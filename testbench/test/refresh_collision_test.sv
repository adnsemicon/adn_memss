`ifndef __GUARD_REFRESH_COLLISION_TEST_SV__
`define __GUARD_REFRESH_COLLISION_TEST_SV__

`include "test/base_test.sv"
`include "sequence/random_stress_seq.sv"

class refresh_collision_test extends base_test;
  `uvm_component_utils(refresh_collision_test)

  function new(string name = "refresh_collision_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task configure_phase(uvm_phase phase);
    super.configure_phase(phase);
    cnfg_vif.set_fast_refresh(16'd100);
  endtask

  virtual task main_phase(uvm_phase phase);
    random_stress_seq seq;

    super.main_phase(phase);
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting refresh_collision_test sequence...", UVM_LOW)

    seq = random_stress_seq::type_id::create("seq");
    seq.randomize();
    seq.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();

    `uvm_info("TEST", "Completed random_stress_test sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif