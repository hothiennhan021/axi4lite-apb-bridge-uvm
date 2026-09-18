//==============================================================================
// apb_cfg.sv - configuration object for the APB slave agent
//==============================================================================

class apb_cfg extends uvm_object;

  `uvm_object_utils(apb_cfg)

  uvm_active_passive_enum is_active        = UVM_ACTIVE;
  virtual apb_if           vif;

  int unsigned min_wait_cycles = 0;   // inclusive
  int unsigned max_wait_cycles = 8;   // inclusive - see FEAT-004 / cp_wait_states
  int unsigned error_pct       = 0;   // 0-100, chance a transfer completes with PSLVERR
  int unsigned mem_depth_words = 256; // word-addressable memory model size

  function new(string name = "apb_cfg");
    super.new(name);
  endfunction

endclass : apb_cfg
