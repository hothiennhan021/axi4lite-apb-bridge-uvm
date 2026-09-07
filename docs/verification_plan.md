# Verification Plan — AXI4-Lite to APB Bridge

| | |
|---|---|
| **DUT** | `axi2apb_bridge` |
| **Version** | 0.1 (draft) |
| **Author** | Ho Thien Nhan |
| **Methodology** | UVM 1.2 (SystemVerilog) |
| **Simulator** | Xilinx XSim (Vivado ML Standard) |
| **Status** | In progress |

---

## 1. Introduction

### 1.1 Purpose

This document defines the verification strategy, feature list, test plan, coverage
model and assertion set for the AXI4-Lite to APB protocol bridge. Every verification
item is traceable to a numbered requirement so that coverage closure can be argued
against the specification rather than against an arbitrary percentage target.

### 1.2 DUT Overview

The bridge accepts AXI4-Lite transactions on its slave port and converts each of them
into a single APB transfer on its master port. It is a common building block in an SoC:
a high-throughput AXI interconnect on one side, low-bandwidth configuration peripherals
(timers, UARTs, GPIO, register banks) on the other.

```
                 +----------------------+
   AXI4-Lite --->|                      |---> APB
   (slave port)  |   axi2apb_bridge     |     (master port)
                 |                      |
                 +----------------------+
```

### 1.3 Interface Summary

**AXI4-Lite slave port** (32-bit address, 32-bit data)

| Channel | Signals |
|---|---|
| Write address | `AWVALID`, `AWREADY`, `AWADDR`, `AWPROT` |
| Write data | `WVALID`, `WREADY`, `WDATA`, `WSTRB` |
| Write response | `BVALID`, `BREADY`, `BRESP` |
| Read address | `ARVALID`, `ARREADY`, `ARADDR`, `ARPROT` |
| Read data | `RVALID`, `RREADY`, `RDATA`, `RRESP` |

**APB master port** (APB3)

`PADDR`, `PWRITE`, `PWDATA`, `PSEL`, `PENABLE`, `PRDATA`, `PREADY`, `PSLVERR`

### 1.4 Key Design Assumptions

| ID | Assumption |
|---|---|
| ASM-01 | AXI4-Lite carries no bursts — one transfer per transaction |
| ASM-02 | Bridge supports one outstanding transaction at a time |
| ASM-03 | Data width is fixed at 32 bits on both sides; no width conversion |
| ASM-04 | `AWPROT` / `ARPROT` are passed through or ignored (design choice, documented in RTL) |
| ASM-05 | Reset is active-low, asynchronous assert, synchronous deassert |

---

## 2. Verification Strategy

### 2.1 Approach

Constrained-random, coverage-driven verification using a UVM environment. Directed
tests are used only for scenarios that random stimulus reaches too rarely (reset in
mid-transfer, specific error sequences).

Correctness is checked by three independent mechanisms so that a single bug cannot
slip through one weak checker:

1. **Scoreboard** — transaction-level comparison between the AXI side and the APB side
2. **SVA** — cycle-level protocol compliance on both interfaces
3. **UVM `uvm_error` reporting** — driver/monitor sanity checks

### 2.2 Testbench Architecture

```
                         +---------------------------+
                         |          env              |
                         |                           |
  +------------+         |  +-------------------+    |
  | axi_lite   |<------->|  | scoreboard        |    |
  | agent      |         |  +-------------------+    |
  | (master)   |         |          ^   ^            |
  +------------+         |          |   |            |
        |                |  +-------------------+    |
        |                |  | coverage collector|    |
        v                |  +-------------------+    |
   [ AXI4-Lite IF ]      |                           |
        |                |  +------------+           |
   +----v-----+          |  | apb agent  |           |
   |  DUT     |----------|->| (slave)    |           |
   +----------+          |  +------------+           |
        ^                +---------------------------+
        |
   [ APB IF ] ------> SVA protocol checkers (bound to both interfaces)
```

### 2.3 Verification Components

| Component | Type | Role |
|---|---|---|
| `axi_lite_agent` | Active master | Drives read/write transactions into the DUT |
| `apb_agent` | Active slave | Responds to APB transfers, models a memory, injects wait states and errors |
| `scoreboard` | Analysis | Compares AXI transaction against the corresponding APB transfer |
| `coverage_collector` | Analysis | Samples functional coverage from both monitors |
| `axi_lite_protocol_sva` | Bind module | Cycle-accurate AXI4-Lite protocol checks |
| `apb_protocol_sva` | Bind module | Cycle-accurate APB3 protocol checks |

