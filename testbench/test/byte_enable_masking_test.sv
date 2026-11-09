`ifndef __GUARD_BYTE_ENABLE_MASKING_TEST_SV__
`define __GUARD_BYTE_ENABLE_MASKING_TEST_SV__

`include "test/base_test.sv"
`include "obj/byte_enable_masking_seq.sv"

class byte_enable_masking_test extends base_test;
  `uvm_component_utils(byte_enable_masking_test)

  function new(string name = "byte_enable_masking_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    byte_enable_seq seq;

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting byte_enable_masking_test sequence...", UVM_LOW)

    seq = byte_enable_seq::type_id::create("seq");
    seq.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();

    `uvm_info("TEST", "Completed byte_enable_masking_test sequence!", UVM_LOW)
    phase.drop_objection(this);
  endtask
  endclass
`endif
