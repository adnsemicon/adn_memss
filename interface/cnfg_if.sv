interface cnfg_if #(
  parameter int DRAM_ADDR_BITS = 14
) (
  input logic clk,
  input logic arst_n
);

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


task automatic apply_cfg(
    input logic [DRAM_ADDR_BITS-1:0] in_mr0   = 'h0D70, // BL8, CL=6, WR=6, DLL Reset
    input logic [DRAM_ADDR_BITS-1:0] in_mr1   = 'h0010, // DLL Enable
    input logic [DRAM_ADDR_BITS-1:0] in_mr2   = 'h0000, // CWL=5
    input logic [DRAM_ADDR_BITS-1:0] in_mr3   = 'h0000, // MPR=0
    input logic [15:0]               in_tRCD  = 16'd4,   // Safe margin for >15ns
    input logic [15:0]               in_tRP   = 16'd4,   // Safe margin for >15ns
    input logic [15:0]               in_tRAS  = 16'd8,   // Safe margin for >37.5ns
    input logic [15:0]               in_tRC   = 16'd12,  // Safe margin for >52.5ns
    input logic [15:0]               in_tWR   = 16'd4,   // Safe margin for >15ns
    input logic [15:0]               in_tRTP  = 16'd4,   // min 4tCK
    input logic [15:0]               in_tWTR  = 16'd4,   // min 4tCK
    input logic [15:0]               in_tRRD  = 16'd4,   // Safe margin for >10ns
    input logic [15:0]               in_tFAW  = 16'd10,  // Safe margin for >50ns
    input logic [15:0]               in_tRFC  = 16'd28,  // Guarantees >120ns tXPR & >110ns tRFC!
    input logic [15:0]               in_tREFI = 16'd780  // 7.8us refresh interval
  );

    mr0     <= in_mr0;
    mr1     <= in_mr1;
    mr2     <= in_mr2;
    mr3     <= in_mr3;

    tRCD    <= in_tRCD;
    tRP     <= in_tRP;
    tRAS    <= in_tRAS;
    tRC     <= in_tRC;
    tWR     <= in_tWR;
    tRTP    <= in_tRTP;
    tWTR    <= in_tWTR;
    tRRD    <= in_tRRD;
    tFAW    <= in_tFAW;
    tRFC    <= in_tRFC;
    tREFI   <= in_tREFI;
    init_do <= 1'b0;

    // 2. Wait until asynchronous reset is released
    wait (arst_n === 1'b1);
    @(posedge clk);

    // 3. Only pulse init_do if controller was ALREADY initialized (for on-the-fly re-init)

    if (init_done === 1'b1) begin
      init_do <= 1'b1;
      @(posedge clk);
      init_do <= 1'b0;
      wait (init_done === 1'b0);
    end

    // 4. Wait for controller to complete JEDEC initialization sequence
    do begin
      @(posedge clk);
    end while (init_done !== 1'b1);
    @(posedge clk);
  endtask

  // Task 3: Shorten tREFI dynamically for Refresh Collision Test
  task automatic set_fast_refresh(input logic [15:0] fast_tREFI = 16'd200);
    @(posedge clk);
    tREFI <= fast_tREFI;
  endtask

  // Task 4: On-The-Fly Timing Update (Mid-traffic without pulsing init_do)
  task automatic update_timings_on_the_fly(
    input logic [15:0] new_tRCD,
    input logic [15:0] new_tRP,
    input logic [15:0] new_tRAS,
    input logic [15:0] new_tRC,
    input logic [15:0] new_tREFI
  );
    @(posedge clk);
    tRCD  <= new_tRCD;
    tRP   <= new_tRP;
    tRAS  <= new_tRAS;
    tRC   <= new_tRC;
    tREFI <= new_tREFI;
  endtask

  // Task 5: Live Re-Initialization (Update Mode Registers & pulse init_do mid-traffic)
  task automatic trigger_reinit(
    input logic [DRAM_ADDR_BITS-1:0] new_mr0,
    input logic [DRAM_ADDR_BITS-1:0] new_mr2
  );
    @(posedge clk);
    mr0     <= new_mr0;
    mr2     <= new_mr2;
    init_do <= 1'b1;
    @(posedge clk);
    init_do <= 1'b0;

    do begin
      @(posedge clk);
    end while (init_done !== 1'b1);
  endtask

endinterface
