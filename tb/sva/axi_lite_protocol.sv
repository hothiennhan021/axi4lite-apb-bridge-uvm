//==============================================================================
// axi_lite_protocol.sv - AXI4-Lite protocol checker (verification_plan.md §7.1)
//
// Bound (not instantiated) onto axi4lite_if from tb/top/top.sv so it observes
// the exact same interface the DUT and testbench drive, with zero RTL changes
// required. XSim 2022.x does not support assertion coverage, so these are
// checked for pass/fail only - no cover directives.
//==============================================================================

module axi_lite_protocol_sva (
  input logic clk,
  input logic rst_n,

  input logic [31:0] awaddr,
  input logic [2:0]  awprot,
  input logic        awvalid,
  input logic        awready,

  input logic [31:0] wdata,
  input logic [3:0]  wstrb,
  input logic        wvalid,
  input logic        wready,

  input logic [1:0]  bresp,
  input logic        bvalid,
  input logic        bready,

  input logic [31:0] araddr,
  input logic [2:0]  arprot,
  input logic        arvalid,
  input logic        arready,

  input logic [31:0] rdata,
  input logic [1:0]  rresp,
  input logic        rvalid,
  input logic        rready
);

  // XSim (2022.2) does not support "default disable iff" - each property
  // below carries its own explicit disable iff (!rst_n) instead.

  // ASRT-A01: AWVALID remains asserted until AWREADY is sampled high
  a_awvalid_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    awvalid && !awready |=> awvalid
  ) else $error("ASRT-A01: AWVALID deasserted before AWREADY");

  // ASRT-A02: AWADDR/AWPROT stable while AWVALID high and AWREADY low
  a_awaddr_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    awvalid && !awready |=> $stable(awaddr) && $stable(awprot)
  ) else $error("ASRT-A02: AWADDR/AWPROT changed mid-handshake");

  // ASRT-A03: WVALID remains asserted until WREADY is sampled high
  a_wvalid_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    wvalid && !wready |=> wvalid
  ) else $error("ASRT-A03: WVALID deasserted before WREADY");

  // ASRT-A04: WDATA/WSTRB stable during the write-data handshake
  a_wdata_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    wvalid && !wready |=> $stable(wdata) && $stable(wstrb)
  ) else $error("ASRT-A04: WDATA/WSTRB changed mid-handshake");

  // ASRT-A05: ARVALID remains asserted until ARREADY is sampled high
  a_arvalid_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    arvalid && !arready |=> arvalid
  ) else $error("ASRT-A05: ARVALID deasserted before ARREADY");

  // ASRT-A02 (read side): ARADDR/ARPROT stable while ARVALID high, ARREADY low
  a_araddr_stable: assert property (
    @(posedge clk) disable iff (!rst_n)
    arvalid && !arready |=> $stable(araddr) && $stable(arprot)
  ) else $error("ASRT-A02b: ARADDR/ARPROT changed mid-handshake");

  // ASRT-A06: BRESP only takes the values OKAY or SLVERR
  a_bresp_legal: assert property (
    @(posedge clk) disable iff (!rst_n)
    bvalid |-> (bresp == 2'b00 || bresp == 2'b10)
  ) else $error("ASRT-A06: illegal BRESP value");

  // ASRT-A07: RRESP only takes the values OKAY or SLVERR
  a_rresp_legal: assert property (
    @(posedge clk) disable iff (!rst_n)
    rvalid |-> (rresp == 2'b00 || rresp == 2'b10)
  ) else $error("ASRT-A07: illegal RRESP value");

  // ASRT-A08: no VALID signal is asserted while reset is low. Guarded with
  // !$isunknown(...) rather than a disable iff: the VALID signals are
  // legitimately X for the first delta of simulation, before the driver's
  // very first clocked update lands (nothing has driven them yet) - that
  // is a testbench-startup artifact, not a protocol violation, and it only
  // ever happens once, at the very beginning, not on every reset pulse.
  a_no_valid_in_reset: assert property (
    @(posedge clk)
    (!rst_n && !$isunknown({awvalid, wvalid, arvalid, bvalid, rvalid}))
      |-> !(awvalid || wvalid || arvalid || bvalid || rvalid)
  ) else $error("ASRT-A08: a VALID signal is asserted during reset");

  // BVALID/RVALID hold until the corresponding READY is seen (FEAT-013)
  a_bvalid_holds: assert property (
    @(posedge clk) disable iff (!rst_n)
    bvalid && !bready |=> bvalid && $stable(bresp)
  ) else $error("FEAT-013: BVALID/BRESP changed before BREADY");

  a_rvalid_holds: assert property (
    @(posedge clk) disable iff (!rst_n)
    rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp)
  ) else $error("FEAT-013: RVALID/RDATA/RRESP changed before RREADY");

  // ASRT-A09/A10: BVALID/RVALID must never assert without a preceding
  // accepted write/read. AWADDR and WDATA can be accepted on different
  // cycles (see the bridge's aw_done_q/w_done_q), so "write accepted" is
  // tracked as two independent per-channel flags, both required - not a
  // single-cycle AND of both handshakes, which would false-fire whenever
  // the two channels complete apart.
  logic aw_accepted_q, w_accepted_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_accepted_q <= 1'b0;
      w_accepted_q  <= 1'b0;
    end else if (bvalid && bready) begin
      aw_accepted_q <= 1'b0;
      w_accepted_q  <= 1'b0;
    end else begin
      if (awvalid && awready) aw_accepted_q <= 1'b1;
      if (wvalid && wready)   w_accepted_q  <= 1'b1;
    end
  end

  logic write_outstanding_q, read_outstanding_q;
  assign write_outstanding_q = aw_accepted_q && w_accepted_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) read_outstanding_q <= 1'b0;
    else if (arvalid && arready) read_outstanding_q <= 1'b1;
    else if (rvalid && rready) read_outstanding_q <= 1'b0;
  end

  a_bvalid_requires_request: assert property (
    @(posedge clk) disable iff (!rst_n)
    bvalid |-> write_outstanding_q
  ) else $error("ASRT-A09: BVALID asserted with no accepted write outstanding");

  a_rvalid_requires_request: assert property (
    @(posedge clk) disable iff (!rst_n)
    rvalid |-> read_outstanding_q
  ) else $error("ASRT-A10: RVALID asserted with no accepted read outstanding");

endmodule : axi_lite_protocol_sva


// XSim (2022.2) rejects `bind <interface> <module> ...` - binding a plain
// module directly into an interface instance is not supported, only into a
// module. Binding into tb/top/top.sv instead and reaching the axi4lite_if
// instance's signals by hierarchical name gets the same checking with an
// identical, zero-RTL-change bind statement; it just ties this file to the
// top module's name and its interface instance name (axi_vif).
bind top axi_lite_protocol_sva u_axi_lite_protocol_sva (
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
  .rready  (axi_vif.rready)
);
