//==============================================================================
// apb_sequencer.sv
//==============================================================================

class apb_sequencer extends uvm_sequencer #(apb_txn);

  `uvm_component_utils(apb_sequencer)

  apb_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : apb_sequencer
