//==============================================================================
// test_idle.sv - FEAT-012: extended idle period; PSEL/PENABLE must stay low
// with no transaction pending.
//==============================================================================

class test_idle extends base_test;

  `uvm_component_utils(test_idle)

  function new(string name = "test_idle", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    repeat (200) @(posedge env_h.cfg.apb_cfg_h.vif.clk);

    if (env_h.cfg.apb_cfg_h.vif.psel !== 1'b0 || env_h.cfg.apb_cfg_h.vif.penable !== 1'b0)
      `uvm_error(get_type_name(), "PSEL/PENABLE asserted with no pending transaction")

    phase.drop_objection(this);
  endtask

endclass : test_idle
