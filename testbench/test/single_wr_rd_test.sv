`ifndef __GUARD_DDR3_SINGLE_WR_RD_TEST_SV__
`define __GUARD_DDR3_SINGLE_WR_RD_TEST_SV__

`include "test/base_test.sv"
`include "obj/host_single_wr_rd_seq.sv"

class single_wr_rd_test extends base_test;
  `uvm_component_utils(single_wr_rd_test)

  function new(string name = "single_wr_rd_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    host_single_wr_rd_seq seq;

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting single_wr_rd_test sequence...", UVM_LOW)

    seq = host_single_wr_rd_seq::type_id::create("seq");
    seq.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();

    `uvm_info("TEST", "Completed single_wr_rd_test sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif