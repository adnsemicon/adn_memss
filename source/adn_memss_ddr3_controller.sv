/*

# adn_memss_ddr3_controller

Fully Functional Fixed-Burst (mem_if) DDR3 SDRAM Controller

## Key Features:
- **Decoupled Fixed-Burst Host Interface (`mem_if`)**: Operates on a fixed transaction granularity of 8 beats ($BL = 8$) over independent Write Address, Write Data, Read Address, and Read Data channels with full Ready/Valid backpressure flow control.
- **Closed-Page Policy with Autonomous Precharge**: Employs a closed-page memory management strategy with hardware Auto-Precharge ($A[10] = 1$). Every activate command is immediately followed by a read or write with auto-precharge, eliminating bank conflict stalls and complex row tracking logic.
- **Idle Clock Throttling & Internal 2:1 Clock Generation**: Accepts a system clock (`clk`, $F_{sys} = 2 \times F_{ddr}$) that can dynamically throttle or slow down during idle periods, and synthesizes differential DDR3 clocks (`ddr3_ck_p` / `ddr3_ck_n`) internally at `clk / 2`. Registering on alternating clock edges guarantees 1 full system clock cycle ($T_{sys} = 0.5\,t_{CK}$) of command setup time prior to the DRAM latching edge across any clock frequency.
- **Real-Time Clock (`rtc`) Timing Engine**: Uses an independent Real-Time Clock (`rtc`) input—ranging from slow $1\text{ MHz}$, $8\text{ MHz}$, $16\text{ MHz}$, $32\text{ MHz}$ up to $100\text{ MHz}$ max—to measure all wall-clock JEDEC timing intervals ($t_{RCD}$, $t_{RP}$, $t_{RAS}$, $t_{RC}$, $t_{WR}$, $t_{RTP}$, $t_{WTR}$, $t_{RRD}$, $t_{FAW}$, $t_{RFC}$, $t_{REFI}$, and power-up reset delays) invariants of `clk` throttling.
- **Runtime Register File Configuration & Mode Register Decoding**: All Mode Registers (`mr0`–`mr3`) and JEDEC timing parameters (in RTC ticks) are provided as runtime input ports from an external register file. The controller combinationally decodes `CL`, `CWL`, `AL`, `WR` ($t_{CK}$), `RL`, and `WL` directly from `mr0`, `mr1`, and `mr2`.
- **Standard JEDEC Power-Up and Mode Register Synthesis**: Executes the complete JEDEC DDR3 initialization protocol upon reset release: stable power-up delay ($200\,\mu\text{s}$), active-low reset exit ($500\,\mu\text{s}$), CKE assertion ($t_{XPR}$), mode register initialization ($MR2 \rightarrow MR3 \rightarrow MR1 \rightarrow MR0$ with DLL reset), ZQ Calibration Long ($ZQCL$), and DLL lock wait.
- **Autonomous Periodic Auto-Refresh Engine**: Built-in RTC-driven $t_{REFI}$ timer with up to 8 accumulated refresh credits. Automatically arbitrates and issues highest-priority `CMD_REFRESH` ($t_{RFC}$) bursts without host intervention, preventing DRAM data retention failure even when `clk` is throttled during idle.
- **Synthesizable Write PHY with Center-Aligned Strobe Synthesis**: Generates clean differential DQS write strobes with JEDEC-compliant preamble and postamble. DQ and DM are launched on the negative edge of `clk`, providing an exact $90^\circ$ phase lead ($325\text{ ps}$ at $1.54\text{ GHz}$) that centers write data eyes precisely on the DQS transitions without expensive analog delay-locked loops (DLLs).
- **Asynchronous Read Capture PHY & Dual-Edge Gearbox**: Features a dual-edge DQS-strobed capture memory with simulated analog eye centering (`#250ps`), preamble falling-edge glitch suppression, and a synchronous gearbox that transfers captured 8-beat bursts into the read FIFO across the system clock domain.

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


module adn_memss_ddr3_controller #(
    parameter  int ADDR_WIDTH        = 30,                 // Byte address width
    parameter  int DATA_WIDTH        = 64,                 // Datapath width in bits
    localparam int BE_WIDTH          = DATA_WIDTH / 8,     // Byte-enable / strobe width
    localparam int BURST_LEN         = 8,                  // Fixed 8 beats per mem_if transaction
    localparam int ACCESS_SIZE_BYTES = DATA_WIDTH,         // Block size in bytes = DATA_WIDTH
    localparam int ALIGN_SHIFT       = $clog2(DATA_WIDTH), // LSBs forced to 0 for alignment

    parameter int DRAM_CHIP_WIDTH = 16,  // DQ bits per chip: 16 (for x16) or 8 (for x8)
    localparam int NUM_CHIPS = DATA_WIDTH / DRAM_CHIP_WIDTH,  // Number of parallel chips (2^n)
    localparam int DQS_WIDTH = DATA_WIDTH / 8,  // 1 differential DQS pair per byte lane
    localparam int DM_WIDTH = DATA_WIDTH / 8,  // 1 Data Mask bit per byte lane

    parameter int DRAM_ADDR_BITS = 16,  // DDR3 A[15:0] pin width
    parameter int DRAM_BA_BITS   = 3,   // DDR3 BA[2:0] pin width (8 banks)
    parameter int DRAM_ROW_BITS  = 16,  // Row address width
    parameter int DRAM_COL_BITS  = 10,  // Column address width (10 for x16, 11 for x8)

    parameter bit SIM_SPEED_UP = 1'b1  // Accelerates power-up delays for simulation
) (

    // System Clock, Real-Time Clock (RTC) & Reset
    input logic clk,    // System Clock (F_sys = 2 * F_ddr; may throttle during idle)
    input logic rtc,    // Real-Time Clock for timing (1 MHz to 100 MHz max)
    input logic arst_n, // Asynchronous active-low reset

    // DDR3 Mode Registers
    input logic [DRAM_ADDR_BITS-1:0] mr0,  // Mode Register 0 (MRS: BL, CL, DLL Reset, WR, PPD)
    input logic [DRAM_ADDR_BITS-1:0] mr1,  // Mode Register 1 (EMR1: DLL En, DIC, RTT_nom, AL)
    input logic [DRAM_ADDR_BITS-1:0] mr2,  // Mode Register 2 (EMR2: PASR, CWL, ASR, SRT, RTT_wr)
    input logic [DRAM_ADDR_BITS-1:0] mr3,  // Mode Register 3 (EMR3: MPR)

    // Core DRAM Timings (Measured in RTC ticks)
    input logic [15:0] tRCD,  // ACT to READ/WRITE delay (in RTC ticks)
    input logic [15:0] tRP,   // PRECHARGE command period (in RTC ticks)
    input logic [15:0] tRAS,  // ACT to PRECHARGE delay (in RTC ticks)
    input logic [15:0] tRC,   // ACT to ACT / REF period (in RTC ticks)
    input logic [15:0] tWR,   // Write recovery time (in RTC ticks)
    input logic [15:0] tRTP,  // READ to PRECHARGE delay (in RTC ticks)
    input logic [15:0] tWTR,  // Write to Read delay (in RTC ticks)
    input logic [15:0] tRRD,  // ACT bank A to ACT bank B delay (in RTC ticks)
    input logic [15:0] tFAW,  // Four-bank activate window (in RTC ticks)
    input logic [15:0] tRFC,  // AUTO REFRESH command period (in RTC ticks)
    input logic [15:0] tREFI, // Periodic refresh interval (~7.8 us in RTC ticks)

    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0] wa_addr,   // Write address
    input  logic                  wa_valid,  // Write address valid signal
    output logic                  wa_ready,  // Write address ready signal

    // Write Data Channel (Fixed 8 beats per accepted address)
    input  logic [DATA_WIDTH-1:0] wd_data,   // Write data
    input  logic [  BE_WIDTH-1:0] wd_be,     // Write byte enable
    input  logic                  wd_valid,  // Write data valid signal
    output logic                  wd_ready,  // Write data ready signal

    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0] ra_addr,   // Read address
    input  logic                  ra_valid,  // Read address valid signal
    output logic                  ra_ready,  // Read address ready signal

    // Read Data Channel (Fixed 8 beats per accepted address)
    output logic [DATA_WIDTH-1:0] rd_data,   // Read data
    output logic                  rd_valid,  // Read data valid signal
    input  logic                  rd_ready,  // Read data ready signal

    // DDR3 Physical Interface (Operating at F_ddr = F_sys / 2, follows `clk`)
    output logic ddr3_ck_p,   // DDR3 differential clock +
    output logic ddr3_ck_n,   // DDR3 differential clock -
    output logic ddr3_rst_n,  // DDR3 active-low reset
    output logic ddr3_cke,    // DDR3 clock enable
    output logic ddr3_cs_n,   // DDR3 chip select
    output logic ddr3_ras_n,  // DDR3 row address strobe
    output logic ddr3_cas_n,  // DDR3 column address strobe
    output logic ddr3_we_n,   // DDR3 write enable
    output logic ddr3_odt,    // DDR3 on-die termination
    output logic [  DRAM_BA_BITS-1:0] ddr3_ba,   // DDR3 bank address
    output logic [DRAM_ADDR_BITS-1:0] ddr3_addr, // DDR3 address bus
    inout  wire  [  DM_WIDTH-1:0] ddr3_dm,     // DDR3 data mask (active high)
    inout  wire  [ DQS_WIDTH-1:0] ddr3_dqs_p,  // DDR3 data strobe +
    inout  wire  [ DQS_WIDTH-1:0] ddr3_dqs_n,  // DDR3 data strobe -
    inout  wire  [DATA_WIDTH-1:0] ddr3_dq,     // DDR3 bidirectional data bus

    // Initialization Control & Status
    input logic init_do,  // Request (re-)initialization; held high until init_done goes low
    output logic init_done,  // High when initialization complete
    output logic idle  // High when controller is initialized, all FIFOs empty, and FSM/PHY idle
);

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // DDR3 Command Encodings {cs_n, ras_n, cas_n, we_n}
  //////////////////////////////////////////////////////////////////////////////////////////////////

  localparam logic [3:0] CMD_MRS       = 4'b0000;
  localparam logic [3:0] CMD_REFRESH   = 4'b0001;
  localparam logic [3:0] CMD_PRECHARGE = 4'b0010;
  localparam logic [3:0] CMD_ACTIVATE  = 4'b0011;
  localparam logic [3:0] CMD_WRITE     = 4'b0100;
  localparam logic [3:0] CMD_READ      = 4'b0101;
  localparam logic [3:0] CMD_ZQCL      = 4'b0110;
  localparam logic [3:0] CMD_NOP       = 4'b0111;
  localparam logic [3:0] CMD_DESELECT  = 4'b1111;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Clock Generation: Internal 2:1 Clock Divider & Phase Tracking
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // phase: toggles every clk. When clk throttles during idle, phase and
  // ddr3_ck_p / ddr3_ck_n automatically track clk at half frequency.
  // phase == 0: ck_p is 0 (low half of tCK)
  // phase == 1: ck_p is 1 (high half of tCK)
  logic phase;
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      phase <= 1'b0;
    end else begin
      phase <= ~phase;
    end
  end

  // Register CK on the opposite system-clock edge to keep its transitions
  // half a system-clock period away from the write DQS transitions.
  always_ff @(negedge clk or negedge arst_n) begin
    if (!arst_n) begin
      ddr3_ck_p <= 1'b0;
      ddr3_ck_n <= 1'b1;
    end else begin
      ddr3_ck_p <= phase;
      ddr3_ck_n <= ~phase;
    end
  end

  // A tick pulse that fires once per DDR clock cycle (at falling edge of ck_p)
  // All DDR command/address outputs update here to guarantee 1 full clk cycle
  // of setup time prior to the rising edge of ck_p!
  wire tck_tick = (phase == 1'b1);

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Real-Time Clock (RTC) Tick Engine & Refresh Timer
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Free-running RTC tick counter operating directly in the `rtc` clock domain.
  // Never misses RTC edges even if `clk` is throttled or gated during idle.
  logic [31:0] rtc_tick_cnt;
  always_ff @(posedge rtc or negedge arst_n) begin
    if (!arst_n) begin
      rtc_tick_cnt <= 32'd0;
    end else begin
      rtc_tick_cnt <= rtc_tick_cnt + 32'd1;
    end
  end

  // Helper function: returns 1 when at least `req_ticks` full RTC periods
  // (req_ticks * T_RTC) have elapsed since `start_cnt` was snapshotted.
  // Because `start_cnt` is captured in the `clk` domain asynchronously to
  // `posedge rtc`, the 1st RTC edge completes a partial period (0..T_RTC).
  // Waiting for (rtc_tick_cnt - start_cnt) > req_ticks guarantees >= req_ticks * T_RTC.
  function automatic logic rtc_done(input logic [31:0] curr_cnt, input logic [31:0] start_cnt,
                                    input logic [15:0] req_ticks);
    if (req_ticks == 16'd0) begin
      return 1'b1;
    end else begin
      return ((curr_cnt - start_cnt) > {16'd0, req_ticks});
    end
  endfunction

  // Periodic Auto-Refresh Timer running in the `rtc` domain
  logic [DRAM_ADDR_BITS-1:0] active_mr0, active_mr1, active_mr2, active_mr3;
  logic [15:0] active_tRCD, active_tRP, active_tRAS, active_tRC, active_tWR;
  logic [15:0] active_tRTP, active_tWTR, active_tRRD, active_tFAW, active_tRFC, active_tREFI;

  wire  [15:0] eff_tREFI = init_done ? active_tREFI : tREFI;

  logic [15:0] ref_rtc_timer;
  logic [31:0] ref_req_cnt;
  logic [31:0] ref_ack_cnt;

  always_ff @(posedge rtc or negedge arst_n) begin
    if (!arst_n) begin
      ref_rtc_timer <= 16'd0;
      ref_req_cnt   <= 32'd0;
    end else if (!init_done) begin
      ref_rtc_timer <= 16'd0;
    end else begin
      if (eff_tREFI <= 16'd1 || ref_rtc_timer >= (eff_tREFI - 16'd1)) begin
        ref_rtc_timer <= 16'd0;
        ref_req_cnt   <= ref_req_cnt + 32'd1;
      end else begin
        ref_rtc_timer <= ref_rtc_timer + 16'd1;
      end
    end
  end

  wire [31:0] pending_ref = ref_req_cnt - ref_ack_cnt;
  wire [ 3:0] ref_credit = (pending_ref > 32'd8) ? 4'd8 : pending_ref[3:0];

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // mem_if Frontend Buffers (FIFOs)
  //////////////////////////////////////////////////////////////////////////////////////////////////

  localparam int ADDR_FIFO_DEPTH = 4;
  localparam int DATA_FIFO_DEPTH = 32;  // Holds up to 4 x 8-beat bursts

  // Write Address FIFO
  logic [ADDR_WIDTH-1:0] wa_fifo_raddr;
  logic wa_fifo_full, wa_fifo_empty, wa_fifo_afull;
  logic                             wa_fifo_rinc;
  logic [$clog2(ADDR_FIFO_DEPTH):0] wa_fifo_count;

  ddr3_fifo_for_ddr3_controller #(
      .WIDTH(ADDR_WIDTH),
      .DEPTH(ADDR_FIFO_DEPTH)
  ) u_wa_fifo (
      .clk        (clk),
      .arst_n     (arst_n),
      .winc       (wa_valid && wa_ready),
      .wdata      (wa_addr),
      .full       (wa_fifo_full),
      .almost_full(wa_fifo_afull),
      .count      (wa_fifo_count),
      .rinc       (wa_fifo_rinc),
      .rdata      (wa_fifo_raddr),
      .empty      (wa_fifo_empty)
  );

  // Write Data FIFO (stores both data and byte-enables)
  localparam int WD_PAYLOAD_W = DATA_WIDTH + BE_WIDTH;
  logic [WD_PAYLOAD_W-1:0] wd_fifo_rpayload;
  logic wd_fifo_full, wd_fifo_empty, wd_fifo_afull;
  logic                             wd_fifo_rinc;
  logic [$clog2(DATA_FIFO_DEPTH):0] wd_fifo_count;

  ddr3_fifo_for_ddr3_controller #(
      .WIDTH(WD_PAYLOAD_W),
      .DEPTH(DATA_FIFO_DEPTH)
  ) u_wd_fifo (
      .clk        (clk),
      .arst_n     (arst_n),
      .winc       (wd_valid && wd_ready),
      .wdata      ({wd_be, wd_data}),
      .full       (wd_fifo_full),
      .almost_full(wd_fifo_afull),
      .count      (wd_fifo_count),
      .rinc       (wd_fifo_rinc),
      .rdata      (wd_fifo_rpayload),
      .empty      (wd_fifo_empty)
  );

  wire [DATA_WIDTH-1:0] wd_fifo_rdata = wd_fifo_rpayload[DATA_WIDTH-1:0];
  wire [BE_WIDTH-1:0] wd_fifo_rbe = wd_fifo_rpayload[WD_PAYLOAD_W-1:DATA_WIDTH];

  // Flow control: accept write address when initialized, FIFO has room for at least 1 address,
  // and write data FIFO has room for at least 8 beats.
  logic init_req_pending;
  assign wa_ready = init_done && !init_do && !init_req_pending && !wa_fifo_full && (wd_fifo_count <= (DATA_FIFO_DEPTH - 8));
  assign wd_ready = init_done && !wd_fifo_full;

  // Read Address FIFO
  logic [ADDR_WIDTH-1:0] ra_fifo_raddr;
  logic ra_fifo_full, ra_fifo_empty, ra_fifo_afull;
  logic                             ra_fifo_rinc;
  logic [$clog2(ADDR_FIFO_DEPTH):0] ra_fifo_count;

  ddr3_fifo_for_ddr3_controller #(
      .WIDTH(ADDR_WIDTH),
      .DEPTH(ADDR_FIFO_DEPTH)
  ) u_ra_fifo (
      .clk        (clk),
      .arst_n     (arst_n),
      .winc       (ra_valid && ra_ready),
      .wdata      (ra_addr),
      .full       (ra_fifo_full),
      .almost_full(ra_fifo_afull),
      .count      (ra_fifo_count),
      .rinc       (ra_fifo_rinc),
      .rdata      (ra_fifo_raddr),
      .empty      (ra_fifo_empty)
  );

  // Read Data FIFO
  logic [DATA_WIDTH-1:0] rd_fifo_wdata;
  logic                  rd_fifo_winc;
  logic rd_fifo_full, rd_fifo_empty, rd_fifo_afull;
  logic [$clog2(DATA_FIFO_DEPTH):0] rd_fifo_count;

  ddr3_fifo_for_ddr3_controller #(
      .NAME ("RD_FIFO"),
      .WIDTH(DATA_WIDTH),
      .DEPTH(DATA_FIFO_DEPTH)
  ) u_rd_fifo (
      .clk        (clk),
      .arst_n     (arst_n),
      .winc       (rd_fifo_winc),
      .wdata      (rd_fifo_wdata),
      .full       (rd_fifo_full),
      .almost_full(rd_fifo_afull),
      .count      (rd_fifo_count),
      .rinc       (rd_valid && rd_ready),
      .rdata      (rd_data),
      .empty      (rd_fifo_empty)
  );

  assign rd_valid = !rd_fifo_empty;
  // Accept read address when initialized, RA FIFO has space, and RD FIFO can hold 8 returned beats
  assign ra_ready = init_done && !init_do && !init_req_pending && !ra_fifo_full && (rd_fifo_count <= (DATA_FIFO_DEPTH - 8));

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Address Mapping Function
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Maps a linear block-aligned byte address into {row, bank, col}
  localparam int COL_BURST_BITS = DRAM_COL_BITS - 3;  // LSB 3 bits are 0 for BL8

  function automatic void decode_address(
      input logic [ADDR_WIDTH-1:0] in_addr, output logic [DRAM_BA_BITS-1:0] out_bank,
      output logic [DRAM_ROW_BITS-1:0] out_row, output logic [DRAM_COL_BITS-1:0] out_col);
    logic [ADDR_WIDTH-1:0] shifted_addr;
    shifted_addr = in_addr >> ALIGN_SHIFT;

    out_col = '0;
    out_col[DRAM_COL_BITS-1:3] = shifted_addr[COL_BURST_BITS-1:0];
    shifted_addr = shifted_addr >> COL_BURST_BITS;

    out_bank = shifted_addr[DRAM_BA_BITS-1:0];
    shifted_addr = shifted_addr >> DRAM_BA_BITS;

    out_row = shifted_addr[DRAM_ROW_BITS-1:0];
  endfunction

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Runtime DDR3 Mode Register (MR0..MR3) Latency Decoding
  //////////////////////////////////////////////////////////////////////////////////////////////////

  logic [3:0] cfg_cl;
  logic [3:0] cfg_cwl;
  logic [3:0] cfg_al;
  logic [4:0] cfg_wr_tck;
  logic       cfg_dll_en;
  logic [4:0] cfg_rl;
  logic [4:0] cfg_wl;

  always_comb begin
    // Decode CAS Latency (CL) from active_mr0[6:4] and active_mr0[2]
    cfg_cl = {active_mr0[2], active_mr0[6:4]} + 4'd4;

    // Decode Write Recovery (WR in tCK) from active_mr0[11:9]
    case (active_mr0[11:9])
      3'b000:  cfg_wr_tck = 5'd16;
      3'b001:  cfg_wr_tck = 5'd5;
      3'b010:  cfg_wr_tck = 5'd6;
      3'b011:  cfg_wr_tck = 5'd7;
      3'b100:  cfg_wr_tck = 5'd8;
      3'b101:  cfg_wr_tck = 5'd10;
      3'b110:  cfg_wr_tck = 5'd12;
      3'b111:  cfg_wr_tck = 5'd14;
      default: cfg_wr_tck = 5'd12;
    endcase

    // Decode DLL Enable and Additive Latency (AL) from active_mr1
    cfg_dll_en = ~active_mr1[0];
    case (active_mr1[4:3])
      2'b00:   cfg_al = 4'd0;
      2'b01:   cfg_al = cfg_cl - 4'd1;
      2'b10:   cfg_al = cfg_cl - 4'd2;
      default: cfg_al = 4'd0;
    endcase

    // Decode CAS Write Latency (CWL) from active_mr2[5:3]
    cfg_cwl = active_mr2[5:3] + 4'd5;

    // Derived Read and Write Latencies (in tCK)
    cfg_rl  = cfg_dll_en ? (5'(cfg_cl) + 5'(cfg_al)) : (5'(cfg_cl) + 5'(cfg_al) - 5'd1);
    cfg_wl  = 5'(cfg_cwl) + 5'(cfg_al);
  end

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Command Scheduler & FSM State Definitions
  //////////////////////////////////////////////////////////////////////////////////////////////////

  typedef enum logic [4:0] {
    ST_RESET_LOW,
    ST_RESET_HIGH,
    ST_CKE_HIGH,
    ST_LOAD_MR2,
    ST_LOAD_MR3,
    ST_LOAD_MR1,
    ST_LOAD_MR0,
    ST_ZQCL,
    ST_DLL_WAIT,
    ST_IDLE,
    ST_REFRESH,
    ST_WR_ACT,
    ST_WR_ACT_WAIT,
    ST_WR_CMD,
    ST_WR_PRECHARGE_WAIT,
    ST_RD_ACT,
    ST_RD_ACT_WAIT,
    ST_RD_CMD,
    ST_RD_PRECHARGE_WAIT
  } ctrl_state_t;

  ctrl_state_t        state;
  logic        [15:0] tck_timer;
  logic        [31:0] rtc_state_start;
  logic        [31:0] rtc_act_start;
  logic        [31:0] rtc_wr_end_start;
  logic               wr_end_valid;
  logic               pre_phase;

  // Four-Bank Activate Window (tFAW) and ACT-to-ACT (tRRD) tracking in RTC ticks
  logic        [31:0] rtc_faw_pipe     [3:0];
  logic        [ 3:0] faw_valid;
  logic               act_window_ok;
  logic               wtr_ok;

  always_comb begin
    act_window_ok = (!faw_valid[0] || rtc_done(rtc_tick_cnt, rtc_faw_pipe[0], active_tRRD)) &&
        (!faw_valid[3] || rtc_done(rtc_tick_cnt, rtc_faw_pipe[3], active_tFAW));
    wtr_ok = (!wr_end_valid || rtc_done(rtc_tick_cnt, rtc_wr_end_start, active_tWTR));
  end

  // Registers to hold current active command parameters
  logic [  DRAM_BA_BITS-1:0] curr_bank;
  logic [ DRAM_ROW_BITS-1:0] curr_row;
  logic [ DRAM_COL_BITS-1:0] curr_col;

  // Direct registered DRAM command outputs
  logic [               3:0] cmd_reg;
  logic [  DRAM_BA_BITS-1:0] ba_reg;
  logic [DRAM_ADDR_BITS-1:0] addr_reg;
  logic                      cke_reg;
  logic                      rst_n_reg;
  logic                      odt_reg;

  assign {ddr3_cs_n, ddr3_ras_n, ddr3_cas_n, ddr3_we_n} = cmd_reg;
  assign ddr3_ba    = ba_reg;
  assign ddr3_addr  = addr_reg;
  assign ddr3_cke   = cke_reg;
  assign ddr3_rst_n = rst_n_reg;
  assign ddr3_odt   = odt_reg;

  // PHY Trigger Flags & Status
  logic wr_phy_start;
  logic rd_phy_start;
  logic rd_cap_busy;
  logic rd_push_active;

  // Power-up RTC wait targets (26*tREFI ~= 202.8 us, 65*tREFI ~= 507 us)
  wire [15:0] wait_reset_low_rtc = SIM_SPEED_UP ? 16'd2 : (tREFI * 16'd26);
  wire [15:0] wait_reset_high_rtc = SIM_SPEED_UP ? 16'd2 : (tREFI * 16'd65);
  localparam logic [15:0] WAIT_RESET_LOW_TCK  = SIM_SPEED_UP ? 16'd20 : 16'd200;
  localparam logic [15:0] WAIT_RESET_HIGH_TCK = SIM_SPEED_UP ? 16'd10 : 16'd500;
  localparam logic [15:0] WAIT_TMRD_TCK       = 16'd4;
  localparam logic [15:0] WAIT_TMOD_TCK       = 16'd12;
  localparam logic [15:0] WAIT_TZQINIT_TCK    = 16'd512;
  localparam logic [15:0] WAIT_TDLLK_TCK      = 16'd512;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Main Controller FSM (Evaluates on DDR clock boundary tck_tick)
  //////////////////////////////////////////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      state            <= ST_RESET_LOW;
      tck_timer        <= 16'd0;
      rtc_state_start  <= 32'd0;
      rtc_act_start    <= 32'd0;
      rtc_wr_end_start <= 32'd0;
      wr_end_valid     <= 1'b0;
      pre_phase        <= 1'b0;
      rtc_faw_pipe[0]  <= 32'd0;
      rtc_faw_pipe[1]  <= 32'd0;
      rtc_faw_pipe[2]  <= 32'd0;
      rtc_faw_pipe[3]  <= 32'd0;
      faw_valid        <= 4'b0000;
      ref_ack_cnt      <= 32'd0;
      init_done        <= 1'b0;
      init_req_pending <= 1'b0;
      cmd_reg          <= CMD_DESELECT;
      ba_reg           <= '0;
      addr_reg         <= '0;
      cke_reg          <= 1'b0;
      rst_n_reg        <= 1'b0;
      odt_reg          <= 1'b0;
      wa_fifo_rinc     <= 1'b0;
      ra_fifo_rinc     <= 1'b0;
      wr_phy_start     <= 1'b0;
      rd_phy_start     <= 1'b0;
      curr_bank        <= '0;
      curr_row         <= '0;
      curr_col         <= '0;
      active_mr0       <= '0;
      active_mr1       <= '0;
      active_mr2       <= '0;
      active_mr3       <= '0;
      active_tRCD      <= 16'd1;
      active_tRP       <= 16'd1;
      active_tRAS      <= 16'd1;
      active_tRC       <= 16'd1;
      active_tWR       <= 16'd1;
      active_tRTP      <= 16'd1;
      active_tWTR      <= 16'd1;
      active_tRRD      <= 16'd1;
      active_tFAW      <= 16'd1;
      active_tRFC      <= 16'd1;
      active_tREFI     <= 16'd1;
    end else begin
      // Single-cycle pulses cleared by default
      wa_fifo_rinc <= 1'b0;
      ra_fifo_rinc <= 1'b0;
      wr_phy_start <= 1'b0;
      rd_phy_start <= 1'b0;

      // Latch external configuration registers while uninitialized (power-up or init_do re-init)
      if (!init_done && (state == ST_RESET_LOW || state == ST_RESET_HIGH || state == ST_CKE_HIGH)) begin
        active_mr0   <= mr0;
        active_mr1   <= mr1;
        active_mr2   <= mr2;
        active_mr3   <= mr3;
        active_tRCD  <= tRCD;
        active_tRP   <= tRP;
        active_tRAS  <= tRAS;
        active_tRC   <= tRC;
        active_tWR   <= tWR;
        active_tRTP  <= tRTP;
        active_tWTR  <= tWTR;
        active_tRRD  <= tRRD;
        active_tFAW  <= tFAW;
        active_tRFC  <= tRFC;
        active_tREFI <= tREFI;
      end

      // Capture re-initialization request on any clk edge; drop init_done immediately if idle and queues drained
      if (init_do && init_done) begin
        init_req_pending <= 1'b1;
        if ((state == ST_IDLE) && wa_fifo_empty && ra_fifo_empty) begin
          init_done <= 1'b0;
        end
      end

      // Main FSM transitions synchronous to DDR clock boundary
      if (tck_tick) begin
        case (state)
          // ---------------------------------------------------------
          // Power-Up & Initialization Sequence
          // ---------------------------------------------------------
          ST_RESET_LOW: begin
            rst_n_reg <= 1'b0;
            cke_reg   <= 1'b0;
            cmd_reg   <= CMD_DESELECT;
            if (rtc_done(
                    rtc_tick_cnt, rtc_state_start, wait_reset_low_rtc
                ) && (tck_timer >= WAIT_RESET_LOW_TCK)) begin
              rst_n_reg       <= 1'b1;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_RESET_HIGH;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_RESET_HIGH: begin
            rst_n_reg <= 1'b1;
            cke_reg   <= 1'b0;
            cmd_reg   <= CMD_DESELECT;
            if (rtc_done(
                    rtc_tick_cnt, rtc_state_start, wait_reset_high_rtc
                ) && (tck_timer >= WAIT_RESET_HIGH_TCK)) begin
              cke_reg         <= 1'b1;
              cmd_reg         <= CMD_NOP;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_CKE_HIGH;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_CKE_HIGH: begin
            cke_reg <= 1'b1;
            cmd_reg <= CMD_NOP;
            // Wait tXPR (> tRFC + 10ns and >= 5 tCK)
            if (rtc_done(
                    rtc_tick_cnt, rtc_state_start, active_tRFC + 16'd1
                ) && (tck_timer >= 16'd5)) begin
              // Issue MR2 (EMR2)
              cmd_reg         <= CMD_MRS;
              ba_reg          <= 3'd2;
              addr_reg        <= active_mr2;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_LOAD_MR2;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_LOAD_MR2: begin
            cmd_reg <= CMD_NOP;
            if (tck_timer >= WAIT_TMRD_TCK) begin
              // Issue MR3 (EMR3)
              cmd_reg         <= CMD_MRS;
              ba_reg          <= 3'd3;
              addr_reg        <= active_mr3;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_LOAD_MR3;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_LOAD_MR3: begin
            cmd_reg <= CMD_NOP;
            if (tck_timer >= WAIT_TMRD_TCK) begin
              // Issue MR1 (EMR1)
              cmd_reg         <= CMD_MRS;
              ba_reg          <= 3'd1;
              addr_reg        <= active_mr1;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_LOAD_MR1;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_LOAD_MR1: begin
            cmd_reg <= CMD_NOP;
            if (tck_timer >= WAIT_TMRD_TCK) begin
              // Issue MR0 (MRS)
              cmd_reg         <= CMD_MRS;
              ba_reg          <= 3'd0;
              addr_reg        <= active_mr0;
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_LOAD_MR0;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_LOAD_MR0: begin
            cmd_reg <= CMD_NOP;
            // Wait tMOD (>= 12 tCK and >= 15 ns)
            if ((tck_timer >= WAIT_TMOD_TCK) && rtc_done(
                    rtc_tick_cnt, rtc_state_start, 16'd2
                )) begin
              // Issue ZQCL (Long Calibration)
              cmd_reg         <= CMD_ZQCL;
              addr_reg        <= '0;
              addr_reg[10]    <= 1'b1;  // A10 = 1 for ZQCL
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_ZQCL;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_ZQCL: begin
            cmd_reg <= CMD_NOP;
            // Wait tZQINIT (>= 512 tCK and >= 640 ns)
            if ((tck_timer >= WAIT_TZQINIT_TCK) && rtc_done(
                    rtc_tick_cnt, rtc_state_start, active_tRFC
                )) begin
              tck_timer       <= 16'd0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_DLL_WAIT;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_DLL_WAIT: begin
            cmd_reg <= CMD_NOP;
            if ((tck_timer >= WAIT_TDLLK_TCK) && !init_do) begin
              init_done        <= 1'b1;
              init_req_pending <= 1'b0;
              ref_ack_cnt      <= ref_req_cnt;
              tck_timer        <= 16'd0;
              rtc_state_start  <= rtc_tick_cnt;
              state            <= ST_IDLE;
            end else if (tck_timer < WAIT_TDLLK_TCK) begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          // ---------------------------------------------------------
          // Normal Operation & Command Scheduling (Closed Page + AP)
          // ---------------------------------------------------------
          ST_IDLE: begin
            cmd_reg   <= CMD_NOP;
            tck_timer <= 16'd0;

            if (ref_credit > 4'd0) begin
              // Issue REFRESH
              cmd_reg <= CMD_REFRESH;
              ref_ack_cnt <= (pending_ref > 32'd8) ? (ref_req_cnt - 32'd7) : (ref_ack_cnt + 32'd1);
              rtc_state_start <= rtc_tick_cnt;
              state <= ST_REFRESH;
            end else if (!wa_fifo_empty && (wd_fifo_count >= 8) && act_window_ok) begin
              // Schedule WRITE transaction: ACTIVATE bank & row
              decode_address(wa_fifo_raddr, curr_bank, curr_row, curr_col);
              wa_fifo_rinc    <= 1'b1;
              cmd_reg         <= CMD_ACTIVATE;
              ba_reg          <= curr_bank;
              addr_reg        <= curr_row;
              rtc_state_start <= rtc_tick_cnt;
              rtc_act_start   <= rtc_tick_cnt;
              rtc_faw_pipe[3] <= rtc_faw_pipe[2];
              rtc_faw_pipe[2] <= rtc_faw_pipe[1];
              rtc_faw_pipe[1] <= rtc_faw_pipe[0];
              rtc_faw_pipe[0] <= rtc_tick_cnt;
              faw_valid       <= {faw_valid[2:0], 1'b1};
              state           <= ST_WR_ACT_WAIT;
            end else if (!ra_fifo_empty && act_window_ok) begin
              // Schedule READ transaction: ACTIVATE bank & row
              decode_address(ra_fifo_raddr, curr_bank, curr_row, curr_col);
              ra_fifo_rinc    <= 1'b1;
              cmd_reg         <= CMD_ACTIVATE;
              ba_reg          <= curr_bank;
              addr_reg        <= curr_row;
              rtc_state_start <= rtc_tick_cnt;
              rtc_act_start   <= rtc_tick_cnt;
              rtc_faw_pipe[3] <= rtc_faw_pipe[2];
              rtc_faw_pipe[2] <= rtc_faw_pipe[1];
              rtc_faw_pipe[1] <= rtc_faw_pipe[0];
              rtc_faw_pipe[0] <= rtc_tick_cnt;
              faw_valid       <= {faw_valid[2:0], 1'b1};
              state           <= ST_RD_ACT_WAIT;
            end else if (init_do || init_req_pending || !init_done) begin
              // All queues drained: acknowledge re-init request, drop init_done, and reprogram MR2..0 + ZQCL + DLL
              init_done        <= 1'b0;
              init_req_pending <= 1'b0;
              active_mr0       <= mr0;
              active_mr1       <= mr1;
              active_mr2       <= mr2;
              active_mr3       <= mr3;
              active_tRCD      <= tRCD;
              active_tRP       <= tRP;
              active_tRAS      <= tRAS;
              active_tRC       <= tRC;
              active_tWR       <= tWR;
              active_tRTP      <= tRTP;
              active_tWTR      <= tWTR;
              active_tRRD      <= tRRD;
              active_tFAW      <= tFAW;
              active_tRFC      <= tRFC;
              active_tREFI     <= tREFI;
              rtc_state_start  <= rtc_tick_cnt;
              state            <= ST_CKE_HIGH;
            end
          end

          ST_REFRESH: begin
            cmd_reg <= CMD_NOP;
            if (rtc_done(rtc_tick_cnt, rtc_state_start, active_tRFC)) begin
              tck_timer <= 16'd0;
              state     <= ST_IDLE;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          // ---------------------------------------------------------
          // Write Pipeline
          // ---------------------------------------------------------
          ST_WR_ACT_WAIT: begin
            cmd_reg <= CMD_NOP;
            if (rtc_done(rtc_tick_cnt, rtc_state_start, active_tRCD)) begin
              // Issue WRITE command with Auto-Precharge (A10=1)
              cmd_reg         <= CMD_WRITE;
              ba_reg          <= curr_bank;
              addr_reg        <= '0;
              addr_reg[9:0]   <= curr_col[9:0];
              addr_reg[10]    <= 1'b1;  // Auto-Precharge
              addr_reg[12]    <= 1'b0;  // BL8
              odt_reg         <= 1'b1;  // Enable ODT for write
              wr_phy_start    <= 1'b1;  // Arm write PHY
              tck_timer       <= 16'd0;
              pre_phase       <= 1'b0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_WR_PRECHARGE_WAIT;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_WR_PRECHARGE_WAIT: begin
            cmd_reg   <= CMD_NOP;
            tck_timer <= tck_timer + 16'd1;
            if (tck_timer >= 16'd6) begin
              odt_reg <= 1'b0;  // ODT off after write burst (ODTH8 = 6 tCK)
            end

            // Snapshot RTC at end of 8-beat write burst (WL + 4 tCK)
            if (tck_timer == (16'(cfg_wl) + 16'd4)) begin
              rtc_wr_end_start <= rtc_tick_cnt;
              wr_end_valid     <= 1'b1;
            end

            if (!pre_phase) begin
              // Phase 0: Wait for write burst (WL + 4 tCK), Write Recovery (cfg_wr_tck & tWR),
              // and minimum Row Active time (tRAS) so internal auto-precharge begins.
              if ((tck_timer >= (16'(cfg_wl) + 16'd4 + 16'(cfg_wr_tck))) && rtc_done(
                      rtc_tick_cnt, rtc_wr_end_start, active_tWR
                  ) && rtc_done(
                      rtc_tick_cnt, rtc_act_start, active_tRAS
                  )) begin
                pre_phase       <= 1'b1;
                rtc_state_start <= rtc_tick_cnt;
              end
            end else begin
              // Phase 1: Wait for Precharge period (tRP) and Row Cycle time (tRC)
              if (rtc_done(
                      rtc_tick_cnt, rtc_state_start, active_tRP
                  ) && rtc_done(
                      rtc_tick_cnt, rtc_act_start, active_tRC
                  )) begin
                tck_timer <= 16'd0;
                pre_phase <= 1'b0;
                state     <= ST_IDLE;
              end
            end
          end

          // ---------------------------------------------------------
          // Read Pipeline
          // ---------------------------------------------------------
          ST_RD_ACT_WAIT: begin
            cmd_reg <= CMD_NOP;
            if (rtc_done(rtc_tick_cnt, rtc_state_start, active_tRCD) && wtr_ok) begin
              // Issue READ command with Auto-Precharge (A10=1)
              cmd_reg         <= CMD_READ;
              ba_reg          <= curr_bank;
              addr_reg        <= '0;
              addr_reg[9:0]   <= curr_col[9:0];
              addr_reg[10]    <= 1'b1;  // Auto-Precharge
              addr_reg[12]    <= 1'b0;  // BL8
              rd_phy_start    <= 1'b1;  // Arm read capture PHY
              tck_timer       <= 16'd0;
              pre_phase       <= 1'b0;
              rtc_state_start <= rtc_tick_cnt;
              state           <= ST_RD_PRECHARGE_WAIT;
            end else begin
              tck_timer <= tck_timer + 16'd1;
            end
          end

          ST_RD_PRECHARGE_WAIT: begin
            cmd_reg   <= CMD_NOP;
            tck_timer <= tck_timer + 16'd1;

            if (!pre_phase) begin
              // Phase 0: Wait for AL + 4 tCK, Read-to-Precharge (tRTP), and tRAS
              if ((tck_timer >= (16'(cfg_al) + 16'd4)) && rtc_done(
                      rtc_tick_cnt, rtc_state_start, active_tRTP
                  ) && rtc_done(
                      rtc_tick_cnt, rtc_act_start, active_tRAS
                  )) begin
                pre_phase       <= 1'b1;
                rtc_state_start <= rtc_tick_cnt;
              end
            end else begin
              // Phase 1: Wait for Precharge (tRP), tRC, and Read PHY capture completion
              if (rtc_done(
                      rtc_tick_cnt, rtc_state_start, active_tRP
                  ) && rtc_done(
                      rtc_tick_cnt, rtc_act_start, active_tRC
                  ) && (tck_timer >= (16'(cfg_rl) + 16'd6)) && !rd_cap_busy &&
                      !rd_push_active) begin
                tck_timer <= 16'd0;
                pre_phase <= 1'b0;
                state     <= ST_IDLE;
              end
            end
          end

          default: state <= ST_RESET_LOW;
        endcase
      end
    end
  end


  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Write PHY Datapath (Center-Aligned DQS and Synchronous DQ Gearbox)
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // In DDR3, write data arrives at DRAM WL cycles after WRITE command.
  // 1 DDR cycle = 2 system clk cycles.
  // DQS preamble starts 1 tCK (2 clk cycles) before first DQ beat.
  wire  [7:0] wl_sys_cycles = {2'b00, cfg_wl, 1'b0};
  logic [7:0] wr_timer;
  logic       wr_active;

  // Controller is idle when initialized, in ST_IDLE with no pending refresh or re-init,
  // all frontend FIFOs are empty, and both Write/Read PHYs are inactive.
  assign idle = init_done && !init_do && !init_req_pending &&
                (state == ST_IDLE) && (ref_credit == 4'd0) &&
                wa_fifo_empty && wd_fifo_empty && ra_fifo_empty && rd_fifo_empty &&
                !wr_active && !rd_cap_busy && !rd_push_active;

  logic [DATA_WIDTH-1:0] dq_out_reg;
  logic [  DM_WIDTH-1:0] dm_out_reg;
  logic                  dq_oe_reg;
  logic                  dqs_oe_reg;
  logic                  dqs_out_reg;

  // Posedge clk process: controls DQS edges and timing counter
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      wr_timer     <= '0;
      wr_active    <= 1'b0;
      dqs_oe_reg   <= 1'b0;
      dqs_out_reg  <= 1'b0;
      wd_fifo_rinc <= 1'b0;
    end else begin
      wd_fifo_rinc <= 1'b0;

      if (wr_phy_start) begin
        wr_active <= 1'b1;
        wr_timer  <= '0;
      end else if (wr_active) begin
        wr_timer <= wr_timer + 1'b1;

        if (wr_timer >= (wl_sys_cycles - 8'd1) && wr_timer < (wl_sys_cycles + 8'd7)) begin
          wd_fifo_rinc <= 1'b1;  // Advance to next beat in write FIFO
        end

        if (wr_timer == (wl_sys_cycles - 8'd2)) begin
          dqs_oe_reg  <= 1'b1;
          dqs_out_reg <= 1'b0;  // Preamble: DQS low (1 tCK)
        end else if (wr_timer == (wl_sys_cycles - 8'd1)) begin
          dqs_out_reg <= 1'b0;  // Preamble continues low
        end else if (wr_timer >= wl_sys_cycles && wr_timer < (wl_sys_cycles + 8'd8)) begin
          dqs_out_reg <= ~dqs_out_reg;  // Toggle DQS on every posedge clk
        end else if (wr_timer == (wl_sys_cycles + 8'd8)) begin
          dqs_out_reg <= 1'b0;  // Postamble
        end else if (wr_timer == (wl_sys_cycles + 8'd9)) begin
          dqs_oe_reg <= 1'b0;
          wr_active  <= 1'b0;
        end
      end
    end
  end

  // Negedge clk process: launches DQ and DM exactly 90 degrees ahead of DQS!
  always_ff @(negedge clk or negedge arst_n) begin
    if (!arst_n) begin
      dq_oe_reg  <= 1'b0;
      dq_out_reg <= '0;
      dm_out_reg <= '0;
    end else begin
      if (wr_active && wr_timer >= (wl_sys_cycles - 8'd1) && wr_timer < (wl_sys_cycles + 8'd8)) begin
        dq_oe_reg  <= 1'b1;
        dq_out_reg <= wd_fifo_rdata;
        dm_out_reg <= ~wd_fifo_rbe;
      end else if (wr_active && wr_timer == (wl_sys_cycles + 8'd8)) begin
        dq_oe_reg <= 1'b1;  // Hold beat 7 data and mask through DQS latching edge
      end else begin
        dq_oe_reg <= 1'b0;
      end
    end
  end

  // Tri-state buffer drive for Write DQS and DQ
  assign ddr3_dq    = dq_oe_reg ? dq_out_reg : {DATA_WIDTH{1'bz}};
  assign ddr3_dm    = dq_oe_reg ? dm_out_reg : {DM_WIDTH{1'bz}};
  assign ddr3_dqs_p = dqs_oe_reg ? {DQS_WIDTH{dqs_out_reg}} : {DQS_WIDTH{1'bz}};
  assign ddr3_dqs_n = dqs_oe_reg ? {DQS_WIDTH{~dqs_out_reg}} : {DQS_WIDTH{1'bz}};

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Read PHY Datapath (DQS Strobe Capture & Synchronous Gearbox)
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Delay DQS strobe by 250 ps to sample incoming DQ in the eye
  wire  [ DQS_WIDTH-1:0] #250ps dqs_p_dly = ddr3_dqs_p;

  logic [DATA_WIDTH-1:0]        rd_capture_mem         [7:0];
  logic [           3:0]        rd_cap_ptr;
  logic                         rd_burst_done;
  logic [           2:0]        rd_push_cnt;

  // Reset capture pointer when a new READ is launched
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      rd_cap_busy    <= 1'b0;
      rd_push_active <= 1'b0;
      rd_push_cnt    <= '0;
      rd_fifo_winc   <= 1'b0;
      rd_fifo_wdata  <= '0;
    end else begin
      rd_fifo_winc <= 1'b0;

      if (rd_phy_start) begin
        rd_cap_busy <= 1'b1;
      end else if (rd_burst_done && rd_cap_busy) begin
        rd_cap_busy    <= 1'b0;
        rd_push_active <= 1'b1;
        rd_push_cnt    <= '0;
      end

      // Push captured 8 beats into rd_fifo synchronously
      if (rd_push_active) begin
        rd_fifo_winc  <= 1'b1;
        rd_fifo_wdata <= rd_capture_mem[rd_push_cnt];
        if (rd_push_cnt == 3'd7) begin
          rd_push_active <= 1'b0;
        end else begin
          rd_push_cnt <= rd_push_cnt + 1'b1;
        end
      end
    end
  end

  // DQS edge-triggered capture (per-beat sampling)
  // (dqs_p_dly[0] === 1'b1 || rd_cap_ptr != 0) ignores the preamble falling transition!
  always @(posedge dqs_p_dly[0] or negedge dqs_p_dly[0] or posedge rd_phy_start or negedge arst_n) begin
    if (!arst_n || rd_phy_start) begin
      rd_cap_ptr    <= '0;
      rd_burst_done <= 1'b0;
    end else if (rd_cap_busy && (dqs_p_dly[0] === 1'b1 || rd_cap_ptr != 0)) begin
      if (rd_cap_ptr < 8) begin
        rd_capture_mem[rd_cap_ptr[2:0]] <= ddr3_dq;
        rd_cap_ptr <= rd_cap_ptr + 1'b1;
        if (rd_cap_ptr == 7) begin
          rd_burst_done <= 1'b1;
        end
      end
    end
  end

endmodule

module ddr3_fifo_for_ddr3_controller #(
    parameter string NAME = "",
    parameter int WIDTH = 64,
    parameter int DEPTH = 16
) (
    input logic clk,
    input logic arst_n,

    // Write Port
    input  logic                   winc,
    input  logic [      WIDTH-1:0] wdata,
    output logic                   full,
    output logic                   almost_full,
    output logic [$clog2(DEPTH):0] count,

    // Read Port
    input  logic             rinc,
    output logic [WIDTH-1:0] rdata,
    output logic             empty
);

  localparam int ADDR_W = $clog2(DEPTH);

  logic [WIDTH-1:0] mem  [DEPTH-1:0];
  logic [ ADDR_W:0] wptr;
  logic [ ADDR_W:0] rptr;

  assign empty       = (wptr == rptr);
  assign full        = (wptr[ADDR_W] != rptr[ADDR_W]) && (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);
  assign count       = wptr - rptr;
  assign almost_full = (count >= (DEPTH - 8));  // Room for less than an 8-beat burst
  assign rdata       = mem[rptr[ADDR_W-1:0]];

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      wptr <= '0;
      rptr <= '0;
    end else begin
      if (winc && !full) begin
        mem[wptr[ADDR_W-1:0]] <= wdata;
        wptr <= wptr + 1'b1;
      end
      if (rinc && !empty) begin
        rptr <= rptr + 1'b1;
      end
    end
  end

endmodule
