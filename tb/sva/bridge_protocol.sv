//==============================================================================
// bridge_protocol.sv - bridge-level assertions (verification_plan.md §7.3),
// plus ASRT-P06 which also needs the FSM's own idle encoding.
//
// Bound directly to axi2apb_bridge so it can see internal FSM state
// (state_q, addr_q) alongside the AXI/APB ports - these checks inherently
// need both the DUT's decision (which channel it is servicing) and its
// external behaviour, which no single interface-level bind can see.
//==============================================================================

module bridge_protocol_sva (
  input logic        clk,
  input logic        rst_n,

  input logic [2:0]  state_q,   // must match axi2apb_bridge's state_t encoding
  input logic [3:0]  wstrb_q,

  input logic [31:0] awaddr,
  input logic        awvalid,
  input logic        awready,
  input logic        wvalid,
  input logic        wready,
  input logic        bvalid,
  input logic        bready,

  input logic [31:0] araddr,
  input logic        arvalid,
  input logic        arready,
  input logic        rvalid,
  input logic        rready,

  input logic [31:0] paddr,
  input logic        pwrite,
  input logic        psel,
  input logic        penable,
  input logic        pready
);

  localparam logic [2:0] IDLE   = 3'd0;
  localparam logic [2:0] SETUP  = 3'd1;
  localparam logic [2:0] ACCESS = 3'd2;
  localparam logic [2:0] RESP   = 3'd3;

  // XSim (2022.2) does not support "default disable iff" - each property
  // below carries its own explicit disable iff (!rst_n) instead.

  // ASRT-P06: with no transaction pending, PSEL and PENABLE stay low
  a_idle_state: assert property (
    @(posedge clk) disable iff (!rst_n)
    state_q == IDLE |-> !psel && !penable
  ) else $error("ASRT-P06: PSEL/PENABLE asserted while FSM is IDLE");

  //--------------------------------------------------------------------------
  // Black-box tracking of the request being serviced, from AXI handshakes
  // only (no DUT internals): which channels of the current write / read have
  // been accepted, and the address that request carried.
  //--------------------------------------------------------------------------
  logic        aw_seen_q, w_seen_q, ar_seen_q;
  logic [31:0] req_addr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_seen_q  <= 1'b0;
      w_seen_q   <= 1'b0;
      ar_seen_q  <= 1'b0;
      req_addr_q <= '0;
    end else begin
      if (bvalid && bready) begin
        aw_seen_q <= 1'b0;
        w_seen_q  <= 1'b0;
      end else begin
        if (awvalid && awready) aw_seen_q <= 1'b1;
        if (wvalid && wready)   w_seen_q  <= 1'b1;
      end
      if (rvalid && rready)        ar_seen_q <= 1'b0;
      else if (arvalid && arready) ar_seen_q <= 1'b1;

      if (awvalid && awready)      req_addr_q <= awaddr;
      else if (arvalid && arready) req_addr_q <= araddr;
    end
  end

  // ASRT-B01: one outstanding transaction (ASM-02). While a write is open
  // (AW and/or W accepted, B not yet handshaken) no read is accepted and
  // neither of its own channels is accepted twice; while a read is open
  // nothing else is accepted.
  a_single_outstanding_write: assert property (
    @(posedge clk) disable iff (!rst_n)
    (aw_seen_q || w_seen_q) |-> !(arvalid && arready) &&
                                !(aw_seen_q && awvalid && awready) &&
                                !(w_seen_q && wvalid && wready)
  ) else $error("ASRT-B01: new request accepted while a write is outstanding");

  a_single_outstanding_read: assert property (
    @(posedge clk) disable iff (!rst_n)
    ar_seen_q |-> !(arvalid && arready) && !(awvalid && awready) && !(wvalid && wready)
  ) else $error("ASRT-B01: new request accepted while a read is outstanding");

  // ASRT-B02: every accepted request reaches a response within a bounded
  // number of cycles. The bound (64) comfortably covers this project's
  // widest configured wait-state range (0-8) plus SETUP/ACCESS overhead;
  // anything beyond that indicates the FSM is stuck, not just slow.
  a_no_deadlock: assert property (
    @(posedge clk) disable iff (!rst_n)
    state_q == SETUP |-> ##[1:64] state_q == RESP
  ) else $error("ASRT-B02: no response within 64 cycles of SETUP");

  // ASRT-B03: PADDR equals the AWADDR/ARADDR of the request being serviced,
  // as captured from the AXI handshake above (not from the DUT's own addr_q,
  // which would only re-check a wire).
  a_addr_forwarding: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel |-> paddr == req_addr_q
  ) else $error("ASRT-B03: PADDR does not match the AXI request address");

  // ASRT-B04: WSTRB option (d) - a partial-strobe write never reaches APB
  a_no_partial_strobe_write: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel && pwrite |-> wstrb_q == 4'b1111
  ) else $error("ASRT-B04: APB write issued for a partial-strobe AXI write");

endmodule : bridge_protocol_sva


bind axi2apb_bridge bridge_protocol_sva u_bridge_protocol_sva (
  .clk     (clk),
  .rst_n   (rst_n),
  .state_q (state_q),
  .wstrb_q (wstrb_q),
  .awaddr  (awaddr),
  .awvalid (awvalid),
  .awready (awready),
  .wvalid  (wvalid),
  .wready  (wready),
  .bvalid  (bvalid),
  .bready  (bready),
  .araddr  (araddr),
  .arvalid (arvalid),
  .arready (arready),
  .rvalid  (rvalid),
  .rready  (rready),
  .paddr   (paddr),
  .pwrite  (pwrite),
  .psel    (psel),
  .penable (penable),
  .pready  (pready)
);
