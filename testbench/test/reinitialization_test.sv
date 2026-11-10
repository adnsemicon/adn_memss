`ifndef __GUARD_REINITIALIZATION_TEST_SV__
`define __GUARD_REINITIALIZATION_TEST_SV__ 0

`include "test/base_test.sv"
`include "sequence/host_single_wr_rd_seq.sv"

class reinitialization_test extends base_test;
  `uvm_component_utils(reinitialization_test)

  function new(string name = "reinitialization_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    host_single_wr_rd_seq seq_phase1;
    host_single_wr_rd_seq seq_phase2;

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("REINIT_TEST","Running traffic with initial configuration ===", UVM_LOW)
    seq_phase1 = host_single_wr_rd_seq::type_id::create("seq_phase1");
    seq_phase1.start(env.agt.sqr);

    `uvm_info("REINIT_TEST","Updating timings and triggering full re-initialization ===", UVM_LOW)
    cnfg_if.update_timings_on_the_fly(
      .rtc_tp        (rtc_tp),
      .margin_ticks  (4),                               // Default 2 tick bariye test korbe
      .custom_tREFI  (300)
    );

    cnfg_vif.trigger_reinit(
      .new_mr0 ('h1D78),  // WR = 12, DLL Reset = 1, CL = 11, BT = 1 (Interleaved), BL = 8
      .new_mr2 ('h0000)
    );

    `uvm_info("REINIT_TEST", "Running traffic after re-initialization ===", UVM_LOW)
    seq_phase2 = host_single_wr_rd_seq::type_id::create("seq_phase2");
    seq_phase2.start(env.agt.sqr);
    env.agt.mon.wait_for_idle(); 
   
    phase.drop_objection(this);
  endtask

endclass
`endif
