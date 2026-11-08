`ifndef CHECK_INITIALIZATION_SV
`define CHECK_INITIALIZATION_SV

localparam int INIT_TIMEOUT_CYCLES = 20_000;

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
    @(negedge u_ctrl_if.clk);

    if (u_cnfg_if.init_done === 1'b1) begin
      initialization_complete = 1;
      break;
    end

    if ({u_cnfg_if.mr0, u_cnfg_if.mr1, u_cnfg_if.mr2, u_cnfg_if.mr3} ===
        {expected_mr0, expected_mr1, expected_mr2, expected_mr3}) begin
      configuration_seen = 1;
    end else if (configuration_seen) begin
      $fatal(1, "Configuration changed before initialization completed");
    end

    if ((u_host_if.wa_valid !== 1'b0) ||
        (u_host_if.wd_valid !== 1'b0) ||
        (u_host_if.ra_valid !== 1'b0)) begin
      $fatal(1, "Host traffic was driven during initialization");
    end

    if (u_ddr3_if.rst_n === 1'b1) begin
      reset_released = 1;
    end
    if ((u_ddr3_if.cke === 1'b1) && !reset_released) begin
      $fatal(1, "DDR3 CKE asserted before DDR3 reset was released");
    end

    command = {u_ddr3_if.cs_n, u_ddr3_if.ras_n, u_ddr3_if.cas_n, u_ddr3_if.we_n};
    if ($isunknown(command)) begin
      $fatal(1, "Unknown DDR3 command during initialization");
    end

    if (command !== previous_command) begin
      if ((command == 4'b0000) && !configuration_seen) begin
        $fatal(1, "MRS command issued before the configuration was applied");
      end
      case (command)
        4'b0000: begin
          case (mrs_count)
            0: if ((u_ddr3_if.ba !== 3'd2) || (u_ddr3_if.addr !== expected_mr2))
                 $fatal(1, "Expected MR2 value 0x%0h; got BA=%0d ADDR=0x%0h",
                        expected_mr2, u_ddr3_if.ba, u_ddr3_if.addr);
            1: if ((u_ddr3_if.ba !== 3'd3) || (u_ddr3_if.addr !== expected_mr3))
                 $fatal(1, "Expected MR3 value 0x%0h; got BA=%0d ADDR=0x%0h",
                        expected_mr3, u_ddr3_if.ba, u_ddr3_if.addr);
            2: if ((u_ddr3_if.ba !== 3'd1) || (u_ddr3_if.addr !== expected_mr1))
                 $fatal(1, "Expected MR1 value 0x%0h; got BA=%0d ADDR=0x%0h",
                        expected_mr1, u_ddr3_if.ba, u_ddr3_if.addr);
            3: if ((u_ddr3_if.ba !== 3'd0) || (u_ddr3_if.addr !== expected_mr0))
                 $fatal(1, "Expected MR0 value 0x%0h; got BA=%0d ADDR=0x%0h",
                        expected_mr0, u_ddr3_if.ba, u_ddr3_if.addr);
            default: $fatal(1, "Unexpected extra MRS command");
          endcase
          mrs_count++;
        end

        4'b0110: begin
          if ((mrs_count != 4) || (zqcl_count != 0) || (u_ddr3_if.addr[10] !== 1'b1)) begin
            $fatal(1, "Unexpected ZQCL command: MR count=%0d ZQCL count=%0d ADDR=0x%0h",
                   mrs_count, zqcl_count, u_ddr3_if.addr);
          end
          zqcl_count++;
        end

        4'b0011, 4'b0100, 4'b0101, 4'b0001:
          $fatal(1, "Host/refresh command 0x%0h issued before init_done", command);
        default: begin
        end
      endcase
      previous_command = command;
    end
  end

  if (!initialization_complete) begin
    $fatal(1, "DDR3 initialization did not complete within %0d clocks",
           INIT_TIMEOUT_CYCLES);
  end
  if ((mrs_count != 4) || (zqcl_count != 1)) begin
    $fatal(1, "Incomplete initialization sequence: MRS=%0d ZQCL=%0d",
           mrs_count, zqcl_count);
  end
  if (!reset_released || (u_ddr3_if.cke !== 1'b1)) begin
    $fatal(1, "DDR3 reset/CKE power-up sequence did not complete");
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
      u_cnfg_if.apply_cfg(
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

  @(negedge u_ctrl_if.clk);
  if ((u_cnfg_if.init_done !== 1'b1) || (u_dut.idle !== 1'b1) ||
      (u_host_if.wa_ready !== 1'b1) || (u_host_if.wd_ready !== 1'b1) ||
      (u_host_if.ra_ready !== 1'b1)) begin
    $fatal(1, "%s: controller did not become idle and host-ready", case_name);
  end

  repeat (2_000) begin
    @(negedge u_ctrl_if.clk);
    if ((u_cnfg_if.init_done !== 1'b1) || (u_dut.idle !== 1'b1) ||
        (u_host_if.wa_valid !== 1'b0) || (u_host_if.wd_valid !== 1'b0) ||
        (u_host_if.ra_valid !== 1'b0)) begin
      $fatal(1, "%s: controller left the idle initialization state", case_name);
    end
  end

  $display("PASS: %s", case_name);
endtask

task automatic run_tc2_adn_mems_controller_check_initialization();
  u_host_if.reset_signals();
  run_initialization_case("baseline MR configuration", 'h0220, 'h0000, 'h0000, 'h0000);

  fork
    u_ctrl_if.apply_reset(.duration(100ns));
    begin
      wait (u_ctrl_if.arst_n === 1'b0);
      u_cnfg_if.reset_cfg();
    end
  join

  run_initialization_case("alternate CL/CWL configuration", 'h0230, 'h0000, 'h0008, 'h0000);
  $display("PASS: Testcase 2.2 DDR3 Initialization");
endtask

`endif
