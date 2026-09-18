# BUG-002: PSLVERR is dropped on the read path — RRESP always reports OKAY

| | |
|---|---|
| **Feature** | FEAT-005 (error response mapping) |
| **Severity** | High |
| **Status** | Fixed, re-verified |

## Symptom

`test_error_resp` and `test_stress` (the two tests that configure the APB
slave to inject `PSLVERR`) fail with scoreboard `SB_RESP` mismatches, always
in the same shape:

```
[SB_RESP] response mismatch: axi.resp=0 expected=10 (apb.pslverr=1, wstrb=0000)
```

`axi.resp=0` is `OKAY`; the scoreboard expected `10` (`SLVERR`) because the
APB slave signalled `pslverr=1` for that transfer. Every failing comparison
is a read (writes correctly report `SLVERR` when the APB slave injects an
error). 9/80 comparisons failed on `test_error_resp` seed 1; write-side error
injection at the same 30% rate was completely clean.

## Reproduction

```
cd sim
make TEST=test_error_resp SEED=1 run
```

## Root Cause

`rtl/axi2apb_bridge.sv`, the `err_q` latch:

```systemverilog
err_q <= is_write_q ? (pslverr | (wstrb_q != 4'b1111)) : 1'b0;
```

The `is_write_q ? ... : 1'b0` structure only ever lets `err_q` capture
`pslverr` on the write side; for a read (`is_write_q == 0`), `err_q` is
forced to `1'b0` regardless of what the APB slave drove on `pslverr`. Since
`bresp`/`rresp` are both derived from the same `err_q`, `RRESP` therefore
always reports `OKAY`, silently swallowing every read-side `PSLVERR`.

## Fix

`PSLVERR` must be captured unconditionally; only the WSTRB-derived error
(option (c) — see `docs/design_decisions.md`) is write-only:

```systemverilog
err_q <= pslverr | (is_write_q && (wstrb_q != 4'b1111));
```

## Re-verification

```
cd sim
python run_regression.py --tests test_error_resp,test_stress --seeds 5
```

All 10 runs pass with 0 mismatches after the fix (read-side `SLVERR` is now
correctly observed in `cx_dir_x_resp` coverage for both `READ` and `WRITE`).
Full regression also passes across all 10 tests.
