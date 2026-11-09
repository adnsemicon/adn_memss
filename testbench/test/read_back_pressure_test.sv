`ifndef __GUARD_READ_BACK_PRESSURE_TEST_SV__
`define __GUARD_READ_BACK_PRESSURE_TEST_SV__

`include "test/base_test.sv"
`include "obj/read_back_pressure_seq.sv"

class read_back_pressure_test extends base_test;
  `uvm_component_utils(read_back_pressure_test)

  function new(string name = "read_back_pressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    read_back_pressure_seq seq;
    uvm_config_db#(int)::set(uvm_root::get(), "parameter", "seq_length", 4);

    super.main_phase(phase);
    //phase.phase_done.set_drain_time(this, 2000ns);
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting read_back_pressure_test sequence...", UVM_LOW)

    seq = read_back_pressure_seq::type_id::create("seq");
    seq.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();

    `uvm_info("TEST", "Completed read_back_pressure_test sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask
  endclass
`endif