### 2.4 Completion Criteria

Verification is considered complete when **all** of the following hold:

- All planned tests pass across a 50-seed regression
- Functional coverage ≥ 95%, with every unhit bin explicitly justified in §6.3
- Code coverage (line/toggle/branch) ≥ 90% on the DUT
- Zero unresolved assertion failures
- All filed bugs are either fixed and re-verified, or waived with rationale

---

## 3. Feature List

Each feature is a testable behaviour derived from the AMBA specification or from the
bridge's own design intent.

| ID | Feature | Description | Priority |
|---|---|---|---|
| FEAT-001 | AXI write → APB write | A complete AXI4-Lite write results in exactly one APB write transfer with matching address and data | High |
| FEAT-002 | AXI read → APB read | A complete AXI4-Lite read results in exactly one APB read transfer; `PRDATA` is returned on `RDATA` | High |
| FEAT-003 | APB setup/access phase | `PSEL` asserts for one cycle with `PENABLE` low (setup), then `PENABLE` asserts (access) | High |
| FEAT-004 | Wait state insertion | Access phase extends while `PREADY` is low; bridge holds `PADDR`/`PWDATA`/`PWRITE` stable | High |
| FEAT-005 | Error response mapping | `PSLVERR` high maps to `BRESP`/`RRESP` = `SLVERR`; otherwise `OKAY` | High |
| FEAT-006 | Write strobe handling | `WSTRB` is honoured — either forwarded to the APB slave model or handled per design decision | High |
| FEAT-007 | Address/data channel ordering | Write proceeds regardless of whether `AWVALID` or `WVALID` arrives first | High |
| FEAT-008 | Back-to-back transactions | Consecutive transactions with no idle cycles are handled without data corruption | Medium |
| FEAT-009 | Read/write arbitration | Simultaneous read and write requests are serviced fairly, no starvation, no interleaving of APB phases | Medium |
| FEAT-010 | Reset behaviour | On reset assert, all outputs return to their defined idle values; bridge recovers cleanly afterwards | High |
| FEAT-011 | AXI handshake compliance | `VALID` never deasserts before `READY`; payload stays stable during the handshake | High |
| FEAT-012 | Idle behaviour | With no transaction pending, `PSEL` and `PENABLE` remain low | Low |
| FEAT-013 | Response channel backpressure | Bridge holds `BVALID`/`RVALID` until the master asserts `BREADY`/`RREADY` | Medium |
| FEAT-014 | Reset during active transfer | Reset asserted mid-transaction leaves no dangling state or stuck handshake | Medium |

---

## 4. Test Plan

| Test name | Features covered | Type | Description |
|---|---|---|---|
| `test_smoke` | FEAT-001, 002 | Directed | Single write followed by single read to the same address; earliest bring-up check |
| `test_random_rw` | FEAT-001, 002, 003, 006, 007 | Random | Randomised sequence of reads and writes across the full address range |
| `test_wait_state` | FEAT-004 | Random | APB slave inserts a randomised number of wait states (0–8) per transfer |
| `test_error_resp` | FEAT-005 | Random | APB slave asserts `PSLVERR` with configurable probability; response mapping checked |
| `test_back2back` | FEAT-008, 009 | Random | Zero-delay transaction stream, read and write requests issued concurrently |
| `test_wstrb` | FEAT-006 | Random | All 16 `WSTRB` patterns exercised, including `4'b0000` |
| `test_backpressure` | FEAT-013 | Random | Master delays `BREADY`/`RREADY` by a randomised number of cycles |
| `test_reset_mid_txn` | FEAT-010, 014 | Directed | Reset asserted at randomised points during an active transfer |
| `test_idle` | FEAT-012 | Directed | Extended idle period; checks that no spurious APB activity occurs |
| `test_stress` | All | Random | Long-running randomised soak test; primary regression seed vehicle |

**Regression:** each test runs across 50 seeds. Coverage databases are merged before
the closure report is generated.

---

## 5. Sequence Library

| Sequence | Description |
|---|---|
| `axi_write_seq` | Single write transaction with randomised address, data and `WSTRB` |
| `axi_read_seq` | Single read transaction with randomised address |
| `axi_rand_rw_seq` | Randomised mix of reads and writes, randomised inter-transaction delay |
| `axi_back2back_seq` | Transaction stream with delay constrained to zero |
| `axi_same_addr_seq` | Write then read to the identical address — verifies data integrity end to end |
| `axi_wstrb_sweep_seq` | Directed sweep of all `WSTRB` patterns |

