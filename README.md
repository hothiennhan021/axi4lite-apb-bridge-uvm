# AXI4-Lite to APB Bridge - UVM Verification Environment

UVM testbench verifying an AXI4-Lite to APB protocol bridge.

## Testbench Architecture

![TB Architecture](docs/tb_architecture.png)

## Results

| Metric | Value |
|---|---|
| Tests | TBD |
| Pass rate | TBD |
| Functional coverage | TBD |
| Bugs found | TBD |

## Running

    cd sim
    make TEST=test_random_rw
    make regression

## Structure

- `rtl/` - DUT
- `tb/`  - UVM environment
- `sim/` - Makefile, regression scripts
- `docs/` - Verification plan, bug reports
