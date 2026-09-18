//==============================================================================
// test_back2back.sv - FEAT-008, FEAT-009: zero-delay transaction stream.
//
// Note: the AXI agent's driver issues one transaction at a time from a
// single sequencer (see docs/design_decisions.md), so this test exercises
// the "no idle cycles between transactions" half of FEAT-008/009 - it does
// not itself force AWVALID and ARVALID to assert in the same cycle. That
// corner of the fixed-priority arbitration was validated directly against
// the RTL (see the bridge's write_pending logic) rather than through this
// environment; documented as a known coverage gap.
//==============================================================================

class test_back2back extends base_test;

  `uvm_component_utils(test_back2back)

  function new(string name = "test_back2back", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_apb(apb_cfg c);
    c.min_wait_cycles = 0;
    c.max_wait_cycles = 2;
    c.error_pct       = 0;
  endfunction

  task run_phase(uvm_phase phase);
    axi_back2back_seq seq;
    phase.raise_objection(this);

    seq = axi_back2back_seq::type_id::create("seq");
    seq.num_txns = 60;
    seq.start(env_h.axi_agent.sequencer);

    #200ns;
    phase.drop_objection(this);
  endtask

endclass : test_back2back
