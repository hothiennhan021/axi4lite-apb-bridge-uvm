# Design Decisions

This document records the *why* behind decisions in the RTL and the
verification environment that aren't obvious from reading the code — the
trade-offs considered, why the chosen option won, and what it costs.

---

## RTL: `axi2apb_bridge`

### 1. Flag pair (`aw_done_q`/`w_done_q`) instead of an extra FSM state

**Decision:** AWVALID and WVALID can arrive on independent cycles in IDLE.
Rather than adding a fifth state to track "have I seen AW but not W yet" (and
its mirror), the bridge uses two 1-bit flags that latch independently and
both gate entry to `SETUP`.

**Alternatives considered:**
- An explicit `WAIT_W` (or `WAIT_AW`) state, entered from `IDLE` once one
  channel completes, exited to `SETUP` once the other does.

**Why the flag pair won:** the state-based version needs *two* extra states,
not one, if it's going to handle "AW first" and "W first" symmetrically
without one of them silently starving — either that, or a state parameter
tracking which channel arrived first, which is itself extra encoding no
simpler than a flag. The flag pair keeps the state count at four (matching
the natural SETUP/ACCESS/RESP protocol phases 1:1) and makes the "is this
channel done" question a direct signal read (`aw_done_q`) instead of a
state-decode. The cost is two extra flip-flops and the discipline of
remembering to clear them on every path that leaves `IDLE` — which is
exactly the mistake injected and caught in `BUG-001`, so it is a real,
non-hypothetical cost of this choice, not just a style preference.

### 2. Fixed priority, write over read

**Decision:** When both a write and a read are contending for `IDLE`
(`aw_complete && w_complete` vs. `arvalid && arready`), the write always
wins — enforced by gating `arready` on `write_pending`, which is asserted by
any write activity at all (pending flags, or `AWVALID`/`WVALID` this cycle).

**Alternatives considered:** round-robin arbitration, or read-priority.

**Why fixed priority won:** the bridge's whole job is protocol translation
for a single in-order requester per `ASM-02` (one outstanding transaction);
there is no real contention to arbitrate fairly between independent masters
here, only between two channels of the *same* logical request stream. Fixed
priority is the simplest correct answer and the cheapest to verify.

**Downside, stated plainly:** if a real system ever front-ends this bridge
with two independent AXI masters (which ASM-02 does not anticipate but a
future integration might), a write-heavy master can starve a read-only one
indefinitely — nothing in this FSM bounds how long `write_pending` can stay
asserted. `test_back2back` exercises the *low-idle-time* half of this
scenario; it does not, and structurally cannot with a single serial AXI
driver, force `AWVALID` and `ARVALID` simultaneously to directly exercise
the arbitration decision itself (see the testbench-architecture section
below). If this bridge is ever used behind an arbiter/interconnect with
multiple masters, this trade-off should be revisited.

### 3. WSTRB: partial strobe maps to SLVERR (option c)

**Decision:** A write with `WSTRB != 4'b1111` still writes the full 32-bit
word to the APB slave (WSTRB is not forwarded — APB3 has no byte-enable of
its own) but the AXI response is downgraded to `SLVERR`.

**Alternatives considered:**
- (a) Silently ignore WSTRB, always write the full word, always report
  `OKAY`.
- (b) Forward WSTRB on a non-standard APB sideband signal, requiring a
  non-standard APB slave that understands it.

**Why option (c) won:** (a) silently corrupts bytes the master asked to
leave untouched, with no way for the master to ever find out — a correctness
bug dressed up as a simplification. (b) makes the bridge non-compliant with
plain APB3 and pushes the byte-enable problem onto every slave behind it.
Option (c) keeps the APB side a stock, unmodified APB3 slave and gives the
master an honest signal ("I couldn't honor that request exactly") instead of
a wrong one. The cost is that partial-strobe writes are unusable through
this bridge for any master that actually needs byte-level writes — a real
limitation, not just a testbench inconvenience, and worth flagging if this
bridge is reused somewhere that needs true byte-enable support.

### 4. Address/data registered before forwarding to APB

**Decision:** `PADDR`/`PWDATA`/`PWRITE` are driven from registered
`addr_q`/`wdata_q`/`is_write_q`, latched at the AXI handshake, never wired
combinationally from `AWADDR`/`WDATA` directly.

