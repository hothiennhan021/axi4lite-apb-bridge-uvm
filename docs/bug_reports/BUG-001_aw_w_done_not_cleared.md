# BUG-001: `aw_done_q`/`w_done_q` never clear, permanently blocking every transaction after the first

| | |
|---|---|
| **Feature** | FEAT-007 (address/data channel ordering), FEAT-008 (back-to-back), FEAT-009 (arbitration) |
| **Severity** | Critical |
| **Status** | Fixed, re-verified |

## Symptom

Every test that issues more than one AXI4-Lite transaction hangs and hits the
global `PH_TIMEOUT` fatal at 200us. `test_smoke` (a single write followed by
a single read) is enough to reproduce it — the read never completes. In the
same run, `ASRT-A09` (`BVALID asserted with no accepted write outstanding`)
fires on nearly every clock cycle for the rest of the simulation once the
first write completes.

## Reproduction

```
cd sim
make TEST=test_smoke SEED=1 run
```

Any seed reproduces it — the bug does not depend on randomisation, only on
issuing a second transaction. Confirmed on seeds 1-3 of `test_smoke`,
`test_back2back` and `test_random_rw`; 9/9 runs failed, 0/9 passed.

## Root Cause

`rtl/axi2apb_bridge.sv`, the transaction-register block that latches
`aw_done_q`/`w_done_q` while in `IDLE`:

```systemverilog
aw_done_q <= aw_complete;
w_done_q  <= w_complete;
```

`aw_complete` is defined as `aw_done_q | (awvalid & awready)` — once
`aw_done_q` becomes 1 after the first write's address phase, `aw_complete`
stays 1 forever (it depends on its own registered output with no way back to
0), so this line keeps re-latching `aw_done_q <= 1` on every subsequent
cycle. The same happens to `w_done_q`. The flags were only ever supposed to
be cleared the cycle the FSM leaves `IDLE` for a new transaction; that clear
was missing.

With `aw_done_q`/`w_done_q` stuck at 1, `write_pending` (`aw_done_q |
w_done_q | awvalid | wvalid`) is permanently 1, which permanently deasserts
`arready` (`(state_q == IDLE) && !write_pending`). Any read issued after the
first write can never be accepted, so the driver's `while (!vif.driver_cb.
arready) @(...)` blocks forever — hence the timeout. The `ASRT-A09` storm is
a secondary symptom of the same stuck flags feeding back into the FSM's
write-acceptance logic.

## Fix

Restore the clear-on-leave-`IDLE` branch so the flags only persist while the
FSM is still assembling the current transaction, and reset to 0 the moment
it moves on:

```systemverilog
if (state_d == IDLE) begin
  aw_done_q <= aw_complete;
  w_done_q  <= w_complete;
end else begin
  aw_done_q <= 1'b0;
  w_done_q  <= 1'b0;
end
```

## Re-verification

```
cd sim
python run_regression.py --tests test_smoke,test_back2back,test_random_rw,test_stress --seeds 5
```

All 20 runs pass (0 UVM errors/fatals, 0 SVA failures) after the fix. Full
regression (`python run_regression.py`) also passes across all 10 tests.
