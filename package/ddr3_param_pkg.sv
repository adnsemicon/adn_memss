package ddr3_params_pkg;

  parameter int ADDR_WIDTH        = 30;
  parameter int DATA_WIDTH        = 64;
  parameter int BE_WIDTH          = DATA_WIDTH / 8;       // 8 bytes
  parameter int BURST_LEN         = 8;                    // Fixed 8 beats
  parameter int ACCESS_SIZE_BYTES = DATA_WIDTH;           // Block size in bytes
  parameter int ALIGN_SHIFT       = $clog2(DATA_WIDTH);   // Alignment shift bits
  parameter int DRAM_CHIP_WIDTH   = 16;                   // x16 DDR3 chips
  parameter int NUM_CHIPS         = DATA_WIDTH / DRAM_CHIP_WIDTH; // 4 chips for 64-bit
  parameter int DQS_WIDTH         = DATA_WIDTH / 8;       // 1 DQS pair per byte lane
  parameter int DM_WIDTH          = DATA_WIDTH / 8;       // 1 DM bit per byte lane
  parameter int DRAM_ADDR_BITS    = 16;                   // A[15:0]
  parameter int DRAM_BA_BITS      = 3;                    // BA[2:0] (8 banks)
  parameter int DRAM_ROW_BITS     = 16;                   // Row address width
  parameter int DRAM_COL_BITS     = 10;                   // Column width (10 for x16)
  parameter bit SIM_SPEED_UP      = 1'b1;                 // Fast power-up for simulation

endpackage
