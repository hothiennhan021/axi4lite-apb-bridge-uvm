//==============================================================================
// apb_protocol.sv - APB3 protocol checker (verification_plan.md §7.2)
//
// Bound onto apb_if. ASRT-P06 (idle state) and the bridge-level assertions
// (§7.3) need the FSM's own IDLE encoding to be meaningful and live in
// tb/sva/bridge_protocol.sv instead, bound directly to axi2apb_bridge.
//==============================================================================

module apb_protocol_sva (
  input logic        clk,
  input logic        rst_n,

  input logic [31:0] paddr,
  input logic        pwrite,
  input logic [31:0] pwdata,
  input logic        psel,
  input logic        penable,

  input logic [31:0] prdata,
  input logic        pready,
  input logic        pslverr
);

  // XSim (2022.2) does not support "default disable iff" - each property
  // below carries its own explicit disable iff (!rst_n) instead.

  // ASRT-P01: PENABLE asserts exactly one cycle after PSEL, never
  // simultaneously with it going high.
  a_penable_after_psel: assert property (
    @(posedge clk) disable iff (!rst_n)
    $rose(psel) |-> !penable
  ) else $error("ASRT-P01: PENABLE high in the same cycle PSEL rises");

  a_penable_rises_next: assert property (
    @(posedge clk) disable iff (!rst_n)
    $rose(psel) |=> penable
  ) else $error("ASRT-P01: PENABLE did not rise the cycle after PSEL");

  // ASRT-P02: PSEL stays high for as long as PENABLE is high
  a_psel_during_penable: assert property (
    @(posedge clk) disable iff (!rst_n)
    penable |-> psel
  ) else $error("ASRT-P02: PENABLE high while PSEL low");

  // ASRT-P03: PADDR, PWRITE and PWDATA stable throughout the access phase
  a_addr_stable_in_access: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel && penable && !pready |=> $stable(paddr) && $stable(pwrite) && $stable(pwdata)
  ) else $error("ASRT-P03: PADDR/PWRITE/PWDATA changed mid-access");

  // ASRT-P04: PENABLE deasserts in the cycle after PREADY is sampled high
  a_penable_deassert: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel && penable && pready |=> !penable
  ) else $error("ASRT-P04: PENABLE still high the cycle after PREADY");

  // ASRT-P05: PSLVERR is only meaningful when PREADY is high - at minimum
  // it must be a known value at that point (an X here would silently read
  // as an unintended OKAY/SLVERR downstream).
  a_pslverr_known_on_ready: assert property (
    @(posedge clk) disable iff (!rst_n)
    psel && penable && pready |-> !$isunknown(pslverr)
  ) else $error("ASRT-P05: PSLVERR is X while PREADY is high");

endmodule : apb_protocol_sva


// See axi_lite_protocol.sv for why this binds into top rather than apb_if
// directly - XSim does not support binding a module into an interface.
bind top apb_protocol_sva u_apb_protocol_sva (
  .clk     (clk),
  .rst_n   (reset_vif.rst_n),
  .paddr   (apb_vif.paddr),
  .pwrite  (apb_vif.pwrite),
  .pwdata  (apb_vif.pwdata),
  .psel    (apb_vif.psel),
  .penable (apb_vif.penable),
  .prdata  (apb_vif.prdata),
  .pready  (apb_vif.pready),
  .pslverr (apb_vif.pslverr)
);
