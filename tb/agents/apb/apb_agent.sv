//==============================================================================
// apb_agent.sv
//==============================================================================

class apb_agent extends uvm_agent;

  `uvm_component_utils(apb_agent)

  apb_cfg       cfg;
  apb_driver    driver;
  apb_sequencer sequencer;
  apb_monitor   monitor;

  uvm_analysis_port #(apb_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null && !uvm_config_db#(apb_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_cfg must be set for apb_agent")

    uvm_config_db#(virtual apb_if)::set(this, "monitor", "vif", cfg.vif);
    monitor = apb_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      uvm_config_db#(virtual apb_if)::set(this, "driver", "vif", cfg.vif);
      uvm_config_db#(apb_cfg)::set(this, "driver", "cfg", cfg);
      uvm_config_db#(apb_cfg)::set(this, "sequencer", "cfg", cfg);

      driver    = apb_driver::type_id::create("driver", this);
      sequencer = apb_sequencer::type_id::create("sequencer", this);
      sequencer.cfg = cfg;

      uvm_config_db#(uvm_object_wrapper)::set(this, "sequencer.run_phase",
        "default_sequence", apb_default_resp_seq::type_id::get());
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = monitor.ap;
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : apb_agent
