# BUG-003: `addr_q` (and therefore PADDR) is never latched for reads

| | |
|---|---|
| **Feature** | FEAT-002 (AXI read to APB read), ASRT-B03 (address forwarding) |
| **Severity** | Critical |
| **Status** | Fixed, re-verified |

## Symptom

`test_random_rw` fails almost immediately with scoreboard `SB_ADDR`
mismatches on every read transaction:

```
[SB_ADDR] address mismatch: axi.addr=1c0 apb.addr=d2d
[SB_ADDR] address mismatch: axi.addr=a86 apb.addr=d2d
[SB_ADDR] address mismatch: axi.addr=7c6 apb.addr=d2d
```

`apb.addr` is stuck at `d2d` across three consecutive (different-address)
reads — it is the address of an earlier *write*, not of any of these reads.
46/100 comparisons failed on seed 1.

`test_smoke`, however, passes cleanly with the exact same RTL bug. It
issues a write to `0x10` followed by a read from the *same* address
(`axi_same_addr_seq`), so the stale, un-updated `addr_q` happens to already
hold the value the read needed — the bug is invisible unless a test reads
from a different address than the preceding write, which is exactly what
`test_random_rw`'s unconstrained address randomisation exercises and a
same-address directed smoke test structurally cannot. This is the
reason the plan calls for both a directed smoke test and a randomised one
rather than treating the smoke test as sufficient on its own.

## Reproduction

```
cd sim
make TEST=test_random_rw SEED=1 run
```

## Root Cause

`rtl/axi2apb_bridge.sv`, the address latch in the `IDLE`-state transaction
register block:

```systemverilog
if (awvalid && awready) addr_q <= awaddr;
```

The `else if (arvalid && arready) addr_q <= araddr;` branch is missing, so
`addr_q` (and therefore `PADDR`, which is wired straight from it) only ever
updates on a write acceptance. A read still transitions the FSM through
SETUP/ACCESS/RESP normally and returns *some* `PRDATA` from the APB memory
model, but at whatever stale address `addr_q` was last holding.

## Fix

Restore the read-side latch alongside the write-side one:

```systemverilog
if (awvalid && awready) addr_q  <= awaddr;
else if (arvalid && arready) addr_q <= araddr;
```

## Re-verification

```
cd sim
python run_regression.py --tests test_smoke,test_random_rw,test_stress --seeds 5
```

All 15 runs pass after the fix. Full regression also passes across all 10
tests. Noted for `docs/design_decisions.md`: this bug is the concrete
justification for keeping `test_random_rw` (and its unconstrained address
randomisation) in the plan rather than relying on `test_smoke` alone.
