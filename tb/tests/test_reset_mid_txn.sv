//==============================================================================
// test_reset_mid_txn.sv - FEAT-010, FEAT-014: reset asserted at randomised
// points during an active transfer; bridge must recover cleanly afterwards
// with no dangling state or stuck handshake.
//==============================================================================

class test_reset_mid_txn extends base_test;

  `uvm_component_utils(test_reset_mid_txn)

  function new(string name = "test_reset_mid_txn", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_rw_seq        seq;
    virtual axi4lite_if    avif;
    int unsigned           reset_after_cycles;

    phase.raise_objection(this);
    avif = axi_cfg.vif;

    // join, not join_any/disable fork: killing the reset-injection branch
    // mid-pulse (after driving rst_n low but before reasserting it) would
    // leave the DUT stuck in reset forever, hanging every driver/monitor
    // waiting on rst_n==1 until the global phase timeout. Every reset pulse
    // below always completes; the two branches just run concurrently.
    fork
      begin
        seq = axi_rand_rw_seq::type_id::create("seq");
        seq.num_txns = 40;
        seq.start(env_h.axi_agent.sequencer);
      end
      begin
        repeat (3) begin
          reset_after_cycles = $urandom_range(2, 30);
          repeat (reset_after_cycles) @(posedge avif.clk);

          // Nonblocking, same reason as tb/top/top.sv: a blocking assign
          // landing in the same time step as the triggering posedge would
          // race the monitors'/scoreboard's clocking-block input skew.
          reset_vif.rst_n <= 1'b0;
          repeat (3) @(posedge avif.clk);
          reset_vif.rst_n <= 1'b1;
        end
      end
    join

    // Post-reset sanity: DUT must return to idle (no APB activity) and
    // accept a fresh transaction cleanly.
    repeat (10) @(posedge avif.clk);
    if (env_h.cfg.apb_cfg_h.vif.psel !== 1'b0)
      `uvm_error(get_type_name(), "PSEL still asserted shortly after reset deassert")

    seq = axi_rand_rw_seq::type_id::create("seq_post_reset");
    seq.num_txns = 10;
    seq.start(env_h.axi_agent.sequencer);

    #200ns;
    phase.drop_objection(this);
  endtask

endclass : test_reset_mid_txn
