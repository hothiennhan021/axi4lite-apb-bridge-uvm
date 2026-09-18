//==============================================================================
// axi_lite_txn.sv - sequence item for the AXI4-Lite master agent
//==============================================================================

typedef enum { AXI_READ, AXI_WRITE } axi_dir_e;

class axi_lite_txn extends uvm_sequence_item;

  rand axi_dir_e        dir;
  rand bit [31:0]       addr;
  rand bit [31:0]       data;     // write: data to send. read: filled in with RDATA by the driver.
  rand bit [3:0]        wstrb;    // write only, ignored for reads
  rand int unsigned     delay;    // idle cycles inserted before this transaction is driven
  rand int unsigned     resp_ready_delay; // cycles to hold BREADY/RREADY low after the
                                           // address/data handshake, before asserting it
                                           // (FEAT-013 backpressure)

  // Response, filled in by the driver after the transaction completes.
  bit [1:0]             resp;

  constraint c_delay_range {
    delay inside {[0:15]};
  }

  // Bridge/APB slave model decode a 4KB window (matches the LOW/MID/HIGH
  // address-range coverage bins in verification_plan.md section 6.1).
  constraint c_addr_decode {
    addr[31:12] == '0;
  }

  // Sequences that need a specific WSTRB (sweep, byte-enable corners) override
  // this per-item with `randomize() with { wstrb == ...; }` - kept soft so
  // that override always wins without needing `uvm_active_passive` gymnastics.
  constraint c_wstrb_default {
    soft wstrb == 4'b1111;
  }

  constraint c_resp_ready_delay_default {
    soft resp_ready_delay == 0;
  }

  `uvm_object_utils_begin(axi_lite_txn)
    `uvm_field_enum(axi_dir_e, dir, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(wstrb, UVM_ALL_ON | UVM_BIN)
    `uvm_field_int(delay, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(resp_ready_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(resp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi_lite_txn");
    super.new(name);
  endfunction

endclass : axi_lite_txn
