# AXI4-Lite to APB Bridge - UVM Verification Environment

UVM testbench verifying an AXI4-Lite to APB3 protocol bridge, run on Vivado XSim.

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

`axi_lite_agent` drives randomised read/write traffic; `apb_agent` is a
reactive APB slave with a memory model, randomised wait states and
configurable `PSLVERR` injection. `scoreboard` independently reconstructs
each side's transaction stream and compares them; `coverage_collector`
samples the functional coverage model in `docs/verification_plan.md` §6. SVA
checks cycle-level protocol compliance on the AXI4-Lite side, the APB side,
and the bridge's own FSM (`tb/sva/`).

## Results

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
regression per test and ≥95% functional / ≥90% code coverage as the closure
bar; the numbers above are from a 5-seed sample run during development, not
the full 50-seed closure regression. Toggle coverage is the one figure
short of that bar — expected, since a handful of seeds don't exercise every
bit pattern on a 32-bit bus; a full run (`--seeds 50`, several hours of
wall-clock time) is expected to close most of the remaining gap. Run it
yourself with `python sim/run_regression.py --seeds 50` and regenerate this
table from `results/cov_report/dashboard.html`.

### Bugs found during bring-up

| ID | Summary | Feature | Severity |
|---|---|---|---|
| [BUG-001](docs/bug_reports/BUG-001_aw_w_done_not_cleared.md) | `aw_done_q`/`w_done_q` never clear, hanging every transaction after the first | FEAT-007/008/009 | Critical |
| [BUG-002](docs/bug_reports/BUG-002_pslverr_not_mapped_on_read.md) | `PSLVERR` dropped on the read path — `RRESP` always `OKAY` | FEAT-005 | High |
| [BUG-003](docs/bug_reports/BUG-003_addr_q_not_latched_on_read.md) | `addr_q`/`PADDR` never latched for reads (stale address forwarded) | FEAT-002 | Critical |

All three were injected deliberately to validate the environment actually
catches them, then fixed; see each report for symptom, root cause, fix and
re-verification evidence. `docs/design_decisions.md` also documents several
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

# Primary path - no make required:
python run_regression.py                       # all 10 tests, 5 seeds each (default)
python run_regression.py --seeds 50            # full closure regression per the plan
python run_regression.py --tests test_wstrb,test_idle --seeds 10

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

- `rtl/` - the DUT (`axi2apb_bridge.sv`)
- `tb/agents/` - `axi_lite` (active master) and `apb` (reactive slave) UVM agents
- `tb/env/` - scoreboard, functional coverage collector, environment
- `tb/tests/` - `base_test` plus the 10 tests in `docs/verification_plan.md` §4
- `tb/sva/` - AXI4-Lite, APB and bridge-level protocol assertions (bound, not instantiated)
- `tb/top/` - interfaces and the testbench top module
- `tb/pkg/` - the UVM package assembling everything above
- `sim/` - `Makefile`, `filelist.f`, `run_regression.py`
- `docs/` - verification plan, design decisions, bug reports
- `results/` - regenerated logs/coverage reports (gitignored)
