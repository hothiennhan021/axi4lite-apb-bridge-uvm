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
  rand int unsigned     aw_delay;  // write only: cycles before AWVALID is raised
  rand int unsigned     w_delay;   // write only: cycles before WVALID is raised
                                   // (aw_delay != w_delay -> AW and W arrive on
                                   // different cycles, FEAT-007)
  rand bit              full_addr; // 1: address anywhere in the 32-bit space

  // Observed by the monitor (not driven): see axi_lite_monitor.sv
  int                   aw_w_skew;  // W handshake cycle - AW handshake cycle
  int unsigned          resp_wait;  // cycles BVALID/RVALID was high with READY low

  // Response, filled in by the driver after the transaction completes.
  bit [1:0]             resp;

  constraint c_delay_range {
    delay inside {[0:15]};
  }

  constraint c_channel_skew {
    aw_delay inside {[0:3]};
    w_delay  inside {[0:3]};
  }

  // Mostly a 4KB window (the LOW/MID/HIGH address-range coverage bins in
  // verification_plan.md section 6.1), sometimes the full 32-bit space so
  // the upper address bits are exercised too (ABOVE_4K bin).
  constraint c_addr_decode {
    full_addr dist { 1'b0 := 9, 1'b1 := 1 };
    !full_addr -> addr[31:12] == '0;
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
    `uvm_field_int(aw_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(w_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(full_addr, UVM_ALL_ON)
    `uvm_field_int(aw_w_skew, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(resp_wait, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(resp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi_lite_txn");
    super.new(name);
  endfunction

endclass : axi_lite_txn
