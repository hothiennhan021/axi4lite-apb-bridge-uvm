//==============================================================================
// axi_lite_sequencer.sv
//==============================================================================

class axi_lite_sequencer extends uvm_sequencer #(axi_lite_txn);

  `uvm_component_utils(axi_lite_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : axi_lite_sequencer
