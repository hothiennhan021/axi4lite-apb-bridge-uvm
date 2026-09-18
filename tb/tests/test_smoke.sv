//==============================================================================
// test_smoke.sv - FEAT-001, FEAT-002: single write then single read to the
// same address. Earliest bring-up check.
//==============================================================================

class test_smoke extends base_test;

  `uvm_component_utils(test_smoke)

  function new(string name = "test_smoke", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_same_addr_seq seq;
    phase.raise_objection(this);

    seq = axi_same_addr_seq::type_id::create("seq");
    if (!seq.randomize() with { addr == 32'h0000_0010; })
      `uvm_error(get_type_name(), "randomize failed")
    seq.start(env_h.axi_agent.sequencer);

    #100ns;
    phase.drop_objection(this);
  endtask

endclass : test_smoke
