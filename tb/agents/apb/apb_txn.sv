//==============================================================================
// apb_txn.sv - sequence item for the APB slave agent
//
// Doubles as two things depending on who produced it:
//   - a response descriptor: the sequencer supplies wait_cycles/inject_error,
//     randomised by apb_default_resp_seq from the agent's cfg knobs
//   - a completed-transfer record: the monitor fills in addr/pwrite/wdata/
//     rdata/pslverr and publishes it on the analysis port
//==============================================================================

class apb_txn extends uvm_sequence_item;

  // Request side (captured from the bus by the driver/monitor)
  bit [31:0] addr;
  bit        pwrite;
  bit [31:0] wdata;

  // Response side (randomised by the sequence, applied by the driver)
  rand int unsigned wait_cycles;
  rand bit          inject_error;

  // Result (filled in by the driver for reads, mirrored by the monitor)
  bit [31:0] rdata;
  bit        pslverr;

  // Observed by the monitor only: idle PSEL=0 cycles immediately before this
  // transfer's SETUP phase (cp_gap in verification_plan.md section 6.2).
  int unsigned gap_cycles;

  `uvm_object_utils_begin(apb_txn)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(pwrite, UVM_ALL_ON)
    `uvm_field_int(wdata, UVM_ALL_ON)
    `uvm_field_int(wait_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(inject_error, UVM_ALL_ON)
    `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_field_int(pslverr, UVM_ALL_ON)
    `uvm_field_int(gap_cycles, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "apb_txn");
    super.new(name);
  endfunction

endclass : apb_txn
