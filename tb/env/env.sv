//==============================================================================
// env.sv - top-level UVM environment
//==============================================================================

class env_cfg extends uvm_object;

  `uvm_object_utils(env_cfg)

  axi_lite_cfg axi_cfg;
  apb_cfg      apb_cfg_h;

  function new(string name = "env_cfg");
    super.new(name);
  endfunction

endclass : env_cfg


class env extends uvm_env;

  `uvm_component_utils(env)

  env_cfg             cfg;
  axi_lite_agent       axi_agent;
  apb_agent            apb_agt;
  scoreboard           sb;
  coverage_collector   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null && !uvm_config_db#(env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "env_cfg must be set for env")

    uvm_config_db#(axi_lite_cfg)::set(this, "axi_agent", "cfg", cfg.axi_cfg);
    uvm_config_db#(apb_cfg)::set(this, "apb_agt", "cfg", cfg.apb_cfg_h);

    axi_agent = axi_lite_agent::type_id::create("axi_agent", this);
    apb_agt   = apb_agent::type_id::create("apb_agt", this);
    sb        = scoreboard::type_id::create("sb", this);
    cov       = coverage_collector::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    axi_agent.ap.connect(sb.axi_fifo.analysis_export);
    apb_agt.ap.connect(sb.apb_fifo.analysis_export);
    axi_agent.ap.connect(cov.axi_imp);
    apb_agt.ap.connect(cov.apb_imp);
  endfunction

endclass : env
