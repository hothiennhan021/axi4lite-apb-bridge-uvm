//==============================================================================
// test_stress.sv - long-running randomised soak test; primary regression
// seed vehicle covering all features together.
//==============================================================================

class test_stress extends base_test;

  `uvm_component_utils(test_stress)

  function new(string name = "test_stress", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_apb(apb_cfg c);
    c.min_wait_cycles = 0;
    c.max_wait_cycles = 8;
    c.error_pct       = 15;
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_rw_seq seq;
    phase.raise_objection(this);

    seq = axi_rand_rw_seq::type_id::create("seq");
    seq.num_txns = 500;
    seq.start(env_h.axi_agent.sequencer);

    #500ns;
    phase.drop_objection(this);
  endtask

endclass : test_stress
