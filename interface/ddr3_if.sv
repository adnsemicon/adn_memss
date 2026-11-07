`ifndef __GUARD_DDR3_IF_SV__
`define __GUARD_DDR3_IF_SV__ 0

interface ddr3_if #(
  parameter int DRAM_BA_BITS   = 3,
  parameter int DRAM_ADDR_BITS = 14,
  parameter int DM_WIDTH       = 8,
  parameter int DQS_WIDTH      = 8,
  parameter int DATA_WIDTH     = 64
);
  logic                      ck_p;
  logic                      ck_n;
  logic                      rst_n;
  logic                      cke;
  logic                      cs_n;
  logic                      ras_n;
  logic                      cas_n;
  logic                      we_n;
  logic                      odt;
  logic [DRAM_BA_BITS-1:0]   ba;
  logic [DRAM_ADDR_BITS-1:0] addr;
  wire  [DM_WIDTH-1:0]       dm;
  wire  [DQS_WIDTH-1:0]      dqs_p;
  wire  [DQS_WIDTH-1:0]      dqs_n;
  wire  [DATA_WIDTH-1:0]     dq;

  string current_fsm_state;
endinterface

`endif