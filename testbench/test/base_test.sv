`ifndef __GUARD_DDR3_BASE_TEST_SV__
`define __GUARD_DDR3_BASE_TEST_SV__

`include "component/env.sv"

class base_test extends uvm_test;

  `uvm_component_utils(base_test)

  function new (string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  environment env;
  realtime rtc_tp;

  virtual ctrl_if ctrl_vif;
  virtual cnfg_if #(
    .DRAM_ADDR_BITS (DRAM_ADDR_BITS)
  ) cnfg_vif;
  virtual host_if #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .BE_WIDTH       (BE_WIDTH),
    .BURST_LEN      (BURST_LEN)
  ) host_vif;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (get_type_name() == "base_test")
      uvm_config_db#(bit)::set(this, "env.scb", "expect_reads", 1'b0);
    env = environment::type_id::create("env", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (!uvm_config_db #(virtual ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
      `uvm_fatal("NOVIF", "ctrl_vif was not found in uvm_config_db")
    end

    if (!uvm_config_db #(virtual cnfg_if #(
      .DRAM_ADDR_BITS (DRAM_ADDR_BITS)
    ))::get(this, "", "cnfg_vif", cnfg_vif)) begin
      `uvm_fatal("NOVIF", "cnfg_vif was not found in uvm_config_db")
    end

    if (!uvm_config_db #(virtual host_if #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .DATA_WIDTH     (DATA_WIDTH),
      .BE_WIDTH       (BE_WIDTH),
      .BURST_LEN      (BURST_LEN)
    ))::get(this, "", "host_vif", host_vif)) begin
      `uvm_fatal("NOVIF", "host_vif was not found in uvm_config_db")
    end

    if(!uvm_config_db #(realtime)::get(this, "", "rtc_tp", rtc_tp)) begin
      `uvm_fatal("NO RTC_TP", "rtc_tp was not found in uvm_config_db")
    end
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual task reset_phase(uvm_phase phase);
    super.reset_phase(phase);
    phase.raise_objection(this);
    host_vif.reset_signals();
    cnfg_vif.reset_cfg();
    ctrl_vif.apply_reset();
    phase.drop_objection(this);
  endtask

  virtual task configure_phase(uvm_phase phase);
    super.configure_phase(phase);
    phase.raise_objection(this);
    ctrl_vif.start_clock();
    cnfg_vif.apply_cfg(.rtc_tp(rtc_tp));
    phase.drop_objection(this);
  endtask


  virtual task shutdown_phase(uvm_phase phase);
    super.shutdown_phase(phase);
    phase.raise_objection(this);
    repeat (50) @(posedge host_vif.clk);
    phase.drop_objection(this);
  endtask

endclass

`endif