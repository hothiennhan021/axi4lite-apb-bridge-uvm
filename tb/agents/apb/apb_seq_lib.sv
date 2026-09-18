//==============================================================================
// apb_seq_lib.sv - sequence library for the APB slave agent
//
// apb_default_resp_seq is the agent's default sequence: it runs forever,
// handing the driver one randomised response descriptor (wait_cycles,
// inject_error) per APB transfer, constrained by the agent's apb_cfg.
//==============================================================================

class apb_default_resp_seq extends uvm_sequence #(apb_txn);

  `uvm_object_utils(apb_default_resp_seq)
  `uvm_declare_p_sequencer(apb_sequencer)

  function new(string name = "apb_default_resp_seq");
    super.new(name);
  endfunction

  task body();
    forever begin
      req = apb_txn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            wait_cycles inside {[p_sequencer.cfg.min_wait_cycles : p_sequencer.cfg.max_wait_cycles]};
            inject_error dist {
              1'b1 := p_sequencer.cfg.error_pct,
              1'b0 := (100 - p_sequencer.cfg.error_pct)
            };
          })
        `uvm_error(get_type_name(), "randomize failed")
      finish_item(req);
    end
  endtask

endclass : apb_default_resp_seq
