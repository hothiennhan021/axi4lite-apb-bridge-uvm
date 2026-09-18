//==============================================================================
// axi_lite_cfg.sv - configuration object for the AXI4-Lite master agent
//==============================================================================

class axi_lite_cfg extends uvm_object;

  `uvm_object_utils(axi_lite_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual axi4lite_if      vif;

  function new(string name = "axi_lite_cfg");
    super.new(name);
  endfunction

endclass : axi_lite_cfg