**Why:** AXI permits (in fact requires tolerance for) the master changing
`AWADDR`/`WDATA` the cycle after its own handshake completes, since nothing
in the protocol obligates it to hold those lines stable once `AWREADY`/
`WREADY` was seen. Driving `PADDR` straight from `AWADDR` would let it drift
mid-`ACCESS`, violating `ASRT-P03` (address stable during access) the moment
a real master reused those lines for its next request while this one was
still outstanding. `BUG-003` (address not latched on the read path at all)
demonstrates the failure mode when latching is missed even in the read-only
half of this same mechanism.

---

## Testbench architecture

### 5. Scoreboard: paired analysis FIFOs, not a reference-model predictor

**Decision:** The scoreboard receives completed transactions from the AXI
monitor and the APB monitor into two separate `uvm_tlm_analysis_fifo`s and
pairs them off in arrival order (`axi_fifo.get()` + `apb_fifo.get()`, then
compare), rather than building a predictor that consumes AXI transactions
and produces an *expected* APB transaction to diff against the real one.

**Why FIFOs won:** the bridge's transformation (AXI transaction → APB
transfer) is a 1:1, order-preserving mapping under `ASM-02` — there is no
reordering, splitting, or merging for a predictor to model. A predictor
would duplicate the DUT's own address-latch/response-mapping logic in the
testbench, which (a) is redundant work for a mapping this simple and (b) is
a subtly circular check: if the predictor and the DUT share the same wrong
assumption (e.g., both "forget" WSTRB affects the response), a
predictor-based scoreboard would agree with the bug instead of catching it.
Independently reconstructing *both* sides purely from bus activity, with the
comparison rules written once in the scoreboard from the specification
rather than copied from the RTL, avoids that trap. The FIFO pairing's own
failure mode — silent one-sided desync — is exactly what section 8 below is
about.

### 6. Coverage crosses chosen in the plan

`cx_dir_x_resp` (direction × response) exists specifically because a bridge
can map `PSLVERR` correctly on one AXI channel and drop it on the other —
which is exactly what `BUG-002` did. `cx_pwrite_x_err_x_wait` (APB write ×
error × wait-state depth) exists because an error arriving after several
wait states is a distinct FSM path from an error on a zero-wait transfer:
the RTL takes the same number of cycles through `ACCESS` either way, but a
slave that raises `PSLVERR` only after making the master wait is a
realistic and distinct case from one that flags it immediately, and nothing
about "no wait states" and "some wait states" being separately covered
would catch a bug specific to the combination.

### 7. AXI driver issues one transaction at a time

**Decision:** `axi_lite_driver` pulls one sequence item, fully drives it
(through its response), then pulls the next — it does not run independent
concurrent processes for the write and read channels.

**Why:** this matches `ASM-02` (one outstanding transaction) at the
*environment* level, not just the DUT's — the master this testbench models
genuinely never has two requests in flight, so there is nothing to gain from
concurrent channel-pulling *for closing coverage on this DUT's assumptions*.

**Cost, stated plainly:** it means this environment cannot itself generate
the one stimulus shape that would directly exercise the fixed-priority
arbitration corner discussed in decision 2 above — `AWVALID` and `ARVALID`
asserted in the same cycle. `test_back2back` covers the "no idle cycles
between transactions" half of FEAT-008/009 that a serial driver can produce;
the "simultaneous request, write wins" half of FEAT-009 was checked directly
against the RTL (see `write_pending` in decision 2) rather than through this
environment. A dual-sequencer AXI agent (independent write and read
sequencers, each with its own driver) would close this gap properly; it was
judged disproportionate scope for what a single-master bridge testbench of
this size needs, but is the natural next step if this environment is ever
extended to a multi-master front-end.

### 8. Scoreboard flushes both FIFOs across a reset event

**Decision:** the scoreboard doesn't just pair FIFO entries in a plain
`forever get(); get(); compare();` loop — each round races the FIFO-get pair
against a reset watcher, and on reset it drops whatever was in flight and
flushes both FIFOs once reset clears.

