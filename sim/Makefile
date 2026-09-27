# sim/Makefile - compile, elaborate and run the AXI4-Lite-to-APB bridge
# testbench with Vivado XSim.
#
# Usage (from this directory):
#   make TEST=test_smoke run          # single test, default seed
#   make TEST=test_random_rw SEED=42 run
#   make regression                   # full multi-seed regression (see run_regression.py)
#   make TEST=test_smoke DEFINES=INJECT_BUG_001 run   # re-introduce a documented bug
#   make icarus                       # directed testbench on Icarus Verilog (no Vivado)
#   make icarus_bugs                  # each INJECT_BUG_00x must make it fail
#   make clean

XVLOG     := xvlog
XELAB     := xelab
XSIM      := xsim
XCRG      := xcrg

TEST      ?= test_smoke
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
# space-separated Verilog macros, e.g. DEFINES=INJECT_BUG_002
DEFINES   ?=

FILELIST  := filelist.f
SNAPSHOT  := axi2apb_snap

RESULTS     := ../results
LOG_DIR     := $(RESULTS)/logs
COV_DIR     := $(RESULTS)/cov
COV_RPT     := $(RESULTS)/cov_report
CC_SNAPSHOT := axi2apb_cc_snap
CC_DIR      := $(RESULTS)/codecov
CC_RPT      := $(RESULTS)/codecov_report

.PHONY: compile elab run regression cov_report cc_elab cc_run cc_report icarus icarus_bugs clean

compile:
	$(XVLOG) -sv -L uvm $(addprefix -d ,$(DEFINES)) -f $(FILELIST)

elab: compile
	$(XELAB) -L uvm -timescale 1ns/1ps top -s $(SNAPSHOT)

run: elab
	mkdir -p $(LOG_DIR) $(COV_DIR)
	printf -- '-testplusarg UVM_TESTNAME=$(TEST)\n-testplusarg UVM_VERBOSITY=$(VERBOSITY)\n-sv_seed $(SEED)\n-R\n' > .run_$(TEST)_$(SEED).args
	$(XSIM) $(SNAPSHOT) -f .run_$(TEST)_$(SEED).args \
		-cov_db_dir $(COV_DIR) -cov_db_name $(TEST)_$(SEED) \
		2>&1 | tee $(LOG_DIR)/$(TEST)_$(SEED).log
	rm -f .run_$(TEST)_$(SEED).args

# Full multi-seed regression across every test in verification_plan.md §4 -
# see run_regression.py for seed count, pass/fail table and coverage merge.
regression:
	python run_regression.py

cov_report:
	$(XCRG) -dir $(COV_DIR) -report_dir $(COV_RPT) -report_format html

# Code coverage (line/statement, branch, condition, toggle) on the DUT only.
# Separate from `elab`/`run` above because code-coverage instrumentation is
# baked in at elaboration time via -cc_type and changes the snapshot name.
cc_elab: compile
	$(XELAB) -L uvm -timescale 1ns/1ps top -s $(CC_SNAPSHOT) -cc_type sbct -cc_dir $(CC_DIR)

cc_run: cc_elab
	printf -- '-testplusarg UVM_TESTNAME=$(TEST)\n-sv_seed $(SEED)\n-R\n' > .cc_run.args
	$(XSIM) $(CC_SNAPSHOT) -f .cc_run.args
	rm -f .cc_run.args

cc_report:
	$(XCRG) -cc_db $(CC_SNAPSHOT) -cc_dir $(CC_DIR) -cc_report $(CC_RPT)

# Open-source path: self-checking directed testbench (no UVM) on Icarus
# Verilog. This is what CI runs; the UVM environment above needs XSim.
IVERILOG ?= iverilog
VVP      ?= vvp
IV_DIR   := $(RESULTS)/icarus
IV_SRCS  := ../rtl/axi2apb_bridge.sv ../tb/directed/tb_bridge_directed.sv

icarus:
	mkdir -p $(IV_DIR)
	$(IVERILOG) -g2012 $(addprefix -D,$(DEFINES)) -o $(IV_DIR)/tb.vvp $(IV_SRCS)
	$(VVP) $(IV_DIR)/tb.vvp | tee $(IV_DIR)/tb.log
	@grep -q "^PASSED ALL" $(IV_DIR)/tb.log

# Mutation check: each documented bug, re-injected, must be caught.
icarus_bugs:
	mkdir -p $(IV_DIR)
	@for b in INJECT_BUG_001 INJECT_BUG_002 INJECT_BUG_003; do \
	  $(IVERILOG) -g2012 -D$$b -o $(IV_DIR)/tb_$$b.vvp $(IV_SRCS) || exit 1; \
	  $(VVP) $(IV_DIR)/tb_$$b.vvp > $(IV_DIR)/tb_$$b.log; \
	  if grep -q "^PASSED ALL" $(IV_DIR)/tb_$$b.log; then \
	    echo "$$b: NOT detected"; exit 1; \
	  else \
	    echo "$$b: detected ($$(grep -c '^FAIL' $(IV_DIR)/tb_$$b.log) FAIL line(s))"; \
	  fi; \
	done

clean:
	rm -rf xsim.dir *.jou *.log *.pb *.wdb *.covdb .run_*.args .cc_run.args webtalk* .Xil
	rm -rf $(LOG_DIR) $(COV_DIR) $(COV_RPT) $(CC_DIR) $(CC_RPT) $(IV_DIR)
