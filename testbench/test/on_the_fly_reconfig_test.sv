`ifndef __GUARD_ON_THE_FLY_RECONFIG_TEST_SV__
`define __GUARD_ON_THE_FLY_RECONFIG_TEST_SV__ 0

`include "test/base_test.sv"
`include "obj/host_single_wr_rd_seq.sv"

class on_the_fly_reconfig_test extends base_test;

  `uvm_component_utils(on_the_fly_reconfig_test)

  function new(string name = "on_the_fly_reconfig_test", uvm_component parent = null);
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

    `uvm_info("ON_THE_FLY", "Updating timing parameters on-the-fly & triggering init_do ===", UVM_LOW)
    cnfg_vif.update_timings_on_the_fly(
      .in_tRCD  (16'd6  ),   // 16'd4  
      .in_tRP   (16'd6  ),   // 16'd4 
      .in_tRAS  (16'd14 ),   // 16'd8   
      .in_tRC   (16'd20 ),   // 16'd12  
      .in_tWR   (16'd6  ),   // 16'd4   
      .in_tRTP  (16'd4  ),   // 16'd4   
      .in_tWTR  (16'd4  ),   // 16'd4   
      .in_tRRD  (16'd4  ),   // 16'd4   
      .in_tFAW  (16'd7  ),   // 16'd10  
      .in_tRFC  (16'd18 ),   // 16'd28  
      .in_tREFI (16'd680)   // 16'd780  
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
