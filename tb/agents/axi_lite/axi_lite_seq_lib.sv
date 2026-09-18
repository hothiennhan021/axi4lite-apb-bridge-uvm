//==============================================================================
// axi_lite_seq_lib.sv - sequence library for the AXI4-Lite master agent
// (see verification_plan.md section 5)
//==============================================================================

class axi_write_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_write_seq)

  rand bit [31:0] addr;
  rand bit [31:0] data;
  rand bit [3:0]  wstrb;

  function new(string name = "axi_write_seq");
    super.new(name);
  endfunction

  task body();
    req = axi_lite_txn::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          dir   == AXI_WRITE;
          addr  == local::addr;
          data  == local::data;
          wstrb == local::wstrb;
        })
      `uvm_error(get_type_name(), "randomize failed")
    finish_item(req);
  endtask
endclass : axi_write_seq


class axi_read_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_read_seq)

  rand bit [31:0] addr;

  function new(string name = "axi_read_seq");
    super.new(name);
  endfunction

  task body();
    req = axi_lite_txn::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          dir  == AXI_READ;
          addr == local::addr;
        })
      `uvm_error(get_type_name(), "randomize failed")
    finish_item(req);
  endtask
endclass : axi_read_seq


class axi_rand_rw_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_rand_rw_seq)

  rand int unsigned num_txns = 20;

  function new(string name = "axi_rand_rw_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_txns) begin
      req = axi_lite_txn::type_id::create("req");
      start_item(req);
      if (!req.randomize())
        `uvm_error(get_type_name(), "randomize failed")
      finish_item(req);
    end
  endtask
endclass : axi_rand_rw_seq


class axi_back2back_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_back2back_seq)

  rand int unsigned num_txns = 20;

  function new(string name = "axi_back2back_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_txns) begin
      req = axi_lite_txn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { delay == 0; })
        `uvm_error(get_type_name(), "randomize failed")
      finish_item(req);
    end
  endtask
endclass : axi_back2back_seq


class axi_same_addr_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_same_addr_seq)

  rand bit [31:0] addr;
  rand bit [31:0] data;

  function new(string name = "axi_same_addr_seq");
    super.new(name);
  endfunction

  task body();
    req = axi_lite_txn::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          dir   == AXI_WRITE;
          addr  == local::addr;
          data  == local::data;
          wstrb == 4'b1111;
        })
      `uvm_error(get_type_name(), "randomize failed")
    finish_item(req);

    req = axi_lite_txn::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          dir  == AXI_READ;
          addr == local::addr;
        })
      `uvm_error(get_type_name(), "randomize failed")
    finish_item(req);
  endtask
endclass : axi_same_addr_seq


class axi_backpressure_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_backpressure_seq)

  rand int unsigned num_txns = 20;

  function new(string name = "axi_backpressure_seq");
    super.new(name);
  endfunction

  task body();
    repeat (num_txns) begin
      req = axi_lite_txn::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { resp_ready_delay inside {[0:8]}; })
        `uvm_error(get_type_name(), "randomize failed")
      finish_item(req);
    end
  endtask
endclass : axi_backpressure_seq


class axi_wstrb_sweep_seq extends uvm_sequence #(axi_lite_txn);
  `uvm_object_utils(axi_wstrb_sweep_seq)

  function new(string name = "axi_wstrb_sweep_seq");
    super.new(name);
  endfunction

  task body();
    bit [3:0] pattern;
    for (int i = 0; i < 16; i++) begin
      pattern = i[3:0];
      req = axi_lite_txn::type_id::create("req");
      start_item(req);
      // wstrb is set by plain assignment after randomizing everything else,
      // rather than via an inline `wstrb == pattern` constraint - the XSim
      // constraint solver was observed to hang indefinitely on some values
      // of that equality constraint (reproducible: fine for 4'b0000/0001,
      // hangs on 4'b0010 with this exact class). Since WSTRB has no
      // constraint relationship to any other field, a direct assignment is
      // equivalent and sidesteps the solver entirely.
      if (!req.randomize() with { dir == AXI_WRITE; })
        `uvm_error(get_type_name(), "randomize failed")
      req.wstrb = pattern;
      finish_item(req);
    end
  endtask
endclass : axi_wstrb_sweep_seq
