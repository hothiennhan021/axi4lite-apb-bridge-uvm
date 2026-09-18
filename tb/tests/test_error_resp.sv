//==============================================================================
// test_error_resp.sv - FEAT-005: APB slave asserts PSLVERR with configurable
// probability; response mapping is checked by the scoreboard.
//==============================================================================

class test_error_resp extends base_test;

  `uvm_component_utils(test_error_resp)

  function new(string name = "test_error_resp", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_apb(apb_cfg c);
    c.min_wait_cycles = 0;
    c.max_wait_cycles = 4;
    c.error_pct       = 30;
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

endclass : test_error_resp
