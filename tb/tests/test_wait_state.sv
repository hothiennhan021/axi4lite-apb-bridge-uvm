//==============================================================================
// test_wait_state.sv - FEAT-004: APB slave inserts a randomised number of
// wait states (0-8) per transfer.
//==============================================================================

class test_wait_state extends base_test;

  `uvm_component_utils(test_wait_state)

  function new(string name = "test_wait_state", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_apb(apb_cfg c);
    c.min_wait_cycles = 0;
    c.max_wait_cycles = 8;
    c.error_pct       = 0;
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_rw_seq seq;
    phase.raise_objection(this);

    seq = axi_rand_rw_seq::type_id::create("seq");
    seq.num_txns = 80;
    seq.start(env_h.axi_agent.sequencer);

    #200ns;
    phase.drop_objection(this);
  endtask

endclass : test_wait_state
