//==============================================================================
// coverage_collector.sv - functional coverage per verification_plan.md §6
//==============================================================================

`uvm_analysis_imp_decl(_axi)
`uvm_analysis_imp_decl(_apb)

class coverage_collector extends uvm_subscriber #(axi_lite_txn);

  `uvm_component_utils(coverage_collector)

  uvm_analysis_imp_axi #(axi_lite_txn, coverage_collector) axi_imp;
  uvm_analysis_imp_apb #(apb_txn, coverage_collector)      apb_imp;

  covergroup cg_axi_transaction with function sample(axi_lite_txn tr);
    option.per_instance = 1;

    cp_direction: coverpoint tr.dir {
      bins READ  = {AXI_READ};
      bins WRITE = {AXI_WRITE};
    }

    cp_addr_range: coverpoint tr.addr {
      bins LOW      = {[32'h000:32'h3FF]};
      bins MID      = {[32'h400:32'hBFF]};
      bins HIGH     = {[32'hC00:32'hFFF]};
      bins ABOVE_4K = {[32'h0000_1000:32'hFFFF_FFFF]}; // upper address bits
    }

    cp_addr_align: coverpoint tr.addr[1:0] {
      bins ALIGNED   = {2'b00};
      bins UNALIGNED = {[2'b01:2'b11]};
    }

    // writes only: the monitor fills wstrb with 0 for reads, which would
    // otherwise hit ZERO/PATTERN[0] without any write ever using them
    cp_wstrb: coverpoint tr.wstrb iff (tr.dir == AXI_WRITE) {
      bins ZERO = {4'b0000};
      bins PATTERN[16] = {[4'b0000:4'b1111]};
    }

    cp_resp: coverpoint tr.resp {
      bins OKAY   = {2'b00};
      bins SLVERR = {2'b10};
    }

    cp_data: coverpoint tr.data {
      bins ALL_ZERO    = {32'h0000_0000};
      bins ALL_ONE     = {32'hFFFF_FFFF};
      bins WALKING_ONE = {32'h0000_0001, 32'h0000_0002, 32'h0000_0004, 32'h0000_0008,
                           32'h0000_0010, 32'h0000_0020, 32'h0000_0040, 32'h0000_0080,
                           32'h0000_0100, 32'h0000_0200, 32'h0000_0400, 32'h0000_0800,
                           32'h0000_1000, 32'h0000_2000, 32'h0000_4000, 32'h0000_8000,
                           32'h0001_0000, 32'h0002_0000, 32'h0004_0000, 32'h0008_0000,
                           32'h0010_0000, 32'h0020_0000, 32'h0040_0000, 32'h0080_0000,
                           32'h0100_0000, 32'h0200_0000, 32'h0400_0000, 32'h0800_0000,
                           32'h1000_0000, 32'h2000_0000, 32'h4000_0000, 32'h8000_0000};
      bins RANDOM      = default;
    }

    // Observed idle cycles before the transaction (axi_lite_monitor.sv).
    // The driver always needs one cycle to drop BREADY/RREADY and fetch the
    // next item, so the tightest spacing it can produce reads as 1.
    cp_delay: coverpoint tr.delay {
      bins ZERO  = {[0:1]};
      bins SHORT = {[2:4]};
      bins LONG  = {[5:$]};
    }

    // FEAT-007: order in which AW and W handshake
    cp_aw_w_order: coverpoint tr.aw_w_skew iff (tr.dir == AXI_WRITE) {
      bins SAME_CYCLE = {0};
      bins AW_FIRST   = {[1:$]};
      bins W_FIRST    = {[$:-1]};
    }

    // FEAT-013: cycles BVALID/RVALID was held waiting for BREADY/RREADY
    cp_resp_wait: coverpoint tr.resp_wait {
      bins NONE = {0};
      bins FEW  = {[1:3]};
      bins MANY = {[4:$]};
    }

    cx_dir_x_resp: cross cp_direction, cp_resp;

    cx_dir_x_resp_wait: cross cp_direction, cp_resp_wait;

    cx_dir_x_wstrb: cross cp_direction, cp_wstrb {
      ignore_bins read_wstrb = binsof(cp_direction) intersect {AXI_READ};
    }
  endgroup

  covergroup cg_apb_transfer with function sample(apb_txn tr, int unsigned wait_cycles);
    option.per_instance = 1;

    cp_pwrite: coverpoint tr.pwrite {
      bins READ  = {1'b0};
      bins WRITE = {1'b1};
    }

    cp_wait_states: coverpoint wait_cycles {
      bins ZERO = {0};
      bins ONE  = {1};
      bins FEW  = {[2:4]};
      bins MANY = {[5:8]};
    }

    cp_pslverr: coverpoint tr.pslverr {
      bins NO_ERROR = {1'b0};
      bins ERROR    = {1'b1};
    }

    // BACK2BACK (0) is unreachable by design: the bridge always passes
    // through RESP and IDLE (PSEL low) between two transfers, so the gap is
    // at least 2 cycles. Excluded per verification_plan.md section 6.3.
    cp_gap: coverpoint tr.gap_cycles {
      ignore_bins BACK2BACK = {0};
      bins SHORT     = {[1:3]};
      bins IDLE      = {[4:$]};
    }

    cx_pwrite_x_wait: cross cp_pwrite, cp_wait_states;

    cx_pwrite_x_err_x_wait: cross cp_pwrite, cp_pslverr, cp_wait_states;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_axi_transaction = new();
    cg_apb_transfer    = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_imp = new("axi_imp", this);
    apb_imp = new("apb_imp", this);
  endfunction

  // uvm_subscriber's required write() - unused, real work happens in
  // write_axi/write_apb below; kept only to satisfy the base class.
  function void write(axi_lite_txn t);
  endfunction

  function void write_axi(axi_lite_txn tr);
    cg_axi_transaction.sample(tr);
  endfunction

  function void write_apb(apb_txn tr);
    // apb_monitor derives wait_cycles independently by counting ACCESS-phase
    // cycles until PREADY, rather than trusting the driver's own value.
    cg_apb_transfer.sample(tr, tr.wait_cycles);
  endfunction

endclass : coverage_collector