**Why this exists:** the AXI monitor and the APB monitor each decide
independently, from their own bus observation, when a reset-interrupted
transaction should be abandoned rather than published (see `docs/
bug_reports` is not the place for this — it was found during environment
bring-up on `test_reset_mid_txn`, not filed as a DUT bug, since the DUT
itself was already correct at the time). Two independently-clocked
processes making that same "abandon or not" call almost line up, but in a
narrow timing window one can publish one more (or one fewer) transaction
than the other around the exact reset edge — a one-time, one-entry
desync that then silently shifts every pairing after it, since the FIFO
pairing has no other way to notice it's misaligned. Chasing bit-exact
symmetry between the two monitors' abort conditions was judged more fragile
than giving the scoreboard one clear rule: reset means "discard and
resync," applied in exactly one place.

### 9. `bind` targets: `top` and `axi2apb_bridge`, not the interfaces

**Decision:** `axi_lite_protocol_sva` and `apb_protocol_sva` bind into
`tb/top/top.sv` (reaching `axi_vif.*`/`apb_vif.*` by hierarchical name)
rather than into `axi4lite_if`/`apb_if` directly; `bridge_protocol_sva`
binds into `axi2apb_bridge` itself.

**Why:** XSim 2022.2 rejects binding a plain `module` into an `interface`
instance (`ERROR: [VRFC 10-3535] module instantiation ... is not allowed in
interface`) — only module-into-module binds are accepted. Binding into
`top` instead gets identical checking with an identical bind statement; the
only cost is that the SVA files are now written against one specific top
module's name and interface instance names, rather than being reusable
against any module that happens to instantiate `axi4lite_if`. Given this
project has exactly one top module, that portability was not worth losing
the `bind` mechanism (and its "zero RTL/interface changes" property)
entirely.

---

## Tool-behaviour notes worth keeping (not design decisions, but easy to
mistake for one if rediscovered)

These aren't things anyone chose - they're bugs, in either the RTL/testbench
or in XSim's own handling of edge cases, found and fixed during bring-up.
Recorded here because the *symptom* (an apparent hang, or a spurious
mismatch) looks like it could be a design flaw until you trace it back.

- **`while (!cond) @(clk);` vs. `do @(clk); while (!cond);`** — a plain
  `while` checks its condition *before* the first clock wait. If any signal
  in `cond` is still `X` (true before reset deasserts, or before a driver's
  first clocked update lands), `!(X)` is itself `X`, which a `while`
  evaluates as false — the loop's body, including its own `@(clk)`, never
  runs, and a `forever` around it becomes a zero-simulation-time infinite
  loop with no way to progress. Every monitor task in this environment now
  waits for a solid `rst_n===1` before its first bus read, and uses
  `do...while` (which always executes its body — and thus its own `@` —
  at least once) instead of a checked-first `while` for that reason.
- **Deassert reset with a nonblocking assignment.** A *blocking* reset
  deassertion in the same time step as the clock edge that triggers it races
  a clocking block's `#1step` input-skew sampling: some observers can read
  `rst_n` as already 1 at the very edge it changes, one cycle ahead of
  everyone else watching the same net. `<=` instead of `=` for that one
  assignment removes the race entirely.
- **XSim's constraint solver can hang indefinitely on a specific
  `randomize() with { field == value; }` value** — reproduced with
  `axi_wstrb_sweep_seq`: `wstrb == 4'b0000` and `4'b0001` solved instantly,
  `4'b0010` hung the process forever with no error. Assigning the field
  directly after an unconstrained `randomize()` sidesteps the solver for
  that field entirely and is semantically identical when the field has no
  constraint relationship to anything else being randomized.
- **XSim rejects `default disable iff` in a concurrent assertion** with
  "not supported yet for simulation," despite accepting `default clocking`
  in the same block. Every property in this repo's SVA carries its own
  explicit `disable iff (!rst_n)` instead.
- **A Windows path with backslashes, passed as a plain command-line
  argument to `xsim`/`xcrg`, gets corrupted** (`results\cov` arrives as
  `resultscov` on the other end) — these tools appear to route their
  argument list through an internal Tcl layer, which treats `\c`, `\a`,
  etc. as escape sequences. Forward slashes (`Path.as_posix()` from Python,
  or just typing `/` in a shell script) are accepted on Windows and avoid
  the whole class of corruption.
- **`xcrg -db_name` takes at most one value** — it does not accept a
  comma-separated or repeated-flag list, despite that being the documented
  pattern for some other Xilinx tools. To merge every database under a
  directory, omit `-db_name` entirely rather than trying to enumerate them.
