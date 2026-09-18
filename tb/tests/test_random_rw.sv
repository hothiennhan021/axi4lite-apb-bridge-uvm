//==============================================================================
// test_random_rw.sv - FEAT-001,002,003,006,007: randomised mix of reads and
// writes across the full decoded address range.
//==============================================================================

class test_random_rw extends base_test;

  `uvm_component_utils(test_random_rw)

  function new(string name = "test_random_rw", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_rw_seq seq;
    phase.raise_objection(this);

    seq = axi_rand_rw_seq::type_id::create("seq");
    seq.num_txns = 100;
    seq.start(env_h.axi_agent.sequencer);

    #200ns;
    phase.drop_objection(this);
  endtask

endclass : test_random_rw
