interface cnfg_if #(
  parameter int DRAM_ADDR_BITS = 14
) (
  input logic clk,
  input logic arst_n
);

  `ifdef den1024Mb
    `include "1024Mb_ddr3_parameters.vh"
  `elsif den2048Mb
    `include "2048Mb_ddr3_parameters.vh"
  `elsif den4096Mb
    `include "4096Mb_ddr3_parameters.vh"
  `elsif den8192Mb
    `include "8192Mb_ddr3_parameters.vh"
  `else
    `include "1024Mb_ddr3_parameters.vh"
  `endif


  localparam realtime TREFI = 7.8us;

  // -------------------------------------------------------------------------
  // 1. Initialization Handshake Signals
  // -------------------------------------------------------------------------
  logic init_do;
  logic init_done;

  // -------------------------------------------------------------------------
  // 2. DDR3 Mode Registers (MR0 - MR3)
  // -------------------------------------------------------------------------
  logic [DRAM_ADDR_BITS-1:0] mr0;  // Mode Register 0 (MRS: BL, CL, DLL Reset, WR, PPD)
  logic [DRAM_ADDR_BITS-1:0] mr1;  // Mode Register 1 (EMR1: DLL En, DIC, RTT_nom, AL)
  logic [DRAM_ADDR_BITS-1:0] mr2;  // Mode Register 2 (EMR2: PASR, CWL, ASR, SRT, RTT_wr)
  logic [DRAM_ADDR_BITS-1:0] mr3;  // Mode Register 3 (EMR3: MPR)

  // -------------------------------------------------------------------------
  // 3. Core DRAM Timings (Measured in 16-bit RTC ticks)
  // -------------------------------------------------------------------------
  logic [15:0] tRCD;  // ACT to READ/WRITE delay (in RTC ticks)
  logic [15:0] tRP;   // PRECHARGE command period (in RTC ticks)
  logic [15:0] tRAS;  // ACT to PRECHARGE delay (in RTC ticks)
  logic [15:0] tRC;   // ACT to ACT / REF period (in RTC ticks)
  logic [15:0] tWR;   // Write recovery time (in RTC ticks)
  logic [15:0] tRTP;  // READ to PRECHARGE delay (in RTC ticks)
  logic [15:0] tWTR;  // Write to Read delay (in RTC ticks)
  logic [15:0] tRRD;  // ACT bank A to ACT bank B delay (in RTC ticks)
  logic [15:0] tFAW;  // Four-bank activate window (in RTC ticks)
  logic [15:0] tRFC;  // AUTO REFRESH command period (in RTC ticks)
  logic [15:0] tREFI; // Periodic refresh interval (~7.8 us in RTC ticks)


  // =========================================================================
  // 4. BFM CONFIGURATION TASKS
  // =========================================================================

  // Task 1: Reset all configuration signals to zero (Call during reset phase)
  task automatic reset_cfg();
    init_do <= 1'b0;
    mr0     <= '0;
    mr1     <= '0;
    mr2     <= '0;
    mr3     <= '0;
    tRCD    <= '0;
    tRP     <= '0;
    tRAS    <= '0;
    tRC     <= '0;
    tWR     <= '0;
    tRTP    <= '0;
    tWTR    <= '0;
    tRRD    <= '0;
    tFAW    <= '0;
    tRFC    <= '0;
    tREFI   <= '0;
  endtask

function automatic int calc_tick(input realtime tparam,input realtime rtc_tp);
    return int'($ceil(tparam / (rtc_tp)));
endfunction


task automatic apply_cfg(
    input realtime  rtc_tp                        = 10ns,
    input logic [DRAM_ADDR_BITS-1:0] in_mr0   = 'h0D70, // WR=12, CL=11, BL=8, DLL Reset=1
    input logic [DRAM_ADDR_BITS-1:0] in_mr1   = 'h0010, // DLL Enable
    input logic [DRAM_ADDR_BITS-1:0] in_mr2   = 'h0000, // CWL=5
    input logic [DRAM_ADDR_BITS-1:0] in_mr3   = 'h0000 // MPR=0
  );

    mr0     <= in_mr0;
    mr1     <= in_mr1;
    mr2     <= in_mr2;
    mr3     <= in_mr3;

    tRCD    <= calc_tick(TRCD , rtc_tp); 
    tRP     <= calc_tick(TRP  , rtc_tp);
    tRAS    <= calc_tick(TRAS_MIN , rtc_tp);
    tRC     <= calc_tick(TRC  , rtc_tp);
    tWR     <= calc_tick(TWR  , rtc_tp);
    tRTP    <= calc_tick(TRTP , rtc_tp);
    tWTR    <= calc_tick(TWTR , rtc_tp);
    tRRD    <= calc_tick(TRRD , rtc_tp);
    tFAW    <= calc_tick(TFAW , rtc_tp);
    tRFC    <= calc_tick((TXPR > TRFC_MIN) ? TXPR : TRFC_MIN, rtc_tp) + 16;
    tREFI   <= calc_tick(TREFI, rtc_tp) - 1;
    init_do <= 1'b0;

    wait (arst_n === 1'b1);
    @(posedge clk);
    do begin
      @(posedge clk);
    end while (init_done !== 1'b1);
    @(posedge clk);
  endtask

  task automatic set_fast_refresh(input logic [15:0] fast_tREFI = 16'd200);
    @(posedge clk);
    tREFI <= fast_tREFI;
  endtask

  task automatic update_timings_on_the_fly(
      input realtime rtc_tp       = 10ns,
      input int  margin_ticks = 2, // Default 2 tick bariye test korbe
      input int  custom_tREFI = 780
    );
      @(posedge clk);
      tRCD  <= calc_tick(TRCD    , rtc_tp) + margin_ticks;
      tRP   <= calc_tick(TRP     , rtc_tp) + margin_ticks;
      tRAS  <= calc_tick(TRAS_MIN, rtc_tp) + margin_ticks;
      tRC   <= calc_tick(TRC     , rtc_tp) + margin_ticks;
      tWR   <= calc_tick(TWR     , rtc_tp) + margin_ticks;
      tRTP  <= calc_tick(TRTP    , rtc_tp) + margin_ticks;
      tWTR  <= calc_tick(TWTR    , rtc_tp) + margin_ticks;
      tRRD  <= calc_tick(TRRD    , rtc_tp) + margin_ticks;
      tFAW  <= calc_tick(TFAW    , rtc_tp) + margin_ticks;
      tRFC  <= calc_tick(TRFC_MIN, rtc_tp) + margin_ticks;
      tREFI <= custom_tREFI;
    endtask

  task automatic trigger_reinit(
    input logic [DRAM_ADDR_BITS-1:0] new_mr0    = 'h0D70, // WR=12, CL=11, BL=8, DLL Reset=1,
    input logic [DRAM_ADDR_BITS-1:0] new_mr1    = 'h0010, // DLL Enable
    input logic [DRAM_ADDR_BITS-1:0] new_mr2    = 'h0000, // MPR=0,
    input logic [DRAM_ADDR_BITS-1:0] new_mr3    = 'h0000 // MPR=0

  );
    @(posedge clk);
    mr0     <= new_mr0;
    mr1     <= new_mr1;
    mr2     <= new_mr2;
    mr3     <= new_mr3;
    init_do <= 1'b1;
    @(posedge clk);
    init_do <= 1'b0;

    do begin
      @(posedge clk);
    end while (init_done !== 1'b1);
  endtask

endinterface