---

## 6. Coverage Plan

### 6.1 Functional Coverage — AXI4-Lite side

**Covergroup `cg_axi_transaction`** — sampled on every completed AXI transaction

| Coverpoint | Bins | Rationale |
|---|---|---|
| `cp_direction` | `READ`, `WRITE` | Both directions must be exercised |
| `cp_addr_range` | `LOW` (0x000–0x3FF), `MID` (0x400–0xBFF), `HIGH` (0xC00–0xFFF) | Ensures the whole decoded space is touched |
| `cp_addr_align` | `ALIGNED`, `UNALIGNED` | Alignment affects `WSTRB` interpretation |
| `cp_wstrb` | 16 bins, one per pattern; `4'b0000` in a separate bin | Byte-enable handling is a classic bug source |
| `cp_resp` | `OKAY`, `SLVERR` | Both response paths must be seen |
| `cp_data` | `ALL_ZERO`, `ALL_ONE`, `WALKING_ONE`, `RANDOM` | Corner data patterns catch stuck-bit issues |
| `cp_delay` | `ZERO`, `SHORT` (1–3), `LONG` (4–15) | Inter-transaction spacing affects the FSM |

**Cross `cx_dir_x_resp`** — `cp_direction` × `cp_resp`
Both read and write error paths must be exercised, not just one of them. A bridge can
easily map `PSLVERR` correctly on writes and drop it on reads.

**Cross `cx_dir_x_wstrb`** — `cp_direction` × `cp_wstrb`
`WSTRB` is only meaningful for writes; the read side of this cross is an illegal
combination and is excluded via `ignore_bins`.

### 6.2 Functional Coverage — APB side

**Covergroup `cg_apb_transfer`** — sampled at the end of each APB access phase

| Coverpoint | Bins | Rationale |
|---|---|---|
| `cp_pwrite` | `READ`, `WRITE` | Direction on the APB side must match the AXI side |
| `cp_wait_states` | `ZERO`, `ONE`, `FEW` (2–4), `MANY` (5–8) | Wait-state handling is the main timing risk |
| `cp_pslverr` | `NO_ERROR`, `ERROR` | Error injection must actually happen |
| `cp_gap` | `BACK2BACK` (0), `SHORT` (1–3), `IDLE` (≥4) | Back-to-back transfers stress the FSM return path |

**Cross `cx_pwrite_x_wait`** — `cp_pwrite` × `cp_wait_states`
Read and write paths can hold different signals during wait states; both need coverage
at every wait-state depth.

**Cross `cx_pwrite_x_err_x_wait`** — `cp_pwrite` × `cp_pslverr` × `cp_wait_states`
An error arriving *after* several wait states is a distinct scenario from an error on a
zero-wait transfer, and is a realistic slave behaviour.

### 6.3 Coverage Exclusions

Every bin that cannot be hit is recorded here with justification. An empty
justification is not acceptable.

| Excluded bin | Reason |
|---|---|
| `cx_dir_x_wstrb[READ, *]` | `WSTRB` has no meaning on read transactions per the AXI4-Lite specification |
| *(to be completed during closure)* | |

### 6.4 Code Coverage

Line, toggle, branch and FSM-state coverage collected on `rtl/axi2apb_bridge.sv`.
Target ≥ 90%. Any uncovered line must be traced to either a missing test or genuinely
unreachable RTL, and the finding recorded.

---

## 7. Assertion Plan

### 7.1 AXI4-Lite Protocol Assertions

| ID | Assertion | Description |
|---|---|---|
| ASRT-A01 | `awvalid_stable` | `AWVALID` remains asserted until `AWREADY` is sampled high |
| ASRT-A02 | `awaddr_stable` | `AWADDR` and `AWPROT` are stable while `AWVALID` is high and `AWREADY` is low |
| ASRT-A03 | `wvalid_stable` | `WVALID` remains asserted until `WREADY` is sampled high |
| ASRT-A04 | `wdata_stable` | `WDATA` and `WSTRB` are stable during the write-data handshake |
| ASRT-A05 | `arvalid_stable` | `ARVALID` remains asserted until `ARREADY` is sampled high |
| ASRT-A06 | `bresp_legal` | `BRESP` only takes the values `OKAY` or `SLVERR` |
| ASRT-A07 | `rresp_legal` | `RRESP` only takes the values `OKAY` or `SLVERR` |
| ASRT-A08 | `no_valid_in_reset` | No `VALID` signal is asserted while reset is low |
| ASRT-A09 | `bvalid_requires_request` | `BVALID` is never asserted without a preceding accepted write |
| ASRT-A10 | `rvalid_requires_request` | `RVALID` is never asserted without a preceding accepted read |

