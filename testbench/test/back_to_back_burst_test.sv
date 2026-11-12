`ifndef __GUARD_BACK_TO_BACK_BURST_TEST_SV__
`define __GUARD_BACK_TO_BACK_BURST_TEST_SV__

`include "test/base_test.sv"
`include "sequence/back_to_back_burst_seq.sv"

class back_to_back_burst_test extends base_test;
  `uvm_component_utils(back_to_back_burst_test)

  function new(string name = "back_to_back_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    back_to_back_burst_seq seq;
    uvm_config_db#(int)::set(uvm_root::get(), "parameter", "seq_length", 4);

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting back_to_back_burst_test sequence...", UVM_LOW)

    seq = back_to_back_burst_seq::type_id::create("seq");
    seq.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();

    `uvm_info("TEST", "Completed back_to_back_burst_test sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask
  endclass
`endif
