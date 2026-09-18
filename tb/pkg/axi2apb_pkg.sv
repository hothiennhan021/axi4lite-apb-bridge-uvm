//==============================================================================
// axi2apb_pkg.sv - single UVM package assembling the whole testbench.
//
// Files are `included in dependency order (base classes before things that
// extend or reference them). Include directories for each subdirectory are
// passed to xvlog via -i (see sim/filelist.f).
//==============================================================================

package axi2apb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // AXI4-Lite master agent
  `include "axi_lite_txn.sv"
  `include "axi_lite_cfg.sv"
  `include "axi_lite_sequencer.sv"
  `include "axi_lite_driver.sv"
  `include "axi_lite_monitor.sv"
  `include "axi_lite_seq_lib.sv"
  `include "axi_lite_agent.sv"

  // APB slave agent
  `include "apb_txn.sv"
  `include "apb_cfg.sv"
  `include "apb_sequencer.sv"
  `include "apb_driver.sv"
  `include "apb_monitor.sv"
  `include "apb_seq_lib.sv"
  `include "apb_agent.sv"

  // Environment
  `include "scoreboard.sv"
  `include "coverage_collector.sv"
  `include "env.sv"

  // Tests
  `include "base_test.sv"
  `include "test_smoke.sv"
  `include "test_random_rw.sv"
  `include "test_wait_state.sv"
  `include "test_error_resp.sv"
  `include "test_back2back.sv"
  `include "test_wstrb.sv"
  `include "test_backpressure.sv"
  `include "test_reset_mid_txn.sv"
  `include "test_idle.sv"
  `include "test_stress.sv"

endpackage : axi2apb_pkg