### 7.2 APB Protocol Assertions

| ID | Assertion | Description |
|---|---|---|
| ASRT-P01 | `penable_after_psel` | `PENABLE` asserts exactly one cycle after `PSEL`, never simultaneously |
| ASRT-P02 | `psel_during_penable` | `PSEL` stays high for as long as `PENABLE` is high |
| ASRT-P03 | `addr_stable_in_access` | `PADDR`, `PWRITE` and `PWDATA` are stable throughout the access phase |
| ASRT-P04 | `penable_deassert` | `PENABLE` deasserts in the cycle after `PREADY` is sampled high |
| ASRT-P05 | `no_pslverr_without_pready` | `PSLVERR` is only meaningful when `PREADY` is high |
| ASRT-P06 | `idle_state` | When no transfer is active, both `PSEL` and `PENABLE` are low |

### 7.3 Bridge-Level Assertions

| ID | Assertion | Description |
|---|---|---|
| ASRT-B01 | `single_outstanding` | No new APB transfer starts before the previous one completes |
| ASRT-B02 | `no_deadlock` | Every accepted AXI request produces a response within N cycles |
| ASRT-B03 | `addr_forwarding` | `PADDR` matches the `AWADDR`/`ARADDR` of the request being serviced |

---

## 8. Traceability Matrix

| Feature | Tests | Coverage items | Assertions | Status |
|---|---|---|---|---|
| FEAT-001 | `test_smoke`, `test_random_rw` | `cp_direction`, `cp_addr_range` | ASRT-B03 | Not started |
| FEAT-002 | `test_smoke`, `test_random_rw` | `cp_direction`, `cp_addr_range` | ASRT-B03 | Not started |
| FEAT-003 | `test_random_rw` | `cp_pwrite` | ASRT-P01, P02 | Not started |
| FEAT-004 | `test_wait_state` | `cp_wait_states`, `cx_pwrite_x_wait` | ASRT-P03, P04 | Not started |
| FEAT-005 | `test_error_resp` | `cp_pslverr`, `cx_dir_x_resp` | ASRT-A06, A07, P05 | Not started |
| FEAT-006 | `test_wstrb` | `cp_wstrb`, `cx_dir_x_wstrb` | ASRT-A04 | Not started |
| FEAT-007 | `test_random_rw` | — | ASRT-A01, A03 | Not started |
| FEAT-008 | `test_back2back` | `cp_gap` | ASRT-B01 | Not started |
| FEAT-009 | `test_back2back` | `cp_direction` | ASRT-B01 | Not started |
| FEAT-010 | `test_reset_mid_txn` | — | ASRT-A08 | Not started |
| FEAT-011 | all | — | ASRT-A01–A05 | Not started |
| FEAT-012 | `test_idle` | `cp_gap` | ASRT-P06 | Not started |
| FEAT-013 | `test_backpressure` | `cp_delay` | ASRT-A09, A10 | Not started |
| FEAT-014 | `test_reset_mid_txn` | — | ASRT-B02 | Not started |

---

## 9. Bug Tracking

Bugs are filed as individual markdown files under `docs/bug_reports/` using the naming
convention `BUG-NNN_short_description.md`. Each report contains: symptom, reproduction
seed and test, waveform screenshot, root-cause analysis, fix and re-verification result.

| ID | Summary | Feature | Severity | Status |
|---|---|---|---|---|
| *(to be filled during execution)* | | | | |

---

## 10. Schedule

| Phase | Deliverable |
|---|---|
| 1 | RTL bridge, interfaces, directory structure |
| 2 | AXI4-Lite agent (seq_item, driver, monitor, sequencer) |
| 3 | APB slave agent with memory model and wait-state/error injection |
| 4 | Environment, scoreboard, base test, `test_smoke` passing |
| 5 | Full test list implemented |
| 6 | Functional coverage model and closure |
| 7 | SVA checkers on both interfaces |
| 8 | Regression automation, coverage merge, README and results |

---

## 11. Revision History

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-09-07 | Initial draft — feature list, test plan, coverage and assertion plans |
