# AXI4-Lite to APB Bridge - UVM Verification Environment

[![icarus](https://github.com/hothiennhan021/axi4lite-apb-bridge-uvm/actions/workflows/icarus.yml/badge.svg)](https://github.com/hothiennhan021/axi4lite-apb-bridge-uvm/actions/workflows/icarus.yml)

UVM testbench verifying an AXI4-Lite to APB3 protocol bridge, run on Vivado XSim,
plus a self-checking directed testbench that runs on Icarus Verilog in CI.

## Testbench Architecture

```
  +------------+         +---------------------------+
  | axi_lite   |<------->|          env              |
  | agent      |         |                           |
  | (master)   |         |  +-------------------+    |
  +------------+         |  | scoreboard        |    |
        |                |  +-------------------+    |
        v                |          ^   ^            |
   [ AXI4-Lite IF ]      |          |   |            |
        |                |  +-------------------+    |
   +----v-----+          |  | coverage collector|    |
   |  DUT     |          |  +-------------------+    |
   +----------+          |                           |
        ^                |  +------------+           |
        |                |  | apb agent  |           |
   [ APB IF ] -----------|->| (slave)    |           |
        |                +---------------------------+
        v
   SVA protocol checkers (bound to both interfaces + the bridge itself)
```

`axi_lite_agent` drives randomised read/write traffic (with independent
AW/W timing, so both arrival orders occur); `apb_agent` is a
reactive APB slave with a memory model, randomised wait states and
configurable `PSLVERR` injection. `scoreboard` independently reconstructs
each side's transaction stream and compares them; `coverage_collector`
samples the functional coverage model in `docs/verification_plan.md` §6. SVA
checks cycle-level protocol compliance on the AXI4-Lite side, the APB side,
and the bridge's own FSM (`tb/sva/`).

## Results

> **The table below was measured before the 2026-09-27 changes** (WSTRB
> option (d), AW/W skew in the driver, coverage-collection fixes, new SVA).
> Re-run `python sim/run_regression.py --seeds 5` and a code-coverage pass
> to regenerate it. The UVM code changes compile cleanly (checked with the
> slang SystemVerilog front end against UVM) but have not been run on XSim
> yet.

Measured with `python sim/run_regression.py --seeds 5` (10 tests × 5 seeds
= 50 runs) and a dedicated code-coverage pass on `test_stress`.

| Metric | Value |
|---|---|
| Tests | 10 |
| Regression runs | 50 (10 tests × 5 seeds) |
| Pass rate | 100% (50/50) |
| Functional coverage (overall) | 89.8% (AXI side 85.2%, APB side 94.4%) |
| Code coverage — statement | 100% |
| Code coverage — branch | 96.7% |
| Code coverage — condition | 92.3% |
| Code coverage — toggle | 67.1% |
| Bugs found | 3 (all fixed and re-verified) |

The verification plan's completion criteria (§2.4) call for a 50-seed
regression per test and ≥95% functional / ≥90% code coverage. Both the
functional (89.8%) and the toggle (67.1%) figures above were short of that
bar, and **more seeds would not have closed either gap** — the holes were
structural:

- AXI side 85.2% = (7 × 100% + 33.3% + 33.3%) / 9 coverpoints/crosses.
  `cp_delay` was stuck in its ZERO bin because the monitor never filled in
  `delay`, and `cp_data`'s ALL_ONE / WALKING_ONE bins are practically
  unreachable with random 32-bit data.
- APB side 94.4% = (5 × 100% + 66.7%) / 6: `cp_gap.BACK2BACK` can never be
  hit, because the bridge always spends `RESP` + `IDLE` (PSEL low) between
  transfers.
- Overall 89.8% is the mean of the two.
- Toggle: every address was constrained to `addr[31:12] == 0`, so the upper
  20 bits of `AWADDR`/`ARADDR`/`PADDR`/`addr_q` never toggled; `AWPROT`/
  `ARPROT` are always 0; and since the driver raised `AWVALID` and `WVALID`
  together, `aw_done_q`/`w_done_q` never became 1 (the arrival-order logic,
  FEAT-007, was not exercised at all even though statement coverage read
  100%).

All of these are addressed in v0.3 of the plan: the monitor now measures the
idle gap, AW/W order and response wait; a data-pattern sequence covers the
corner data bins; `BACK2BACK` is an `ignore_bins` with justification; 10%
of addresses span the full 32-bit space; the driver separates AW and W.
Regenerate the numbers with `python sim/run_regression.py --seeds 50` and
`results/cov_report/dashboard.html`.

### Bugs found during bring-up

| ID | Summary | Feature | Severity |
|---|---|---|---|
| [BUG-001](docs/bug_reports/BUG-001_aw_w_done_not_cleared.md) | `aw_done_q`/`w_done_q` never clear, hanging every transaction after the first | FEAT-007/008/009 | Critical |
| [BUG-002](docs/bug_reports/BUG-002_pslverr_not_mapped_on_read.md) | `PSLVERR` dropped on the read path — `RRESP` always `OKAY` | FEAT-005 | High |
| [BUG-003](docs/bug_reports/BUG-003_addr_q_not_latched_on_read.md) | `addr_q`/`PADDR` never latched for reads (stale address forwarded) | FEAT-002 | Critical |

All three were injected deliberately to validate the environment actually
catches them, then fixed; see each report for symptom, root cause, fix and
re-verification evidence. They are kept in the RTL behind macros, so each
one can be reproduced without editing code:
`make TEST=test_smoke DEFINES=INJECT_BUG_001 run` (UVM) or
`make icarus DEFINES=INJECT_BUG_001` (Icarus). CI runs `make icarus_bugs`,
which fails if the directed bench stops catching any of them. `docs/design_decisions.md` also documents several
XSim tool-behaviour quirks found (not RTL bugs) that are easy to mistake for
one if rediscovered.

## Running

Requires Vivado 2022.2 XSim on `PATH` (Git Bash on Windows) and Python 3.
**Vanilla Git for Windows does not include `make`** — `run_regression.py` is
the primary entry point and needs only Python; the `Makefile` is there for
anyone who does have `make` (MSYS2's `pacman -S make`, WSL, etc.) and wants
single-test convenience targets. If neither Python nor `make` is on `PATH`,
Vivado bundles its own Python under
`<Vivado install>/tps/win64/python-3.8.3/python.exe`.

```
cd sim

# Open-source path (Icarus Verilog, no Vivado) - what CI runs:
make icarus                          # self-checking directed bench
make icarus_bugs                     # each INJECT_BUG_00x must be caught

# Primary path - no make required:
python run_regression.py                       # all 10 tests, 5 seeds each (default)
python run_regression.py --seeds 50            # full closure regression per the plan
python run_regression.py --tests test_wstrb,test_idle --seeds 10
python run_regression.py --tests test_smoke --define INJECT_BUG_001   # must FAIL

# If you have make:
make TEST=test_smoke run             # single test, default seed
make TEST=test_random_rw SEED=42 run # single test, specific seed
make cc_run TEST=test_stress         # code coverage (statement/branch/condition/toggle)
make cc_report                       # -> results/codecov_report/dashboard.html
make clean
```

Logs land in `results/logs/`, functional coverage in `results/cov_report/`,
code coverage in `results/codecov_report/`.

## Structure

- `rtl/` - the DUT (`axi2apb_bridge.sv`). WSTRB: a write with a partial
  strobe is answered `SLVERR` and never reaches APB (docs/design_decisions.md §3)
- `tb/agents/` - `axi_lite` (active master) and `apb` (reactive slave) UVM agents
- `tb/env/` - scoreboard, functional coverage collector, environment
- `tb/tests/` - `base_test` plus the 10 tests in `docs/verification_plan.md` §4
- `tb/sva/` - AXI4-Lite, APB and bridge-level protocol assertions (bound, not instantiated)
- `tb/top/` - interfaces and the testbench top module
- `tb/directed/` - `tb_bridge_directed.sv`, self-checking directed bench for Icarus Verilog
- `tb/pkg/` - the UVM package assembling everything above
- `sim/` - `Makefile`, `filelist.f`, `run_regression.py`
- `docs/` - verification plan, design decisions, bug reports
- `results/` - regenerated logs/coverage reports (gitignored)
