`include "uvm_macros.svh"
import uvm_pkg::*;
import ddr3_params_pkg::*;
`include "test/single_wr_rd_test.sv"
`include "test/byte_enable_masking_test.sv"


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

  // -------------------------------------------------------------------------
  // Simulation Initial Block (Clocks, Reset & Config Execution)
  // -------------------------------------------------------------------------
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
    // 4. Run UVM Test
    run_test(test_name);
  end
endmodule
