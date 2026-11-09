`ifndef __GUARD_environment_SV__
`define __GUARD_environment_SV__ 0

`include "component/host_agent.sv"
`include "component/scoreboard.sv"
`include "component/ddr3_monitor.sv"

class environment extends uvm_env;
  `uvm_component_utils(environment)

  host_agent      agt;
  host_scoreboard scb;
  ddr3_monitor    mon;

  function new(string name = "environment", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = host_agent::type_id::create("agt", this);
    scb = host_scoreboard::type_id::create("scb", this);
    mon = ddr3_monitor::type_id::create("mon", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.ap.connect(scb.ap_imp);
  endfunction

endclass

`endif