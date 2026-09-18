//==============================================================================
// base_test.sv - common setup for every test: grabs virtual interfaces,
// builds the env, sets a default timeout. Derived tests override
// configure_apb() for their wait-state / error-injection knobs and provide
// their own run_phase() with the sequence(s) that make the test what it is.
//==============================================================================

class base_test extends uvm_test;

  `uvm_component_utils(base_test)

  env          env_h;
  env_cfg      cfg;
  axi_lite_cfg axi_cfg;
  apb_cfg      apb_cfg_h;

  virtual reset_if reset_vif;

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    axi_cfg = axi_lite_cfg::type_id::create("axi_cfg");
    axi_cfg.is_active = UVM_ACTIVE;
    if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "axi_vif", axi_cfg.vif))
      `uvm_fatal("NOVIF", "axi_vif not found in config db")

    apb_cfg_h = apb_cfg::type_id::create("apb_cfg_h");
    apb_cfg_h.is_active = UVM_ACTIVE;
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", apb_cfg_h.vif))
      `uvm_fatal("NOVIF", "apb_vif not found in config db")
    configure_apb(apb_cfg_h);

    if (!uvm_config_db#(virtual reset_if)::get(this, "", "reset_vif", reset_vif))
      `uvm_fatal("NOVIF", "reset_vif not found in config db")

    cfg           = env_cfg::type_id::create("cfg");
    cfg.axi_cfg   = axi_cfg;
    cfg.apb_cfg_h = apb_cfg_h;
    uvm_config_db#(env_cfg)::set(this, "env_h", "cfg", cfg);

    env_h = env::type_id::create("env_h", this);
  endfunction

  // Default APB slave behaviour: light wait states, no errors. Derived
  // tests override this for the scenario they specifically target.
  virtual function void configure_apb(apb_cfg c);
    c.min_wait_cycles = 0;
    c.max_wait_cycles = 3;
    c.error_pct       = 0;
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.set_timeout(200us, 0);
  endfunction

endclass : base_test
