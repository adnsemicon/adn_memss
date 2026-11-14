`ifndef __GUARD_REINITIALIZATION_TEST_SV__
`define __GUARD_REINITIALIZATION_TEST_SV__ 0

`include "test/base_test.sv"
`include "obj/host_single_wr_rd_seq.sv"

class reinitialization_test extends base_test;
  `uvm_component_utils(reinitialization_test)

  function new(string name = "reinitialization_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

//   virtual task configure_phase(uvm_phase phase);
//     super.configure_phase(phase);
//     phase.raise_objection(this);
//     cnfg_vif.apply_cfg();
//     phase.drop_objection(this);
//   endtask

  virtual task main_phase(uvm_phase phase);
    host_single_wr_rd_seq seq_phase1;
    host_single_wr_rd_seq seq_phase2;

    super.main_phase(phase);
    phase.raise_objection(this);

    `uvm_info("REINIT_TEST","Running traffic with initial configuration ===", UVM_LOW)
    seq_phase1 = host_single_wr_rd_seq::type_id::create("seq_phase1");
    seq_phase1.start(env.agt.sqr);

    #600ns;

    `uvm_info("REINIT_TEST","Updating timings and triggering full re-initialization ===", UVM_LOW)
    cnfg_vif.update_timings_on_the_fly(
      .in_tRCD  (16'd6),
      .in_tRP   (16'd6),
      .in_tRAS  (16'd14),
      .in_tRC   (16'd20),
      .in_tWR   (16'd6),
      .in_tRTP  (16'd4),
      .in_tWTR  (16'd4),
      .in_tRRD  (16'd4),
      .in_tFAW  (16'd7),
      .in_tRFC  (16'd18),
      .in_tREFI (16'd680)
    );

    cnfg_vif.trigger_reinit(
      .new_mr0 ('h1D78),  // WR = 12, DLL Reset = 1, CL = 11, BT = 1 (Interleaved), BL = 8
      .new_mr2 ('h0000)
    );

    `uvm_info("REINIT_TEST", "Running traffic after re-initialization ===", UVM_LOW)
    seq_phase2 = host_single_wr_rd_seq::type_id::create("seq_phase2");
    seq_phase2.start(env.agt.sqr);

    #600ns;
    phase.drop_objection(this);
  endtask

endclass
`endif
