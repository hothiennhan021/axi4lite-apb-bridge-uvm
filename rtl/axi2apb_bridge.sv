//==============================================================================
// axi2apb_bridge.sv
//
// AXI4-Lite slave to APB3 master protocol bridge.
//
// Design assumptions (keep in sync with docs/verification_plan.md):
//   ASM-01 : AXI4-Lite carries no bursts - one transfer per transaction
//   ASM-02 : One outstanding transaction at a time
//   ASM-03 : 32-bit data on both sides, no width conversion
//   ASM-04 : AWPROT / ARPROT are ignored
//   ASM-05 : Reset is active-low, asynchronous assert
//
// WSTRB decision: option (c) - any write with wstrb != 4'b1111 returns SLVERR
//   on BRESP and the APB write is still issued (full word, wstrb not
//   forwarded). Rationale is recorded in docs/design_decisions.md.
//==============================================================================

module axi2apb_bridge (
  input  logic        clk,
  input  logic        rst_n,

  //--------------------------------------------------------------------------
  // AXI4-Lite slave port
  //--------------------------------------------------------------------------
  // Write address channel
  input  logic [31:0] awaddr,
  input  logic [2:0]  awprot,
  input  logic        awvalid,
  output logic        awready,

  // Write data channel
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wvalid,
  output logic        wready,

  // Write response channel
  output logic [1:0]  bresp,
  output logic        bvalid,
  input  logic        bready,

  // Read address channel
  input  logic [31:0] araddr,
  input  logic [2:0]  arprot,
  input  logic        arvalid,
  output logic        arready,

  // Read data channel
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic        rvalid,
  input  logic        rready,

  //--------------------------------------------------------------------------
  // APB master port
  //--------------------------------------------------------------------------
  output logic [31:0] paddr,
  output logic        pwrite,
  output logic [31:0] pwdata,
  output logic        psel,
  output logic        penable,
  input  logic [31:0] prdata,
  input  logic        pready,
  input  logic        pslverr
);

  //==========================================================================
  // Local parameters
  //==========================================================================
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  //==========================================================================
  // FSM state definition
  //==========================================================================
  typedef enum logic [2:0] {
    IDLE   = 3'd0,   // no transaction in flight
    SETUP  = 3'd1,   // APB setup phase  : psel=1, penable=0, exactly 1 cycle
    ACCESS = 3'd2,   // APB access phase : psel=1, penable=1, until pready
    RESP   = 3'd3    // drive AXI response, wait for bready / rready
    // AWVALID/WVALID arriving on different cycles is handled with the
    // aw_done_q / w_done_q flag registers below, not an extra state - see
    // docs/design_decisions.md for why a flag pair was chosen over a state.
  } state_t;

  state_t state_q, state_d;

  //==========================================================================
  // Transaction registers
  //
  // These MUST be registered. Do not wire awaddr/wdata straight to
  // paddr/pwdata - the AXI master is free to change them after the handshake,
  // which would violate ASRT-P03 (address stable during access phase).
  //==========================================================================
  logic [31:0] addr_q;      // latched address (from awaddr or araddr)
  logic [31:0] wdata_q;     // latched write data
  logic [3:0]  wstrb_q;     // latched write strobe
  logic        is_write_q;  // 1 = write transaction, 0 = read

  logic [31:0] rdata_q;     // latched prdata, returned on rdata
  logic        err_q;       // latched pslverr, mapped to bresp / rresp

  // Handshake tracking flags - lets AWADDR and WDATA arrive on independent
  // cycles while still in IDLE, without adding a state for it.
  logic        aw_done_q;
  logic        w_done_q;

  // Combinational "has this channel's handshake completed" - true either
  // because it completed on an earlier cycle (flag latched) or it completes
  // this very cycle (valid & ready).
  logic        aw_complete;
  logic        w_complete;
  assign aw_complete = aw_done_q | (awvalid & awready);
  assign w_complete  = w_done_q  | (wvalid  & wready);

  // True whenever any write activity is pending or starting - gates ARREADY
  // so a read can never be accepted ahead of, or interleaved with, a write
  // (fixed priority: write > read, see docs/design_decisions.md).
  logic        write_pending;
  assign write_pending = aw_done_q | w_done_q | awvalid | wvalid;

  //==========================================================================
  // Sequential: state register
  //==========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  //==========================================================================
  // Sequential: transaction registers
  //
  // WSTRB decision (option c): a write with wstrb_q != 4'b1111 folds into
  // err_q as an SLVERR on BRESP; the full 32-bit word is still written to
  // APB (wstrb is not forwarded - APB3 has no byte-enable signal of its own).
  //==========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_q     <= '0;
      wdata_q    <= '0;
      wstrb_q    <= '0;
      is_write_q <= 1'b0;
      rdata_q    <= '0;
      err_q      <= 1'b0;
      aw_done_q  <= 1'b0;
      w_done_q   <= 1'b0;
    end else begin
      if (state_q == IDLE) begin
        // Latch whichever channel handshakes this cycle. Fixed priority
        // (write > read) is enforced upstream: arready is only asserted
        // when no write activity (pending or starting) is present, so
        // awready/wready and arready never fire in the same cycle.
        if (awvalid && awready) addr_q  <= awaddr;
        else if (arvalid && arready) addr_q <= araddr;

        if (wvalid && wready) begin
          wdata_q <= wdata;
          wstrb_q <= wstrb;
        end

        if (state_d == SETUP) begin
          is_write_q <= aw_complete && w_complete;
        end

        // Clear the flags the cycle we leave IDLE so the next transaction
        // starts clean; otherwise latch whether each channel has completed.
        if (state_d == IDLE) begin
          aw_done_q <= aw_complete;
          w_done_q  <= w_complete;
        end else begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
        end
      end

      if (state_q == ACCESS && pready) begin
        rdata_q <= prdata;
        err_q   <= pslverr | (is_write_q && (wstrb_q != 4'b1111));
      end
    end
  end

  //==========================================================================
  // Combinational: next-state logic
  //
  // Arbitration: fixed priority, write > read. Any write activity (pending
  // flags set, or AWVALID/WVALID asserted this cycle) blocks a read from
  // starting - see write_pending above and docs/design_decisions.md for the
  // starvation trade-off this implies.
  //==========================================================================
  always_comb begin
    state_d = state_q;   // default: hold

    case (state_q)
      IDLE: begin
        if (aw_complete && w_complete)
          state_d = SETUP;                    // full write assembled
        else if (arvalid && arready)
          state_d = SETUP;                    // read accepted (write_pending was low)
        else
          state_d = IDLE;
      end

      SETUP: begin
        state_d = ACCESS;                     // exactly one cycle, no exceptions
      end

      ACCESS: begin
        state_d = pready ? RESP : ACCESS;     // extend on wait states
      end

      RESP: begin
        state_d = (is_write_q ? bready : rready) ? IDLE : RESP;
      end

      default: state_d = IDLE;
    endcase
  end

  //==========================================================================
  // Combinational: AXI output logic
  //
  // awready/wready/arready only assert in IDLE and only for a channel that
  // hasn't already completed its handshake this transaction (ASRT-B01: no
  // second request accepted before the first completes). bvalid/rvalid hold
  // through RESP until bready/rready is seen (FEAT-013), matching the
  // state_d equation above so the two never disagree.
  //==========================================================================
  always_comb begin
    awready = (state_q == IDLE) && !aw_done_q;
    wready  = (state_q == IDLE) && !w_done_q;
    arready = (state_q == IDLE) && !write_pending;
    bvalid  = (state_q == RESP) && is_write_q;
    rvalid  = (state_q == RESP) && !is_write_q;
    bresp   = err_q ? RESP_SLVERR : RESP_OKAY;
    rresp   = err_q ? RESP_SLVERR : RESP_OKAY;
    rdata   = rdata_q;
  end

  //==========================================================================
  // Combinational: APB output logic
  //
  // psel    : high in SETUP and ACCESS
  // penable : high in ACCESS only - never in the same cycle as psel goes high
  //==========================================================================
  always_comb begin
    psel    = (state_q == SETUP) || (state_q == ACCESS);
    penable = (state_q == ACCESS);
    pwrite  = is_write_q;
    paddr   = addr_q;
    pwdata  = wdata_q;
  end

endmodule
