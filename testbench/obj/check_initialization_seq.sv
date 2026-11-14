`ifndef __GUARD_CHECK_INITIALIZATION_SEQ_SV__
`define __GUARD_CHECK_INITIALIZATION_SEQ_SV__

class check_initialization_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(check_initialization_seq)

  localparam int INIT_TIMEOUT_CYCLES = 20_000;

  virtual ctrl_if ctrl_vif;
  virtual cnfg_if #(.DRAM_ADDR_BITS(DRAM_ADDR_BITS)) cnfg_vif;
  virtual host_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .BE_WIDTH   (BE_WIDTH),
    .BURST_LEN  (BURST_LEN)
  ) host_vif;
  virtual ddr3_if #(
    .DRAM_BA_BITS   (DRAM_BA_BITS),
    .DRAM_ADDR_BITS (DRAM_ADDR_BITS),
    .DM_WIDTH       (DM_WIDTH),
    .DQS_WIDTH      (DQS_WIDTH),
    .DATA_WIDTH    (DATA_WIDTH)
  ) ddr3_vif;

  function new(string name = "check_initialization_seq");
    super.new(name);
  endfunction

  virtual task body();
    if (!uvm_config_db#(virtual ctrl_if)::get(m_sequencer, "", "ctrl_vif", ctrl_vif)) begin
      `uvm_fatal("NOVIF", "ctrl_vif was not found in uvm_config_db")
    end
    if (!uvm_config_db#(virtual cnfg_if #(
      .DRAM_ADDR_BITS (DRAM_ADDR_BITS)
    ))::get(m_sequencer, "", "cnfg_vif", cnfg_vif)) begin
      `uvm_fatal("NOVIF", "cnfg_vif was not found in uvm_config_db")
    end
    if (!uvm_config_db#(virtual host_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH),
      .BE_WIDTH   (BE_WIDTH),
      .BURST_LEN  (BURST_LEN)
    ))::get(m_sequencer, "", "host_vif", host_vif)) begin
      `uvm_fatal("NOVIF", "host_vif was not found in uvm_config_db")
    end
    if (!uvm_config_db#(virtual ddr3_if #(
      .DRAM_BA_BITS   (DRAM_BA_BITS),
      .DRAM_ADDR_BITS (DRAM_ADDR_BITS),
      .DM_WIDTH       (DM_WIDTH),
      .DQS_WIDTH      (DQS_WIDTH),
      .DATA_WIDTH     (DATA_WIDTH)
    ))::get(m_sequencer, "", "ddr3_vif", ddr3_vif)) begin
      `uvm_fatal("NOVIF", "ddr3_vif was not found in uvm_config_db")
    end

    host_vif.reset_signals();
    run_initialization_case("baseline MR configuration", 'h0220, 'h0000, 'h0000, 'h0000);

    fork
      ctrl_vif.apply_reset(.duration(100ns));
      begin
        wait (ctrl_vif.arst_n === 1'b0);
        cnfg_vif.reset_cfg();
      end
    join

    run_initialization_case("alternate CL/CWL configuration", 'h0230, 'h0000, 'h0008, 'h0000);
    `uvm_info("TEST", "PASS: Testcase 2.2 DDR3 Initialization", UVM_LOW)
  endtask

  task automatic check_initialization_sequence(
    input logic [DRAM_ADDR_BITS-1:0] expected_mr0,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr1,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr2,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr3
  );
    int unsigned mrs_count;
    int unsigned zqcl_count;
    bit reset_released;
    bit configuration_seen;
    bit initialization_complete;
    logic [3:0] command;
    logic [3:0] previous_command;

    mrs_count = 0;
    zqcl_count = 0;
    reset_released = 0;
    configuration_seen = 0;
    initialization_complete = 0;
    previous_command = 4'b1111;

    for (int cycle = 0; cycle < INIT_TIMEOUT_CYCLES; cycle++) begin
      @(negedge ctrl_vif.clk);

      if (cnfg_vif.init_done === 1'b1) begin
        initialization_complete = 1;
        break;
      end

      if ({cnfg_vif.mr0, cnfg_vif.mr1, cnfg_vif.mr2, cnfg_vif.mr3} ===
          {expected_mr0, expected_mr1, expected_mr2, expected_mr3}) begin
        configuration_seen = 1;
      end else if (configuration_seen) begin
        `uvm_fatal("INITCFG", "Configuration changed before initialization completed")
      end

      if ((host_vif.wa_valid !== 1'b0) ||
          (host_vif.wd_valid !== 1'b0) ||
          (host_vif.ra_valid !== 1'b0)) begin
        `uvm_fatal("INITBUS", "Host traffic was driven during initialization")
      end

      if (ddr3_vif.rst_n === 1'b1) begin
        reset_released = 1;
      end
      if ((ddr3_vif.cke === 1'b1) && !reset_released) begin
        `uvm_fatal("INITPWR", "DDR3 CKE asserted before DDR3 reset was released")
      end

      command = {ddr3_vif.cs_n, ddr3_vif.ras_n, ddr3_vif.cas_n, ddr3_vif.we_n};
      if ($isunknown(command)) begin
        `uvm_fatal("INITCMD", "Unknown DDR3 command during initialization")
      end

      if (command !== previous_command) begin
        if ((command == 4'b0000) && !configuration_seen) begin
          `uvm_fatal("INITCFG", "MRS command issued before the configuration was applied")
        end
        case (command)
          4'b0000: begin
            case (mrs_count)
              0: if ((ddr3_vif.ba !== 3'd2) || (ddr3_vif.addr !== expected_mr2))
                   `uvm_fatal("INITMRS", $sformatf(
                     "Expected MR2 value 0x%0h; got BA=%0d ADDR=0x%0h",
                     expected_mr2, ddr3_vif.ba, ddr3_vif.addr))
              1: if ((ddr3_vif.ba !== 3'd3) || (ddr3_vif.addr !== expected_mr3))
                   `uvm_fatal("INITMRS", $sformatf(
                     "Expected MR3 value 0x%0h; got BA=%0d ADDR=0x%0h",
                     expected_mr3, ddr3_vif.ba, ddr3_vif.addr))
              2: if ((ddr3_vif.ba !== 3'd1) || (ddr3_vif.addr !== expected_mr1))
                   `uvm_fatal("INITMRS", $sformatf(
                     "Expected MR1 value 0x%0h; got BA=%0d ADDR=0x%0h",
                     expected_mr1, ddr3_vif.ba, ddr3_vif.addr))
              3: if ((ddr3_vif.ba !== 3'd0) || (ddr3_vif.addr !== expected_mr0))
                   `uvm_fatal("INITMRS", $sformatf(
                     "Expected MR0 value 0x%0h; got BA=%0d ADDR=0x%0h",
                     expected_mr0, ddr3_vif.ba, ddr3_vif.addr))
              default: `uvm_fatal("INITMRS", "Unexpected extra MRS command")
            endcase
            mrs_count++;
          end

          4'b0110: begin
            if ((mrs_count != 4) || (zqcl_count != 0) || (ddr3_vif.addr[10] !== 1'b1)) begin
              `uvm_fatal("INITZQCL", $sformatf(
                "Unexpected ZQCL command: MR count=%0d ZQCL count=%0d ADDR=0x%0h",
                mrs_count, zqcl_count, ddr3_vif.addr))
            end
            zqcl_count++;
          end

          4'b0011, 4'b0100, 4'b0101, 4'b0001:
            `uvm_fatal("INITCMD", $sformatf(
              "Host/refresh command 0x%0h issued before init_done", command))
          default: begin
          end
        endcase
        previous_command = command;
      end
    end

    if (!initialization_complete) begin
      `uvm_fatal("INITTIMEOUT", $sformatf(
        "DDR3 initialization did not complete within %0d clocks", INIT_TIMEOUT_CYCLES))
    end
    if ((mrs_count != 4) || (zqcl_count != 1)) begin
      `uvm_fatal("INITSEQ", $sformatf(
        "Incomplete initialization sequence: MRS=%0d ZQCL=%0d", mrs_count, zqcl_count))
    end
    if (!reset_released || (ddr3_vif.cke !== 1'b1)) begin
      `uvm_fatal("INITPWR", "DDR3 reset/CKE power-up sequence did not complete")
    end
  endtask

  task automatic run_initialization_case(
    input string case_name,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr0,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr1,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr2,
    input logic [DRAM_ADDR_BITS-1:0] expected_mr3
  );
    fork
      begin
        cnfg_vif.apply_cfg(
          .in_mr0(expected_mr0),
          .in_mr1(expected_mr1),
          .in_mr2(expected_mr2),
          .in_mr3(expected_mr3)
        );
      end
      begin
        check_initialization_sequence(expected_mr0, expected_mr1, expected_mr2, expected_mr3);
      end
    join

    @(negedge ctrl_vif.clk);
    if ((cnfg_vif.init_done !== 1'b1) ||
        (ddr3_vif.current_fsm_state != "IDLE") ||
        (host_vif.wa_ready !== 1'b1) ||
        (host_vif.wd_ready !== 1'b1) ||
        (host_vif.ra_ready !== 1'b1)) begin
      `uvm_fatal("INITIDLE", $sformatf(
        "%s: controller did not become idle and host-ready", case_name))
    end

    repeat (2_000) begin
      @(negedge ctrl_vif.clk);
      if ((cnfg_vif.init_done !== 1'b1) ||
          (ddr3_vif.current_fsm_state != "IDLE") ||
          (host_vif.wa_valid !== 1'b0) ||
          (host_vif.wd_valid !== 1'b0) ||
          (host_vif.ra_valid !== 1'b0)) begin
        `uvm_fatal("INITIDLE", $sformatf(
          "%s: controller left the idle initialization state", case_name))
      end
    end

    `uvm_info("TEST", $sformatf("PASS: %s", case_name), UVM_LOW)
  endtask

endclass

`endif
