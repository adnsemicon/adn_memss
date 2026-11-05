`ifndef __GUARD_HOST_ENV_SV__
`define __GUARD_HOST_ENV_SV__

class host_env extends uvm_env;
  `uvm_component_utils(host_env)

  host_sequencer sequencer;
  host_driver driver;
  host_monitor monitor;
  host_scoreboard scoreboard;

  function new(string name = "host_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = host_sequencer::type_id::create("sequencer", this);
    driver = host_driver::type_id::create("driver", this);
    monitor = host_monitor::type_id::create("monitor", this);
    scoreboard = host_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    monitor.ap.connect(scoreboard.analysis_export);
  endfunction
endclass

`endif
