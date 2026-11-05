`ifndef __GUARD_environment_SV__
`define __GUARD_environment_SV__ 0

`include "component/host_agent.sv"
`include "component/scoreboard.sv"

class environment extends uvm_env;
  `uvm_component_utils(environment)

  host_agent      agt;
  host_scoreboard scb;

  function new(string name = "environment", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = host_agent::type_id::create("agt", this);
    scb = host_scoreboard::type_id::create("scb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect agent's analysis port to scoreboard's analysis imp
    agt.ap.connect(scb.ap_imp);
  endfunction

endclass

`endif