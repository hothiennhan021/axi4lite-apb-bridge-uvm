//==============================================================================
// interfaces.sv
//
// SystemVerilog interfaces for the AXI4-Lite slave port and the APB master
// port of axi2apb_bridge. Each interface exposes:
//   - a driver clocking block  (agent drives stimulus, samples handshake)
//   - a monitor clocking block (passive sampling only)
//   - a dut modport            (plain signal directions, no clocking block -
//                                the DUT is a synthesizable module)
//==============================================================================

interface axi4lite_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input logic clk,
  input logic rst_n
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  logic [ADDR_WIDTH-1:0] awaddr;
  logic [2:0]            awprot;
  logic                  awvalid;
  logic                  awready;

  logic [DATA_WIDTH-1:0] wdata;
  logic [STRB_WIDTH-1:0] wstrb;
  logic                  wvalid;
  logic                  wready;

  logic [1:0]            bresp;
  logic                  bvalid;
  logic                  bready;

  logic [ADDR_WIDTH-1:0] araddr;
  logic [2:0]            arprot;
  logic                  arvalid;
  logic                  arready;

  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rvalid;
  logic                  rready;

  // Driver side: this bridge's AXI port is a slave, so the agent acting as
  // the AXI master drives the request signals and samples the response
  // signals the DUT produces.
  clocking driver_cb @(posedge clk);
    default input #1step output #1step;
    output awaddr, awprot, awvalid;
    input  awready;
    output wdata, wstrb, wvalid;
    input  wready;
    input  bresp, bvalid;
    output bready;
    output araddr, arprot, arvalid;
    input  arready;
    input  rdata, rresp, rvalid;
    output rready;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step;
    input awaddr, awprot, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arprot, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking

  modport driver_mp  (clocking driver_cb, input rst_n);
  modport monitor_mp (clocking monitor_cb, input rst_n);

  modport dut_mp (
    input  awaddr, awprot, awvalid, output awready,
    input  wdata, wstrb, wvalid,    output wready,
    output bresp, bvalid,           input  bready,
    input  araddr, arprot, arvalid, output arready,
    output rdata, rresp, rvalid,    input  rready,
    input  clk, rst_n
  );

endinterface : axi4lite_if


interface apb_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input logic clk,
  input logic rst_n
);

  logic [ADDR_WIDTH-1:0] paddr;
  logic                  pwrite;
  logic [DATA_WIDTH-1:0] pwdata;
  logic                  psel;
  logic                  penable;

  logic [DATA_WIDTH-1:0] prdata;
  logic                  pready;
  logic                  pslverr;

  // Driver side: this bridge's APB port is a master, so the agent acting as
  // the APB slave samples the request signals and drives the response
  // signals (prdata / pready / pslverr).
  clocking driver_cb @(posedge clk);
    default input #1step output #1step;
    input  paddr, pwrite, pwdata, psel, penable;
    output prdata, pready, pslverr;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step;
    input paddr, pwrite, pwdata, psel, penable, prdata, pready, pslverr;
  endclocking

  modport driver_mp  (clocking driver_cb, input rst_n);
  modport monitor_mp (clocking monitor_cb, input rst_n);

  modport dut_mp (
    output paddr, pwrite, pwdata, psel, penable,
    input  prdata, pready, pslverr,
    input  clk, rst_n
  );

endinterface : apb_if


// Minimal wrapper so directed tests (test_reset_mid_txn) can pulse reset
// mid-simulation. axi4lite_if/apb_if only expose rst_n as a read-only input,
// which is intentional - agents must never control reset themselves.
interface reset_if;
  logic rst_n;
endinterface : reset_if
