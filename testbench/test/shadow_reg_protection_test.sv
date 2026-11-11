`ifndef __GUARD_ON_THE_FLY_RECONFIG_TEST_SV__
`define __GUARD_ON_THE_FLY_RECONFIG_TEST_SV__ 0

`include "test/base_test.sv"
`include "sequence/host_single_wr_rd_seq.sv"

class shadow_reg_protection_test extends base_test;

  `uvm_component_utils(shadow_reg_protection_test)

  function new(string name = "shadow_reg_protection_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    host_single_wr_rd_seq seq_phase1;
    host_single_wr_rd_seq seq_phase2;

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("ON_THE_FLY","Running baseline traffic with default config ===", UVM_LOW)
    seq_phase1 = host_single_wr_rd_seq::type_id::create("seq_phase1");
    seq_phase1.start(env.agt.sqr);
    env.agt.mon.wait_for_idle();

    `uvm_info("ON_THE_FLY", "Updating timing parameters on-the-fly WITHOUT init_do ===", UVM_LOW)

    cnfg_if.update_timings_on_the_fly(
      .rtc_tp        (rtc_tp),
      .margin_ticks  (-10),
      .custom_tREFI  (300)
    );

    `uvm_info("ON_THE_FLY", "Running post-reconfig traffic ===", UVM_LOW)
    seq_phase2 = host_single_wr_rd_seq::type_id::create("seq_phase2");
    seq_phase2.start(env.agt.sqr);

    env.agt.mon.wait_for_idle();
    #100ns;
    phase.drop_objection(this);
  endtask

endclass

`endif
