`include "uvm_macros.svh"
import uvm_pkg::*;
import ddr3_params_pkg::*;
import micron_ddr3_msg_pkg::msg_t;

`include "test/single_wr_rd_test.sv"
`include "test/byte_enable_masking_test.sv"
`include "test/back_to_back_burst_test.sv"
`include "test/read_back_pressure_test.sv"
//`include "test/write_back_pressure_test.sv"
`include "test/random_stress_test.sv"
`include "test/refresh_collision_test.sv"
`include "test/check_initialization.sv"
`include "test/on_the_fly_reconfig_test.sv"
`include "test/reinitialization_test.sv"
`include "test/reset_test.sv"


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

  ddr3_if #(
    .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
    .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
    .DM_WIDTH       (DM_WIDTH      ),  
    .DQS_WIDTH      (DQS_WIDTH     ),  
    .DATA_WIDTH     (DATA_WIDTH    )     
  ) u_ddr3_if();

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
    .ddr3_ck_p       (u_ddr3_if.ck_p  ),
    .ddr3_ck_n       (u_ddr3_if.ck_n  ),
    .ddr3_rst_n      (u_ddr3_if.rst_n ),
    .ddr3_cke        (u_ddr3_if.cke   ),
    .ddr3_cs_n       (u_ddr3_if.cs_n  ),
    .ddr3_ras_n      (u_ddr3_if.ras_n ),
    .ddr3_cas_n      (u_ddr3_if.cas_n ),
    .ddr3_we_n       (u_ddr3_if.we_n  ),
    .ddr3_odt        (u_ddr3_if.odt   ),
    .ddr3_ba         (u_ddr3_if.ba    ),
    .ddr3_addr       (u_ddr3_if.addr  ),
    .ddr3_dm         (u_ddr3_if.dm    ),
    .ddr3_dqs_p      (u_ddr3_if.dqs_p ),
    .ddr3_dqs_n      (u_ddr3_if.dqs_n ),
    .ddr3_dq         (u_ddr3_if.dq    ),

    // Initialization Control & Status
    .init_do         (u_cnfg_if.init_do),
    .init_done       (u_cnfg_if.init_done),
    .idle            ()
  );

  // -------------------------------------------------------------------------
  // DDR3 Memory Model / Chip Array Instantiation
  // -------------------------------------------------------------------------
  adn_memss_ddr3_chip_array #(
    .DATA_WIDTH      (DATA_WIDTH),
    .DRAM_ADDR_BITS  (DRAM_ADDR_BITS),
    .DRAM_BA_BITS    (DRAM_BA_BITS)
  ) u_chip_array (
    .ddr3_ck_p       (u_ddr3_if.ck_p  ),
    .ddr3_ck_n       (u_ddr3_if.ck_n  ),
    .ddr3_rst_n      (u_ddr3_if.rst_n ),
    .ddr3_cke        (u_ddr3_if.cke   ),
    .ddr3_cs_n       (u_ddr3_if.cs_n  ),
    .ddr3_ras_n      (u_ddr3_if.ras_n ),
    .ddr3_cas_n      (u_ddr3_if.cas_n ),
    .ddr3_we_n       (u_ddr3_if.we_n  ),
    .ddr3_odt        (u_ddr3_if.odt   ),
    .ddr3_ba         (u_ddr3_if.ba    ),
    .ddr3_addr       (u_ddr3_if.addr  ),
    .ddr3_dm         (u_ddr3_if.dm    ),
    .ddr3_dqs_p      (u_ddr3_if.dqs_p ),
    .ddr3_dqs_n      (u_ddr3_if.dqs_n ),
    .ddr3_dq         (u_ddr3_if.dq    )
  );

  always_comb begin
    if (u_ctrl_if.arst_n === 1'b0) begin
      u_ddr3_if.current_fsm_state = "RESET";
    end else begin
      case (u_dut.state)
        u_dut.ST_RESET_LOW         : u_ddr3_if.current_fsm_state = "RESET_LOW";
        u_dut.ST_RESET_HIGH        : u_ddr3_if.current_fsm_state = "RESET_HIGH";
        u_dut.ST_CKE_HIGH          : u_ddr3_if.current_fsm_state = "CKE_HIGH";
        u_dut.ST_LOAD_MR2          : u_ddr3_if.current_fsm_state = "LOAD_MR2";
        u_dut.ST_LOAD_MR3          : u_ddr3_if.current_fsm_state = "LOAD_MR3";
        u_dut.ST_LOAD_MR1          : u_ddr3_if.current_fsm_state = "LOAD_MR1";
        u_dut.ST_LOAD_MR0          : u_ddr3_if.current_fsm_state = "LOAD_MR0";
        u_dut.ST_ZQCL              : u_ddr3_if.current_fsm_state = "ZQCL";
        u_dut.ST_DLL_WAIT          : u_ddr3_if.current_fsm_state = "DLL_WAIT";
        u_dut.ST_IDLE              : u_ddr3_if.current_fsm_state = "IDLE";
        u_dut.ST_REFRESH           : u_ddr3_if.current_fsm_state = "REFRESH";
        u_dut.ST_WR_ACT            : u_ddr3_if.current_fsm_state = "WR_ACT";
        u_dut.ST_WR_ACT_WAIT       : u_ddr3_if.current_fsm_state = "WR_ACT_WAIT";
        u_dut.ST_WR_CMD            : u_ddr3_if.current_fsm_state = "WR_CMD";
        u_dut.ST_WR_PRECHARGE_WAIT : u_ddr3_if.current_fsm_state = "WR_PRE_WAIT";
        u_dut.ST_RD_ACT            : u_ddr3_if.current_fsm_state = "RD_ACT";
        u_dut.ST_RD_ACT_WAIT       : u_ddr3_if.current_fsm_state = "RD_ACT_WAIT";
        u_dut.ST_RD_CMD            : u_ddr3_if.current_fsm_state = "RD_CMD";
        u_dut.ST_RD_PRECHARGE_WAIT : u_ddr3_if.current_fsm_state = "RD_PRE_WAIT";
        default                    : u_ddr3_if.current_fsm_state = "UNKNOWN";
      endcase
    end
  end

  initial begin
    string test_name;

    if (!$value$plusargs("TN=%s", test_name)) begin
      test_name = "base_test"; 
    end

    // 1. Store Virtual Interfaces into UVM Config DB
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
    
    uvm_config_db #(virtual ddr3_if #(
      .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
      .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
      .DM_WIDTH       (DM_WIDTH      ),  
      .DQS_WIDTH      (DQS_WIDTH     ),  
      .DATA_WIDTH     (DATA_WIDTH    )    
    ))::set(null, "*", "ddr3_vif", u_ddr3_if);

    // 2. Pass Micron DDR3 Model Mailboxes to Scoreboard after u_chip_array initializes them at time 0
    fork
      begin
        #1step;
        uvm_config_db #(mailbox #(msg_t))::set(null, "*", "dram_info_mbx",    u_chip_array.info_mbx);
        uvm_config_db #(mailbox #(msg_t))::set(null, "*", "dram_warning_mbx", u_chip_array.warning_mbx);
        uvm_config_db #(mailbox #(msg_t))::set(null, "*", "dram_error_mbx",   u_chip_array.error_mbx);
      end
    join_none

    // 3. Run UVM Test (Must be called at time 0ns)
    run_test(test_name);
  end
endmodule
