//==============================================================================
// apb_driver.sv - reactive APB slave: detects each SETUP phase, pulls a
// randomised response descriptor (wait_cycles / inject_error) from the
// sequencer, applies it while running an internal word-addressable memory
// model for read/write data.
//==============================================================================

class apb_driver extends uvm_driver #(apb_txn);

  `uvm_component_utils(apb_driver)

  virtual apb_if vif;
  apb_cfg        cfg;

  bit [31:0] mem[bit [31:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface must be set for apb_driver")
    if (!uvm_config_db#(apb_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_cfg must be set for apb_driver")
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] word_addr;
    bit        pwrite;
    bit [31:0] wdata_captured;
    apb_txn    resp;
    bit        aborted;

    vif.driver_cb.pready  <= 1'b0;
    vif.driver_cb.prdata  <= '0;
    vif.driver_cb.pslverr <= 1'b0;
    wait (vif.rst_n === 1'b1);

    forever begin
      @(vif.driver_cb);

      // FEAT-010/014: reset asserting mid-poll or mid-transfer must not
      // leave stale outputs driven or a bogus transfer published - see
      // axi_lite_driver.sv for the matching AXI-side fix.
      if (vif.rst_n !== 1'b1) begin
        vif.driver_cb.pready  <= 1'b0;
        vif.driver_cb.prdata  <= '0;
        vif.driver_cb.pslverr <= 1'b0;
        wait (vif.rst_n === 1'b1);
      end else if (vif.driver_cb.psel && !vif.driver_cb.penable) begin
        word_addr      = vif.driver_cb.paddr >> 2;
        pwrite         = vif.driver_cb.pwrite;
        wdata_captured = vif.driver_cb.pwdata;

        seq_item_port.get_next_item(resp);

        aborted = 1'b0;
        fork
          repeat (resp.wait_cycles) @(vif.driver_cb);
          begin
            wait (vif.rst_n === 1'b0);
            aborted = 1'b1;
          end
        join_any
        disable fork;

        if (!aborted) begin
          if (pwrite) begin
            mem[word_addr] = wdata_captured;
            resp.rdata = '0;
          end else begin
            resp.rdata = mem.exists(word_addr) ? mem[word_addr] : 32'h0000_0000;
          end
          resp.addr    = vif.driver_cb.paddr;
          resp.pwrite  = pwrite;
          resp.wdata   = wdata_captured;
          resp.pslverr = resp.inject_error;

          vif.driver_cb.pready  <= 1'b1;
          vif.driver_cb.pslverr <= resp.inject_error;
          vif.driver_cb.prdata  <= pwrite ? 32'h0000_0000 : resp.rdata;
        end

        seq_item_port.item_done();

        if (!aborted) begin
          @(vif.driver_cb);
          vif.driver_cb.pready  <= 1'b0;
          vif.driver_cb.pslverr <= 1'b0;
        end else begin
          wait (vif.rst_n === 1'b1);
        end
      end
    end
  endtask

endclass : apb_driver
