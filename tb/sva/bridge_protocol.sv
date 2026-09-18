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
  input logic [31:0] addr_q,

  input logic [31:0] awaddr,
  input logic        awvalid,
  input logic        awready,

  input logic [31:0] araddr,
  input logic        arvalid,
  input logic        arready,

  input logic [31:0] paddr,
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

  // ASRT-B01: no new APB transfer starts before the previous one completes -
  // SETUP is only ever entered directly from IDLE, never re-entered while a
  // transfer is already in flight.
  a_single_outstanding: assert property (
    @(posedge clk) disable iff (!rst_n)
    state_q == SETUP |-> $past(state_q) == IDLE
  ) else $error("ASRT-B01: SETUP entered without returning to IDLE first");

  // ASRT-B02: every accepted request reaches a response within a bounded
  // number of cycles. The bound (64) comfortably covers this project's
  // widest configured wait-state range (0-8) plus SETUP/ACCESS overhead;
  // anything beyond that indicates the FSM is stuck, not just slow.
  a_no_deadlock: assert property (
    @(posedge clk) disable iff (!rst_n)
    state_q == SETUP |-> ##[1:64] state_q == RESP
  ) else $error("ASRT-B02: no response within 64 cycles of SETUP");

  // ASRT-B03: PADDR matches the latched address of the request being
  // serviced - guards the paddr/addr_q wiring against a future refactor.
  a_addr_forwarding: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel |-> paddr == addr_q
  ) else $error("ASRT-B03: PADDR does not match the latched request address");

endmodule : bridge_protocol_sva


bind axi2apb_bridge bridge_protocol_sva u_bridge_protocol_sva (
  .clk     (clk),
  .rst_n   (rst_n),
  .state_q (state_q),
  .addr_q  (addr_q),
  .awaddr  (awaddr),
  .awvalid (awvalid),
  .awready (awready),
  .araddr  (araddr),
  .arvalid (arvalid),
  .arready (arready),
  .paddr   (paddr),
  .psel    (psel),
  .penable (penable),
  .pready  (pready)
);
