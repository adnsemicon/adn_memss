`ifndef __GUARD_HOST_SEQUENCER_SV__
`define __GUARD_HOST_SEQUENCER_SV__

class host_sequencer extends uvm_sequencer #(host_seq_item);
  `uvm_component_utils(host_sequencer)

  function new(string name = "host_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

`endif
