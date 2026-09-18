//==============================================================================
// axi_lite_monitor.sv - passively reconstructs completed AXI4-Lite
// transactions and publishes them on an analysis port.
//
// Write and read channels are watched independently since they are separate
// signal groups on the bus; the DUT's own single-outstanding behaviour means
// they never actually overlap, but the monitor does not rely on that.
//==============================================================================

class axi_lite_monitor extends uvm_monitor;

  `uvm_component_utils(axi_lite_monitor)

  virtual axi4lite_if vif;
  uvm_analysis_port #(axi_lite_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface must be set for axi_lite_monitor")
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    // Bus signals read X before reset deasserts (nothing has driven them
    // yet); evaluating handshake conditions against X can misbehave rather
    // than cleanly reading as "not yet asserted", so wait for a solid reset
    // deassertion before watching for any handshake.
    wait (vif.rst_n === 1'b1);
    fork
      watch_write();
      watch_read();
    join
  endtask

  task watch_write();
    bit [31:0] a, d;
    bit [3:0]  s;
    bit        aw_done, w_done;
    axi_lite_txn tr;

    // FEAT-010/014: if reset asserts mid-capture, abandon this transfer
    // (`disable one_write` unwinds straight back to the top of the forever
    // loop) rather than risk pairing stale address/data with whatever
    // unrelated write's BVALID/BREADY happens to satisfy the wait next -
    // the DUT itself forgets the aborted transfer, so nothing should be
    // published for it. Matches the abort axi_lite_driver.sv performs.
    forever begin
      begin : one_write
        aw_done = 1'b0;
        w_done  = 1'b0;
        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_write;
          end
          if (!aw_done && vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
            a = vif.monitor_cb.awaddr;
            aw_done = 1'b1;
          end
          if (!w_done && vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
            d = vif.monitor_cb.wdata;
            s = vif.monitor_cb.wstrb;
            w_done = 1'b1;
          end
        end while (!aw_done || !w_done);

        // do-while: X on bvalid/bready before the first clock edge must not
        // make this loop skip its @ entirely (see apb_monitor.sv for why).
        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_write;
          end
        end while (!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));

        tr = axi_lite_txn::type_id::create("tr");
        tr.dir   = AXI_WRITE;
        tr.addr  = a;
        tr.data  = d;
        tr.wstrb = s;
        tr.resp  = vif.monitor_cb.bresp;
        ap.write(tr);
      end : one_write
    end
  endtask

  task watch_read();
    bit [31:0] a;
    axi_lite_txn tr;

    forever begin
      begin : one_read
        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_read;
          end
        end while (!(vif.monitor_cb.arvalid && vif.monitor_cb.arready));
        a = vif.monitor_cb.araddr;

        do begin
          @(vif.monitor_cb);
          if (vif.rst_n !== 1'b1) begin
            wait (vif.rst_n === 1'b1);
            disable one_read;
          end
        end while (!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));

        tr = axi_lite_txn::type_id::create("tr");
        tr.dir   = AXI_READ;
        tr.addr  = a;
        tr.data  = vif.monitor_cb.rdata;
        tr.wstrb = 4'b0000;
        tr.resp  = vif.monitor_cb.rresp;
        ap.write(tr);
      end : one_read
    end
  endtask

endclass : axi_lite_monitor
