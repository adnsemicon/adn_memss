/*

The `ddr3_chip_array` module `ddr3_chip_array.sv` provides a parameterized structural wrapper that instantiates a parallel array of discrete DDR3 SDRAM components (using Micron's verified `ddr3.v` simulation model).

| REVISION | DATE       | AUTHOR          | DESCRIPTION                                            |
|----------|------------|-----------------|--------------------------------------------------------|
| 0.1      | 2026-11-01 | Foez Ahmed      | Initial version                                        |
| 1.0      | 2026-11-01 | Foez Ahmed      | Stable release                                         |

Author : Foez Ahmed (foez.official@gmail.com)
This file is part of adnsemicon/adn_memss
Copyright (c) 2026 ADN Semiconductors
Licensed under the MIT License
See LICENSE file in the project root for full license information

*/

module adn_memss_ddr3_chip_array #(
    parameter  int DATA_WIDTH      = 64,
    parameter  int DRAM_CHIP_WIDTH = 16,                            // 16 for x16, 8 for x8
    parameter  int DRAM_ADDR_BITS  = 16,
    parameter  int DRAM_BA_BITS    = 3,
    localparam int NUM_CHIPS       = DATA_WIDTH / DRAM_CHIP_WIDTH,
    localparam int DQS_WIDTH       = DATA_WIDTH / 8,
    localparam int DM_WIDTH        = DATA_WIDTH / 8,
    localparam int DQS_PER_CHIP    = DRAM_CHIP_WIDTH / 8,
    localparam int DM_PER_CHIP     = DRAM_CHIP_WIDTH / 8
) (
    input logic                      ddr3_ck_p,
    input logic                      ddr3_ck_n,
    input logic                      ddr3_rst_n,
    input logic                      ddr3_cke,
    input logic                      ddr3_cs_n,
    input logic                      ddr3_ras_n,
    input logic                      ddr3_cas_n,
    input logic                      ddr3_we_n,
    input logic                      ddr3_odt,
    input logic [  DRAM_BA_BITS-1:0] ddr3_ba,
    input logic [DRAM_ADDR_BITS-1:0] ddr3_addr,
    inout wire  [      DM_WIDTH-1:0] ddr3_dm,
    inout wire  [     DQS_WIDTH-1:0] ddr3_dqs_p,
    inout wire  [     DQS_WIDTH-1:0] ddr3_dqs_n,
    inout wire  [    DATA_WIDTH-1:0] ddr3_dq
);

  `include "micron_ddr3_msg.sv"

  `DDR3_MSG_MBX_DECLARE

  `DDR3_MSG_MBX_INI_NEW

  genvar i;
  generate
    for (i = 0; i < NUM_CHIPS; i = i + 1) begin : gen_ddr3_chips
      ddr3 #(
          .check_strict_timing(0),
          .PERTCKAVG          (12),
          .DEBUG              (0)
      ) u_ddr3_chip (
          .rst_n  (ddr3_rst_n),
          .ck     (ddr3_ck_p),
          .ck_n   (ddr3_ck_n),
          .cke    (ddr3_cke),
          .cs_n   (ddr3_cs_n),
          .ras_n  (ddr3_ras_n),
          .cas_n  (ddr3_cas_n),
          .we_n   (ddr3_we_n),
          .dm_tdqs(ddr3_dm[DM_PER_CHIP*i+:DM_PER_CHIP]),
          .ba     (ddr3_ba),
          .addr   (ddr3_addr),
          .dq     (ddr3_dq[DRAM_CHIP_WIDTH*i+:DRAM_CHIP_WIDTH]),
          .dqs    (ddr3_dqs_p[DQS_PER_CHIP*i+:DQS_PER_CHIP]),
          .dqs_n  (ddr3_dqs_n[DQS_PER_CHIP*i+:DQS_PER_CHIP]),
          .tdqs_n (),
          .odt    (ddr3_odt)
      );

      initial begin
        #1step;
        `DDR3_MSG_MBX_CONNECT(u_ddr3_chip)
      end

    end
  endgenerate

endmodule
