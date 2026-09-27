//==============================================================================
// tb_bridge_directed.sv - self-checking directed testbench for axi2apb_bridge
// that runs on open-source simulators (Icarus Verilog -g2012), no UVM needed.
// It complements the UVM environment (Vivado XSim) and is what CI runs.
//
//   iverilog -g2012 -o tb.vvp rtl/axi2apb_bridge.sv tb/directed/tb_bridge_directed.sv
//   vvp tb.vvp                      # prints PASSED ALL / FAIL ...
//
// Add -DINJECT_BUG_001 / _002 / _003 to re-introduce the bugs in
// docs/bug_reports/: each one must make this bench FAIL.
//
// Checks: write/read data path, AW-before-W and W-before-AW, AW+AR in the
// same cycle (write first), partial WSTRB -> SLVERR with no APB transfer and
// the slave memory untouched, PSLVERR mapping on both directions, wait
// states, BREADY/RREADY backpressure (VALID and payload held), upper address
// bits forwarded, back-to-back traffic, reset in the middle of a transfer,
// and basic APB protocol rules on every cycle.
//==============================================================================

`timescale 1ns/1ps

module tb_bridge_directed;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  // AXI4-Lite master side
  logic [31:0] awaddr = '0, wdata = '0, araddr = '0;
  logic [2:0]  awprot = '0, arprot = '0;
  logic [3:0]  wstrb  = '0;
  logic        awvalid = 1'b0, wvalid = 1'b0, bready = 1'b0, arvalid = 1'b0, rready = 1'b0;
  logic        awready, wready, bvalid, arready, rvalid;
  logic [1:0]  bresp, rresp;
  logic [31:0] rdata;

  // APB slave side
  logic [31:0] paddr, pwdata;
  logic        pwrite, psel, penable;
  logic [31:0] prdata = '0;
  logic        pready = 1'b0, pslverr = 1'b0;

  axi2apb_bridge dut (.*);

  //--------------------------------------------------------------------------
  // APB slave model: word memory indexed by paddr[11:2], configurable wait
  // states and error for the next transfer, transfer log.
  //--------------------------------------------------------------------------
  logic [31:0] mem [0:1023];
  integer      apb_wait   = 0;     // wait states for upcoming transfers
  logic        apb_err    = 1'b0;  // PSLVERR for upcoming transfers
  integer      apb_count  = 0;     // completed APB transfers
  logic [31:0] last_paddr, last_pwdata;
  logic        last_pwrite;
  integer      wait_cnt   = 0;
  integer      errors     = 0;

  always @(posedge clk) begin
    if (!rst_n) begin
      pready   <= 1'b0;
      pslverr  <= 1'b0;
      wait_cnt <= 0;
    end else begin
      pready  <= 1'b0;
      pslverr <= 1'b0;
      if (psel && !penable) begin
        wait_cnt <= 0;
        if (apb_wait == 0) begin
          pready  <= 1'b1;
          pslverr <= apb_err;
          prdata  <= mem[paddr[11:2]];
        end
      end else if (psel && penable && !pready) begin
        wait_cnt <= wait_cnt + 1;
        if (wait_cnt + 1 >= apb_wait) begin
          pready  <= 1'b1;
          pslverr <= apb_err;
          prdata  <= mem[paddr[11:2]];
        end
      end
      if (psel && penable && pready) begin
        apb_count   <= apb_count + 1;
        last_paddr  <= paddr;
        last_pwdata <= pwdata;
        last_pwrite <= pwrite;
        if (pwrite && !pslverr) mem[paddr[11:2]] <= pwdata;
      end
    end
  end

  // APB protocol rules, checked every cycle out of reset
  logic        psel_d = 1'b0, penable_d = 1'b0, pready_d = 1'b0;
  logic [31:0] paddr_d, pwdata_d;
  logic        pwrite_d;
  always @(posedge clk) begin
    if (rst_n) begin
      if (penable && !psel) begin
        errors = errors + 1; $display("FAIL apb: PENABLE without PSEL @%0t", $time);
      end
      if (psel && !psel_d && penable) begin
        errors = errors + 1; $display("FAIL apb: PENABLE with rising PSEL @%0t", $time);
      end
      if (psel_d && !penable_d && !(psel && penable)) begin
        errors = errors + 1; $display("FAIL apb: SETUP not followed by ACCESS @%0t", $time);
      end
      if (psel_d && (!penable_d || !pready_d) && psel &&
          (paddr !== paddr_d || pwrite !== pwrite_d || pwdata !== pwdata_d)) begin
        errors = errors + 1; $display("FAIL apb: PADDR/PWRITE/PWDATA changed mid-transfer @%0t", $time);
      end
    end
    psel_d <= psel; penable_d <= penable; pready_d <= pready;
    paddr_d <= paddr; pwdata_d <= pwdata; pwrite_d <= pwrite;
  end

  //--------------------------------------------------------------------------
  // AXI master tasks (drive on negedge, sample on posedge)
  //--------------------------------------------------------------------------
  localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;
  localparam integer     TIMEOUT = 200;

  logic [1:0]  got_resp;
  logic [31:0] got_data;
  logic        timed_out;

  task automatic aw_channel(input logic [31:0] a, input integer dly);
    integer n;
    repeat (dly) @(negedge clk);
    awaddr = a; awvalid = 1'b1;
    n = 0;
    do begin @(posedge clk); n++; end while (!awready && n < TIMEOUT);
    if (n >= TIMEOUT) timed_out = 1'b1;
    @(negedge clk); awvalid = 1'b0; awaddr = 32'hDEAD_0000; // master may change it now
  endtask

  task automatic w_channel(input logic [31:0] d, input logic [3:0] s, input integer dly);
    integer n;
    repeat (dly) @(negedge clk);
    wdata = d; wstrb = s; wvalid = 1'b1;
    n = 0;
    do begin @(posedge clk); n++; end while (!wready && n < TIMEOUT);
    if (n >= TIMEOUT) timed_out = 1'b1;
    @(negedge clk); wvalid = 1'b0; wdata = 32'hBAD0_BAD0;
  endtask

  // Holds BREADY low for `rdly` cycles (checking BVALID/BRESP do not change
  // once BVALID is up), then raises BREADY and completes the handshake.
  task automatic b_channel(input integer rdly);
    integer n;
    logic [1:0] first_resp;
    logic       seen;
    bready = 1'b0; seen = 1'b0;
    repeat (rdly) begin
      @(posedge clk);
      if (bvalid) begin
        if (!seen) begin seen = 1'b1; first_resp = bresp; end
        else if (bresp !== first_resp) begin
          errors++; $display("FAIL b: BRESP changed before BREADY");
        end
      end else if (seen) begin
        errors++; $display("FAIL b: BVALID dropped before BREADY");
      end
    end
    @(negedge clk); bready = 1'b1;
    n = 0;
    do begin @(posedge clk); n++; end while (!bvalid && n < TIMEOUT);
    if (!bvalid) timed_out = 1'b1;
    else begin
      got_resp = bresp;
      if (seen && bresp !== first_resp) begin
        errors++; $display("FAIL b: BRESP changed before BREADY");
      end
    end
    @(negedge clk); bready = 1'b0;
  endtask

  task automatic axi_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s,
                           input integer aw_dly, input integer w_dly, input integer b_dly);
    timed_out = 1'b0;
    fork
      aw_channel(a, aw_dly);
      w_channel(d, s, w_dly);
    join
    if (!timed_out) b_channel(b_dly);
    if (timed_out) begin
      errors++; $display("FAIL write %h: timed out (bridge hung)", a);
    end
  endtask

  task automatic axi_read(input logic [31:0] a, input integer r_dly);
    integer n;
    logic [31:0] first_data;
    logic [1:0]  first_resp;
    logic        seen;
    timed_out = 1'b0;
    @(negedge clk); araddr = a; arvalid = 1'b1;
    n = 0;
    do begin @(posedge clk); n++; end while (!arready && n < TIMEOUT);
    if (n >= TIMEOUT) timed_out = 1'b1;
    @(negedge clk); arvalid = 1'b0; araddr = 32'hDEAD_1111; // master may change it now
    rready = 1'b0; seen = 1'b0;
    repeat (r_dly) begin
      @(posedge clk);
      if (rvalid) begin
        if (!seen) begin seen = 1'b1; first_data = rdata; first_resp = rresp; end
        else if (rdata !== first_data || rresp !== first_resp) begin
          errors++; $display("FAIL r: RDATA/RRESP changed before RREADY");
        end
      end else if (seen) begin
        errors++; $display("FAIL r: RVALID dropped before RREADY");
      end
    end
    @(negedge clk); rready = 1'b1;
    n = 0;
    do begin @(posedge clk); n++; end while (!rvalid && n < TIMEOUT);
    if (!rvalid) timed_out = 1'b1;
    else begin got_resp = rresp; got_data = rdata; end
    @(negedge clk); rready = 1'b0;
    if (timed_out) begin
      errors++; $display("FAIL read %h: timed out (bridge hung)", a);
    end
  endtask

  //--------------------------------------------------------------------------
  // check helpers
  //--------------------------------------------------------------------------
  integer cnt0;

  task automatic expect_write(input string name, input logic [31:0] a, input logic [31:0] d,
                              input logic [1:0] resp);
    if (got_resp !== resp) begin
      errors++; $display("FAIL %s: BRESP=%b expected %b", name, got_resp, resp);
    end
    if (apb_count !== cnt0 + 1 || last_pwrite !== 1'b1 || last_paddr !== a || last_pwdata !== d) begin
      errors++;
      $display("FAIL %s: APB transfer count=%0d (exp %0d) pwrite=%b paddr=%h (exp %h) pwdata=%h (exp %h)",
               name, apb_count - cnt0, 1, last_pwrite, last_paddr, a, last_pwdata, d);
    end
  endtask

  task automatic expect_read(input string name, input logic [31:0] a, input logic [31:0] d,
                             input logic [1:0] resp);
    if (got_resp !== resp) begin
      errors++; $display("FAIL %s: RRESP=%b expected %b", name, got_resp, resp);
    end
    if (resp == OKAY && got_data !== d) begin
      errors++; $display("FAIL %s: RDATA=%h expected %h", name, got_data, d);
    end
    if (apb_count !== cnt0 + 1 || last_pwrite !== 1'b0 || last_paddr !== a) begin
      errors++;
      $display("FAIL %s: APB read count=%0d pwrite=%b paddr=%h (exp %h)",
               name, apb_count - cnt0, last_pwrite, last_paddr, a);
    end
  endtask

  task automatic do_reset;
    @(negedge clk); rst_n = 1'b0;
    awvalid = 1'b0; wvalid = 1'b0; arvalid = 1'b0; bready = 1'b0; rready = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);
  endtask

  //--------------------------------------------------------------------------
  // tests
  //--------------------------------------------------------------------------
  integer i, k, n_pass;
  logic [31:0] a, d;
  logic [3:0]  s;
  logic [3:0]  s_list [0:5];

  initial begin
    for (i = 0; i < 1024; i++) mem[i] = 32'h0;
    s_list[0] = 4'b0000; s_list[1] = 4'b0001; s_list[2] = 4'b0011;
    s_list[3] = 4'b0111; s_list[4] = 4'b1110; s_list[5] = 4'b1000;
    do_reset();

    // 1. basic write then read
    cnt0 = apb_count; axi_write(32'h0000_0010, 32'hA5A5_0001, 4'hF, 0, 0, 0);
    expect_write("basic write", 32'h10, 32'hA5A5_0001, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0010, 0);
    expect_read("basic read", 32'h10, 32'hA5A5_0001, OKAY);

    // 2/3. AW before W, W before AW (the aw_done_q / w_done_q path)
    cnt0 = apb_count; axi_write(32'h0000_0020, 32'h1111_2222, 4'hF, 0, 3, 0);
    expect_write("AW first", 32'h20, 32'h1111_2222, OKAY);
    cnt0 = apb_count; axi_write(32'h0000_0024, 32'h3333_4444, 4'hF, 4, 0, 0);
    expect_write("W first", 32'h24, 32'h3333_4444, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0020, 0);
    expect_read("read after AW first", 32'h20, 32'h1111_2222, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0024, 0);
    expect_read("read after W first", 32'h24, 32'h3333_4444, OKAY);

    // 4. partial strobes: SLVERR, no APB transfer, slave memory untouched
    for (k = 0; k < 6; k++) begin
      s = s_list[k];
      cnt0 = apb_count; axi_write(32'h0000_0010, 32'hFFFF_FFFF, s, k % 3, (k + 1) % 3, 0);
      if (got_resp !== SLVERR || apb_count !== cnt0) begin
        errors++;
        $display("FAIL partial wstrb=%b: BRESP=%b, APB transfers=%0d (expected SLVERR, 0)",
                 s, got_resp, apb_count - cnt0);
      end
    end
    cnt0 = apb_count; axi_read(32'h0000_0010, 0);
    expect_read("memory untouched after partial writes", 32'h10, 32'hA5A5_0001, OKAY);

    // 5. PSLVERR mapping, both directions, with wait states
    apb_err = 1'b1; apb_wait = 2;
    cnt0 = apb_count; axi_write(32'h0000_0030, 32'h5555_AAAA, 4'hF, 0, 0, 0);
    expect_write("write PSLVERR", 32'h30, 32'h5555_AAAA, SLVERR);
    cnt0 = apb_count; axi_read(32'h0000_0010, 0);
    expect_read("read PSLVERR", 32'h10, 32'h0, SLVERR);
    apb_err = 1'b0;

    // 6. wait states 0..6 on both directions
    for (k = 0; k <= 6; k++) begin
      apb_wait = k;
      d = 32'hC0DE_0000 + k;
      a = 32'h0000_0100 + 4 * k;
      cnt0 = apb_count; axi_write(a, d, 4'hF, 0, 0, 0);
      expect_write("wait-state write", a, d, OKAY);
      cnt0 = apb_count; axi_read(a, 0);
      expect_read("wait-state read", a, d, OKAY);
    end
    apb_wait = 0;

    // 7. BREADY / RREADY backpressure (VALID + payload must hold)
    cnt0 = apb_count; axi_write(32'h0000_0200, 32'h0BAD_F00D, 4'hF, 0, 0, 6);
    expect_write("B backpressure", 32'h200, 32'h0BAD_F00D, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0200, 6);
    expect_read("R backpressure", 32'h200, 32'h0BAD_F00D, OKAY);

    // 8. read from a different address than the previous write (BUG-003)
    cnt0 = apb_count; axi_write(32'h0000_0300, 32'h1234_5678, 4'hF, 0, 0, 0);
    expect_write("write before other read", 32'h300, 32'h1234_5678, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0100, 0);
    expect_read("read other address", 32'h100, 32'hC0DE_0000, OKAY);

    // 9. upper address bits are forwarded unchanged
    cnt0 = apb_count; axi_write(32'hF000_1234, 32'h7777_7777, 4'hF, 0, 0, 0);
    expect_write("upper address bits write", 32'hF000_1234, 32'h7777_7777, OKAY);
    cnt0 = apb_count; axi_read(32'h8000_0FFC, 0);
    expect_read("upper address bits read", 32'h8000_0FFC, mem[10'h3FF], OKAY);

    // 10. AW, W and AR asserted in the same cycle: write goes first
    @(negedge clk);
    awaddr = 32'h0000_0400; awvalid = 1'b1;
    wdata  = 32'hFEED_BEEF; wstrb = 4'hF; wvalid = 1'b1;
    araddr = 32'h0000_0400; arvalid = 1'b1;
    @(posedge clk);
    if (!(awready && wready && !arready)) begin
      errors++; $display("FAIL arbitration: awready=%b wready=%b arready=%b", awready, wready, arready);
    end
    @(negedge clk); awvalid = 1'b0; wvalid = 1'b0;
    bready = 1'b1;
    do @(posedge clk); while (!bvalid);
    @(negedge clk); bready = 1'b0;
    do @(posedge clk); while (!arready);
    @(negedge clk); arvalid = 1'b0; rready = 1'b1;
    do @(posedge clk); while (!rvalid);
    if (rdata !== 32'hFEED_BEEF) begin
      errors++; $display("FAIL arbitration: read returned %h, expected the new write data", rdata);
    end
    @(negedge clk); rready = 1'b0;

    // 11. back-to-back traffic (BUG-001 hangs on the second transaction)
    n_pass = 0;
    for (k = 0; k < 20; k++) begin
      a = 32'h0000_0500 + 4 * k;
      d = 32'h9000_0000 ^ (k * 32'h0101_0101);
      cnt0 = apb_count; axi_write(a, d, 4'hF, k % 2, (k + 1) % 2, 0);
      if (got_resp === OKAY && apb_count === cnt0 + 1) n_pass++;
      cnt0 = apb_count; axi_read(a, 0);
      if (got_resp === OKAY && got_data === d) n_pass++;
    end
    if (n_pass != 40) begin
      errors++; $display("FAIL back-to-back: %0d/40 transactions correct", n_pass);
    end

    // 12. reset in the middle of an APB access, then recover
    apb_wait = 20;
    @(negedge clk); araddr = 32'h0000_0010; arvalid = 1'b1;
    do @(posedge clk); while (!arready);
    @(negedge clk); arvalid = 1'b0;
    repeat (3) @(posedge clk);
    do_reset();
    apb_wait = 0;
    if (psel || penable || bvalid || rvalid) begin
      errors++; $display("FAIL reset: outputs not idle after reset");
    end
    cnt0 = apb_count; axi_write(32'h0000_0600, 32'h600D_600D, 4'hF, 0, 0, 0);
    expect_write("write after reset", 32'h600, 32'h600D_600D, OKAY);
    cnt0 = apb_count; axi_read(32'h0000_0600, 0);
    expect_read("read after reset", 32'h600, 32'h600D_600D, OKAY);

    if (errors == 0) $display("PASSED ALL (%0d APB transfers)", apb_count);
    else             $display("FAILED: %0d error(s)", errors);
    $finish;
  end

  // global watchdog
  initial begin
    #2_000_000;
    $display("FAIL watchdog: simulation did not finish");
    $finish;
  end

endmodule
