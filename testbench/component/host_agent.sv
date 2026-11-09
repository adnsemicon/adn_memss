`ifndef __GUARD_HOST_AGENT_SV__
`define __GUARD_HOST_AGENT_SV__ 0

`include "component/host_driver.sv"
`include "component/host_monitor.sv"

class host_agent extends uvm_agent;

  `uvm_component_utils(host_agent)

  uvm_analysis_port #(host_seq_item) ap;

  uvm_sequencer     #(host_seq_item) sqr;
  host_driver                        dvr;
  host_monitor                       mon;

  function new (string name = "host_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap  = new("ap", this);
    mon = host_monitor::type_id::create("mon", this);

    if (get_is_active() == UVM_ACTIVE) begin
      sqr = uvm_sequencer#(host_seq_item)::type_id::create("sqr", this);
      dvr = host_driver::type_id::create("dvr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      dvr.seq_item_port.connect(sqr.seq_item_export);
    end
    mon.ap.connect(ap);
  endfunction

endclass

`endif
