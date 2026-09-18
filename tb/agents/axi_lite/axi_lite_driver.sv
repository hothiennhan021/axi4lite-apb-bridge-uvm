//==============================================================================
// axi_lite_driver.sv - drives AXI4-Lite master-side transactions onto the DUT
//
// Fixed priority write>read is a DUT decision, not a driver one: the driver
// simply issues each transaction's channel handshakes independently and lets
// the AWVALID/WVALID/ARVALID arbitration happen on the bus. AWADDR and WDATA
// are asserted together but each channel's VALID is deasserted the cycle its
// own READY is seen, so the two channels can complete on different cycles.
//==============================================================================

class axi_lite_driver extends uvm_driver #(axi_lite_txn);

  `uvm_component_utils(axi_lite_driver)

  virtual axi4lite_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface must be set for axi_lite_driver")
  endfunction

  task run_phase(uvm_phase phase);
    idle_bus();
    wait (vif.rst_n === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);

      // FEAT-010/014: if reset asserts while a transaction is in flight,
      // the DUT forgets it entirely (its registers reset), so waiting for
      // that transaction's response would block forever. Race the drive
      // against a reset watcher and abandon the item cleanly if reset wins.
      fork
        begin
          repeat (req.delay) @(vif.driver_cb);
          if (req.dir == AXI_WRITE) drive_write(req);
          else                      drive_read(req);
        end
        wait (vif.rst_n === 1'b0);
      join_any
      disable fork;

      seq_item_port.item_done();

      if (vif.rst_n !== 1'b1) begin
        idle_bus();
        wait (vif.rst_n === 1'b1);
      end
    end
  endtask

  task idle_bus();
    vif.driver_cb.awvalid <= 1'b0;
    vif.driver_cb.awaddr  <= '0;
    vif.driver_cb.awprot  <= '0;
    vif.driver_cb.wvalid  <= 1'b0;
    vif.driver_cb.wdata   <= '0;
    vif.driver_cb.wstrb   <= '0;
    vif.driver_cb.bready  <= 1'b0;
    vif.driver_cb.arvalid <= 1'b0;
    vif.driver_cb.araddr  <= '0;
    vif.driver_cb.arprot  <= '0;
    vif.driver_cb.rready  <= 1'b0;
  endtask

  task drive_write(axi_lite_txn tr);
    bit aw_done = 1'b0;
    bit w_done  = 1'b0;

    vif.driver_cb.awaddr  <= tr.addr;
    vif.driver_cb.awprot  <= 3'b000;
    vif.driver_cb.awvalid <= 1'b1;
    vif.driver_cb.wdata   <= tr.data;
    vif.driver_cb.wstrb   <= tr.wstrb;
    vif.driver_cb.wvalid  <= 1'b1;

    do begin
      @(vif.driver_cb);
      if (!aw_done && vif.driver_cb.awready) begin
        vif.driver_cb.awvalid <= 1'b0;
        aw_done = 1'b1;
      end
      if (!w_done && vif.driver_cb.wready) begin
        vif.driver_cb.wvalid <= 1'b0;
        w_done = 1'b1;
      end
    end while (!aw_done || !w_done);

    // FEAT-013: BREADY can be held low for resp_ready_delay cycles after the
    // address/data handshake - the DUT must keep BVALID asserted until then.
    repeat (tr.resp_ready_delay) @(vif.driver_cb);
    vif.driver_cb.bready <= 1'b1;
    while (!vif.driver_cb.bvalid) @(vif.driver_cb);
    tr.resp = vif.driver_cb.bresp;
    @(vif.driver_cb);
    vif.driver_cb.bready <= 1'b0;
  endtask

  task drive_read(axi_lite_txn tr);
    vif.driver_cb.araddr  <= tr.addr;
    vif.driver_cb.arprot  <= 3'b000;
    vif.driver_cb.arvalid <= 1'b1;

    @(vif.driver_cb);
    while (!vif.driver_cb.arready) @(vif.driver_cb);
    vif.driver_cb.arvalid <= 1'b0;

    // FEAT-013: RREADY can be held low for resp_ready_delay cycles after the
    // address handshake - the DUT must keep RVALID asserted until then.
    repeat (tr.resp_ready_delay) @(vif.driver_cb);
    vif.driver_cb.rready <= 1'b1;
    while (!vif.driver_cb.rvalid) @(vif.driver_cb);
    tr.data = vif.driver_cb.rdata;
    tr.resp = vif.driver_cb.rresp;
    @(vif.driver_cb);
    vif.driver_cb.rready <= 1'b0;
  endtask

endclass : axi_lite_driver
