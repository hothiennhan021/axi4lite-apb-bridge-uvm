//==============================================================================
// test_backpressure.sv - FEAT-013: master delays BREADY/RREADY by a
// randomised number of cycles; DUT must hold BVALID/RVALID until then.
//==============================================================================

class test_backpressure extends base_test;

  `uvm_component_utils(test_backpressure)

  function new(string name = "test_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_backpressure_seq seq;
    phase.raise_objection(this);

    seq = axi_backpressure_seq::type_id::create("seq");
    seq.num_txns = 60;
    seq.start(env_h.axi_agent.sequencer);

    #200ns;
    phase.drop_objection(this);
  endtask

endclass : test_backpressure
