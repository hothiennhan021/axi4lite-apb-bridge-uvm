//==============================================================================
// scoreboard.sv - transaction-level comparison between the AXI4-Lite side
// and the APB side. Rationale for the analysis-fifo pairing (rather than a
// predictor/reference-model split) is in docs/design_decisions.md.
//==============================================================================

class scoreboard extends uvm_scoreboard;

  `uvm_component_utils(scoreboard)

  uvm_tlm_analysis_fifo #(axi_lite_txn) axi_fifo;
  uvm_tlm_analysis_fifo #(apb_txn)      apb_fifo;

  virtual reset_if reset_vif;

  int unsigned num_compared;
  int unsigned num_mismatched;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_fifo = new("axi_fifo", this);
    apb_fifo = new("apb_fifo", this);
    if (!uvm_config_db#(virtual reset_if)::get(this, "", "reset_vif", reset_vif))
      `uvm_fatal("NOVIF", "reset_vif not found in config db")
  endfunction

  // FEAT-010/014: the AXI and APB monitors each independently decide when
  // to abandon a reset-interrupted transaction, and their exact abort
  // timing does not line up cycle-for-cycle - in rare timing windows one
  // side can publish one more (or fewer) transaction than the other around
  // a reset event, permanently shifting every pairing after it. Rather than
  // chase perfect symmetry between two independently-clocked monitors, the
  // scoreboard drops whatever pairing round was in flight when reset
  // asserts and flushes both fifos once it clears, which is the point
  // where any such asymmetry could have been introduced.
  task run_phase(uvm_phase phase);
    axi_lite_txn axi_tr;
    apb_txn      apb_tr;
    bit [1:0]    expected_resp;
    bit          aborted;

    forever begin
      aborted = 1'b0;
      fork
        begin
          axi_fifo.get(axi_tr);
          apb_fifo.get(apb_tr);
        end
        begin
          wait (reset_vif.rst_n === 1'b0);
          aborted = 1'b1;
        end
      join_any
      disable fork;

      if (aborted) begin
        wait (reset_vif.rst_n === 1'b1);
        axi_fifo.flush();
        apb_fifo.flush();
        continue;
      end

      num_compared++;

      if ((axi_tr.dir == AXI_WRITE) != apb_tr.pwrite) begin
        num_mismatched++;
        `uvm_error("SB_DIR", $sformatf(
          "direction mismatch: axi.dir=%s apb.pwrite=%0b", axi_tr.dir.name(), apb_tr.pwrite))
      end

      if (axi_tr.addr !== apb_tr.addr) begin
        num_mismatched++;
        `uvm_error("SB_ADDR", $sformatf(
          "address mismatch: axi.addr=%0h apb.addr=%0h", axi_tr.addr, apb_tr.addr))
      end

      if (axi_tr.dir == AXI_WRITE && axi_tr.data !== apb_tr.wdata) begin
        num_mismatched++;
        `uvm_error("SB_WDATA", $sformatf(
          "write data mismatch: axi.data=%0h apb.wdata=%0h", axi_tr.data, apb_tr.wdata))
      end

      if (axi_tr.dir == AXI_READ && axi_tr.data !== apb_tr.rdata) begin
        num_mismatched++;
        `uvm_error("SB_RDATA", $sformatf(
          "read data mismatch: axi.data=%0h apb.rdata=%0h", axi_tr.data, apb_tr.rdata))
      end

      // WSTRB decision (option c): a write with a partial strobe is an
      // SLVERR on BRESP regardless of what the APB slave itself signalled.
      expected_resp = (apb_tr.pslverr || (axi_tr.dir == AXI_WRITE && axi_tr.wstrb != 4'b1111))
                      ? 2'b10 : 2'b00;

      if (axi_tr.resp !== expected_resp) begin
        num_mismatched++;
        `uvm_error("SB_RESP", $sformatf(
          "response mismatch: axi.resp=%0b expected=%0b (apb.pslverr=%0b, wstrb=%b)",
          axi_tr.resp, expected_resp, apb_tr.pslverr, axi_tr.wstrb))
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf(
      "scoreboard: %0d compared, %0d mismatched", num_compared, num_mismatched), UVM_LOW)
  endfunction

endclass : scoreboard
