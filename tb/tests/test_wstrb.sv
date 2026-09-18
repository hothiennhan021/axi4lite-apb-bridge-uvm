//==============================================================================
// test_wstrb.sv - FEAT-006: all 16 WSTRB patterns exercised, including 0000.
//==============================================================================

class test_wstrb extends base_test;

  `uvm_component_utils(test_wstrb)

  function new(string name = "test_wstrb", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_wstrb_sweep_seq seq;
    phase.raise_objection(this);

    seq = axi_wstrb_sweep_seq::type_id::create("seq");
    seq.start(env_h.axi_agent.sequencer);

    #100ns;
    phase.drop_objection(this);
  endtask

endclass : test_wstrb
