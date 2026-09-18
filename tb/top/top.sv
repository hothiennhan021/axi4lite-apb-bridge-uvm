//==============================================================================
// top.sv - testbench top: clock/reset generation, DUT + interface wiring,
// config_db handles, run_test().
//==============================================================================

`timescale 1ns / 1ps

module top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi2apb_pkg::*;

  localparam real CLK_PERIOD = 10.0;

  logic clk = 0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  reset_if reset_vif ();

  initial begin
    reset_vif.rst_n = 1'b0;
    repeat (5) @(posedge clk);
    // Nonblocking: a blocking assign here lands in the same time step as
    // this posedge, racing the monitors' clocking-block input skew - some
    // of them would sample rst_n already 1 at the very edge it deasserts,
    // one cycle earlier than everything else in the testbench sees it.
    reset_vif.rst_n <= 1'b1;
  end

  axi4lite_if axi_vif (.clk(clk), .rst_n(reset_vif.rst_n));
  apb_if      apb_vif (.clk(clk), .rst_n(reset_vif.rst_n));

  axi2apb_bridge dut (
    .clk     (clk),
    .rst_n   (reset_vif.rst_n),

    .awaddr  (axi_vif.awaddr),
    .awprot  (axi_vif.awprot),
    .awvalid (axi_vif.awvalid),
    .awready (axi_vif.awready),

    .wdata   (axi_vif.wdata),
    .wstrb   (axi_vif.wstrb),
    .wvalid  (axi_vif.wvalid),
    .wready  (axi_vif.wready),

    .bresp   (axi_vif.bresp),
    .bvalid  (axi_vif.bvalid),
    .bready  (axi_vif.bready),

    .araddr  (axi_vif.araddr),
    .arprot  (axi_vif.arprot),
    .arvalid (axi_vif.arvalid),
    .arready (axi_vif.arready),

    .rdata   (axi_vif.rdata),
    .rresp   (axi_vif.rresp),
    .rvalid  (axi_vif.rvalid),
    .rready  (axi_vif.rready),

    .paddr   (apb_vif.paddr),
    .pwrite  (apb_vif.pwrite),
    .pwdata  (apb_vif.pwdata),
    .psel    (apb_vif.psel),
    .penable (apb_vif.penable),
    .prdata  (apb_vif.prdata),
    .pready  (apb_vif.pready),
    .pslverr (apb_vif.pslverr)
  );

  initial begin
    uvm_config_db#(virtual axi4lite_if)::set(null, "*", "axi_vif", axi_vif);
    uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_vif);
    uvm_config_db#(virtual reset_if)::set(null, "*", "reset_vif", reset_vif);
    run_test();
  end

endmodule : top
