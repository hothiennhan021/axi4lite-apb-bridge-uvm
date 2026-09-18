//==============================================================================
// apb_monitor.sv - passively reconstructs completed APB transfers
//==============================================================================

class apb_monitor extends uvm_monitor;

  `uvm_component_utils(apb_monitor)

  virtual apb_if vif;
  uvm_analysis_port #(apb_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface must be set for apb_monitor")
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0]     a, d;
    bit            wr;
    int unsigned   wait_cycles;
    int unsigned   idle_cycles;
    apb_txn        tr;

    // See axi_lite_monitor.sv: bus signals read X before reset deasserts,
    // so don't start interpreting handshakes until it does.
    wait (vif.rst_n === 1'b1);

    forever begin
      // Named so a reset seen mid-transfer can `disable` straight back to
      // the top of the forever loop instead of publishing a transfer that
      // the DUT itself abandoned (FEAT-010/014) - see apb_driver.sv, which
      // makes the matching guarantee that PREADY never asserts for a
      // transfer reset interrupts, so this monitor simply never completes
      // its second wait for one either; the abort here just stops it from
      // misattributing a later, unrelated transfer's completion to the
      // stale address/data captured before reset.
      begin : one_transfer
        // Idle PSEL=0 cycles since the bus was last free - cp_gap.
        // do-while, not while: signals read as X before the first real
        // clock edge would make a plain `while` skip its body entirely (X
        // is neither true nor false, so `!(...)` is also X, which is
        // falsy) - that turned into a zero-time infinite loop. do-while
        // guarantees at least one @(vif.monitor_cb) before the condition
        // is judged.
        idle_cycles = 0;
        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_transfer;
          end
          if (!(vif.monitor_cb.psel && !vif.monitor_cb.penable) && !vif.monitor_cb.psel)
            idle_cycles++;
        end while (!(vif.monitor_cb.psel && !vif.monitor_cb.penable));

        a  = vif.monitor_cb.paddr;
        wr = vif.monitor_cb.pwrite;
        d  = vif.monitor_cb.pwdata;

        wait_cycles = 0;
        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_transfer;
          end
          if (!(vif.monitor_cb.psel && vif.monitor_cb.penable && vif.monitor_cb.pready))
            wait_cycles++;
        end while (!(vif.monitor_cb.psel && vif.monitor_cb.penable && vif.monitor_cb.pready));

        tr = apb_txn::type_id::create("tr");
        tr.addr        = a;
        tr.pwrite      = wr;
        tr.wdata       = d;
        tr.rdata       = vif.monitor_cb.prdata;
        tr.pslverr     = vif.monitor_cb.pslverr;
        tr.wait_cycles = wait_cycles;
        tr.gap_cycles  = idle_cycles;
        ap.write(tr);
      end : one_transfer
    end
  endtask

endclass : apb_monitor
