//==============================================================================
// axi_lite_agent.sv
//==============================================================================

class axi_lite_agent extends uvm_agent;

  `uvm_component_utils(axi_lite_agent)

  axi_lite_cfg       cfg;
  axi_lite_driver    driver;
  axi_lite_sequencer sequencer;
  axi_lite_monitor   monitor;

  uvm_analysis_port #(axi_lite_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null && !uvm_config_db#(axi_lite_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_lite_cfg must be set for axi_lite_agent")

    uvm_config_db#(virtual axi4lite_if)::set(this, "monitor", "vif", cfg.vif);
    monitor = axi_lite_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      uvm_config_db#(virtual axi4lite_if)::set(this, "driver", "vif", cfg.vif);
      driver    = axi_lite_driver::type_id::create("driver", this);
      sequencer = axi_lite_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = monitor.ap;
    if (cfg.is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : axi_lite_agent
