`ifndef __GUARD_DDR3_RESET_TEST_SV__
`define __GUARD_DDR3_RESET_TEST_SV__

`include "test/base_test.sv"

class reset_test extends base_test;
  `uvm_component_utils(reset_test)

  function new(string name = "reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "env.scb", "expect_reads", 1'b0);
  endfunction

  virtual task main_phase(uvm_phase phase);
    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting reset_test...", UVM_LOW)

    repeat (2) begin
      ctrl_vif.apply_reset();
      if (cnfg_vif.init_done !== 1'b0)
        `uvm_error("RESET", "init_done did not clear during reset")

      wait (cnfg_vif.init_done === 1'b1);
      `uvm_info("RESET", "Controller completed initialization after reset", UVM_MEDIUM)
    end

    `uvm_info("TEST", "Completed reset_test!", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
