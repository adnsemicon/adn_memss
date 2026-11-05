`include "uvm_macros.svh"
import uvm_pkg::*;
import ddr3_params_pkg::*;
`include "test/single_wr_rd_test.sv"
// `include "../package/host_params_pkg.sv"

module ddr3_controller_uvm_tb;

  // -------------------------------------------------------------------------
  // Interface Instantiations
  // -------------------------------------------------------------------------
  ctrl_if u_ctrl_if();

  host_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .BE_WIDTH   (DATA_WIDTH / 8),
        .BURST_LEN  (BURST_LEN)
  ) u_host_if(
        .clk(u_ctrl_if.clk), 
        .arst_n(u_ctrl_if.arst_n));

  cnfg_if #(.DRAM_ADDR_BITS(DRAM_ADDR_BITS)) u_cnfg_if(
        .clk(u_ctrl_if.clk),
        .arst_n(u_ctrl_if.arst_n)
  );

  // -------------------------------------------------------------------------
  // Interconnect Wires between Controller and DDR3 Chip Array
  // -------------------------------------------------------------------------
  logic                       ddr3_ck_p;
  logic                       ddr3_ck_n;
  logic                       ddr3_rst_n;
  logic                       ddr3_cke;
  logic                       ddr3_cs_n;
  logic                       ddr3_ras_n;
  logic                       ddr3_cas_n;
  logic                       ddr3_we_n;
  logic                       ddr3_odt;
  logic                       idle;
  logic [DRAM_BA_BITS-1:0]    ddr3_ba;
  logic [DRAM_ADDR_BITS-1:0]  ddr3_addr;
  wire  [DM_WIDTH-1:0]        ddr3_dm;
  wire  [DQS_WIDTH-1:0]       ddr3_dqs_p;
  wire  [DQS_WIDTH-1:0]       ddr3_dqs_n;
  wire  [DATA_WIDTH-1:0]      ddr3_dq;

  // -------------------------------------------------------------------------
  // DUT: ADN DDR3 Memory Controller Instantiation
  // -------------------------------------------------------------------------
  adn_memss_ddr3_controller #(
    .ADDR_WIDTH      (ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .DRAM_ADDR_BITS  (DRAM_ADDR_BITS),
    .DRAM_BA_BITS    (DRAM_BA_BITS),
    .SIM_SPEED_UP    (1'b1)
  ) u_dut (
    // Clock, RTC & Reset
    .clk             (u_ctrl_if.clk),
    .rtc             (u_ctrl_if.rtc),
    .arst_n          (u_ctrl_if.arst_n),

    // DDR3 Mode Registers (driven from cnfg_if)
    .mr0             (u_cnfg_if.mr0),
    .mr1             (u_cnfg_if.mr1),
    .mr2             (u_cnfg_if.mr2),
    .mr3             (u_cnfg_if.mr3),

    // Core DRAM Timings (driven from cnfg_if)
    .tRCD            (u_cnfg_if.tRCD),
    .tRP             (u_cnfg_if.tRP),
    .tRAS            (u_cnfg_if.tRAS),
    .tRC             (u_cnfg_if.tRC),
    .tWR             (u_cnfg_if.tWR),
    .tRTP            (u_cnfg_if.tRTP),
    .tWTR            (u_cnfg_if.tWTR),
    .tRRD            (u_cnfg_if.tRRD),
    .tFAW            (u_cnfg_if.tFAW),
    .tRFC            (u_cnfg_if.tRFC),
    .tREFI           (u_cnfg_if.tREFI),

    // Write Address Channel (driven from host_if)
    .wa_addr         (u_host_if.wa_addr),
    .wa_valid        (u_host_if.wa_valid),
    .wa_ready        (u_host_if.wa_ready),

    // Write Data Channel
    .wd_data         (u_host_if.wd_data),
    .wd_be           (u_host_if.wd_be),
    .wd_valid        (u_host_if.wd_valid),
    .wd_ready        (u_host_if.wd_ready),

    // Read Address Channel
    .ra_addr         (u_host_if.ra_addr),
    .ra_valid        (u_host_if.ra_valid),
    .ra_ready        (u_host_if.ra_ready),

    // Read Data Channel
    .rd_data         (u_host_if.rd_data),
    .rd_valid        (u_host_if.rd_valid),
    .rd_ready        (u_host_if.rd_ready),

    // DDR3 Physical Interface Wires
    .ddr3_ck_p       (ddr3_ck_p),
    .ddr3_ck_n       (ddr3_ck_n),
    .ddr3_rst_n      (ddr3_rst_n),
    .ddr3_cke        (ddr3_cke),
    .ddr3_cs_n       (ddr3_cs_n),
    .ddr3_ras_n      (ddr3_ras_n),
    .ddr3_cas_n      (ddr3_cas_n),
    .ddr3_we_n       (ddr3_we_n),
    .ddr3_odt        (ddr3_odt),
    .ddr3_ba         (ddr3_ba),
    .ddr3_addr       (ddr3_addr),
    .ddr3_dm         (ddr3_dm),
    .ddr3_dqs_p      (ddr3_dqs_p),
    .ddr3_dqs_n      (ddr3_dqs_n),
    .ddr3_dq         (ddr3_dq),

    // Initialization Control & Status
    .init_do         (u_cnfg_if.init_do),
    .init_done       (u_cnfg_if.init_done),
    .idle            (idle)
  );

  // -------------------------------------------------------------------------
  // DDR3 Memory Model / Chip Array Instantiation
  // -------------------------------------------------------------------------
  adn_memss_ddr3_chip_array #(
    .DATA_WIDTH      (DATA_WIDTH),
    .DRAM_ADDR_BITS  (DRAM_ADDR_BITS),
    .DRAM_BA_BITS    (DRAM_BA_BITS)
  ) u_chip_array (
    .ddr3_ck_p       (ddr3_ck_p),
    .ddr3_ck_n       (ddr3_ck_n),
    .ddr3_rst_n      (ddr3_rst_n),
    .ddr3_cke        (ddr3_cke),
    .ddr3_cs_n       (ddr3_cs_n),
    .ddr3_ras_n      (ddr3_ras_n),
    .ddr3_cas_n      (ddr3_cas_n),
    .ddr3_we_n       (ddr3_we_n),
    .ddr3_odt        (ddr3_odt),
    .ddr3_ba         (ddr3_ba),
    .ddr3_addr       (ddr3_addr),
    .ddr3_dm         (ddr3_dm),
    .ddr3_dqs_p      (ddr3_dqs_p),
    .ddr3_dqs_n      (ddr3_dqs_n),
    .ddr3_dq         (ddr3_dq)
  );

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

      if (ddr3_rst_n === 1'b1) begin
        reset_released = 1;
      end
      if ((ddr3_cke === 1'b1) && !reset_released) begin
        $fatal(1, "DDR3 CKE asserted before DDR3 reset was released");
      end

      command = {ddr3_cs_n, ddr3_ras_n, ddr3_cas_n, ddr3_we_n};
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
              0: if ((ddr3_ba !== 3'd2) || (ddr3_addr !== expected_mr2))
                   $fatal(1, "Expected MR2 value 0x%0h; got BA=%0d ADDR=0x%0h",
                          expected_mr2, ddr3_ba, ddr3_addr);
              1: if ((ddr3_ba !== 3'd3) || (ddr3_addr !== expected_mr3))
                   $fatal(1, "Expected MR3 value 0x%0h; got BA=%0d ADDR=0x%0h",
                          expected_mr3, ddr3_ba, ddr3_addr);
              2: if ((ddr3_ba !== 3'd1) || (ddr3_addr !== expected_mr1))
                   $fatal(1, "Expected MR1 value 0x%0h; got BA=%0d ADDR=0x%0h",
                          expected_mr1, ddr3_ba, ddr3_addr);
              3: if ((ddr3_ba !== 3'd0) || (ddr3_addr !== expected_mr0))
                   $fatal(1, "Expected MR0 value 0x%0h; got BA=%0d ADDR=0x%0h",
                          expected_mr0, ddr3_ba, ddr3_addr);
              default: $fatal(1, "Unexpected extra MRS command");
            endcase
            mrs_count++;
          end

          4'b0110: begin
            if ((mrs_count != 4) || (zqcl_count != 0) || (ddr3_addr[10] !== 1'b1)) begin
              $fatal(1, "Unexpected ZQCL command: MR count=%0d ZQCL count=%0d ADDR=0x%0h",
                     mrs_count, zqcl_count, ddr3_addr);
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
    if (!reset_released || (ddr3_cke !== 1'b1)) begin
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
    if ((u_cnfg_if.init_done !== 1'b1) || (idle !== 1'b1) ||
        (u_host_if.wa_ready !== 1'b1) || (u_host_if.wd_ready !== 1'b1) ||
        (u_host_if.ra_ready !== 1'b1)) begin
      $fatal(1, "%s: controller did not become idle and host-ready", case_name);
    end

    repeat (2_000) begin
      @(negedge u_ctrl_if.clk);
      if ((u_cnfg_if.init_done !== 1'b1) || (idle !== 1'b1) ||
          (u_host_if.wa_valid !== 1'b0) || (u_host_if.wd_valid !== 1'b0) ||
          (u_host_if.ra_valid !== 1'b0)) begin
        $fatal(1, "%s: controller left the idle initialization state", case_name);
      end
    end

    $display("PASS: %s", case_name);
  endtask

  // -------------------------------------------------------------------------
  // Testcase 2.2: DDR3 Initialization
  // -------------------------------------------------------------------------
  initial begin
    $timeformat(-9, 0, "ns");
    $dumpfile("ddr3_controller_uvm_tb.vcd");
    $dumpvars(0, ddr3_controller_uvm_tb);
    uvm_config_db #(virtual ctrl_if)::set(null, "*", "ctrl_vif", u_ctrl_if);
    
    uvm_config_db #(virtual cnfg_if #(.DRAM_ADDR_BITS(DRAM_ADDR_BITS)))::set(null, "*", "cnfg_vif", u_cnfg_if);
    
    uvm_config_db #(virtual host_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH),
      .BE_WIDTH   (DATA_WIDTH / 8),
      .BURST_LEN  (BURST_LEN)
    ))::set(null, "*", "host_vif", u_host_if);
    // 4. Run UVM Test
    run_test("single_wr_rd_test");
    #1000us;
    $finish;
  end

endmodule
