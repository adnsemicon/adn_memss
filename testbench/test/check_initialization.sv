`ifndef __GUARD_CHECK_INITIALIZATION_TEST_SV__
`define __GUARD_CHECK_INITIALIZATION_TEST_SV__

`include "test/base_test.sv"
`include "sequence/check_initialization_seq.sv"

class check_initialization extends base_test;
  `uvm_component_utils(check_initialization)

  function new(string name = "check_initialization", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    uvm_config_db#(bit)::set(this, "env.scb", "expect_reads", 1'b0);
    super.build_phase(phase);
  endfunction

  virtual task configure_phase(uvm_phase phase);
    phase.raise_objection(this);
    ctrl_vif.start_clock();
    phase.drop_objection(this);
  endtask

  virtual task main_phase(uvm_phase phase);
    check_initialization_seq seq;

    super.main_phase(phase);
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting DDR3 initialization sequence...", UVM_LOW)

    seq = check_initialization_seq::type_id::create("seq");
    seq.start(env.agt.sqr);

    `uvm_info("TEST", "Completed DDR3 initialization sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
