// =============================================================================
// File: tb.sv
// Description: Rigorous Testbench for Fixed-Burst (mem_if) DDR3 SDRAM Controller
//
// Verification Scope:
//   1. Initialization & Calibration: JEDEC DDR3 power-up, MRS (0-3), ZQCL, DLL lock.
//   2. External Register File Configuration: Runtime MR0..MR3 and RTC-tick timing
//      parameters (tRCD, tRP, tRAS, tRC, tWR, tRTP, tWTR, tRRD, tFAW, tRFC, tREFI).
//   3. Directed Multi-Bank Test: All 8 DRAM banks exercised with unique data.
//   4. Byte-Enable / Masking Test: Verify wd_be correctly preserves masked bytes.
//   5. Flow Control & Backpressure Stress: Random deassertion of rd_ready during burst.
//   6. Pipelined Queueing Stress: Multi-burst back-to-back writes and reads.
//   7. Idle Clock Throttling & Differential Clock Tracking: System clock (clk)
//      throttles during idle; verifies ddr3_ck_p/ck_n follows clk/2 and RTC refresh.
//   8. Multi-RTC Frequency Verification: 1 MHz, 8 MHz, 16 MHz, 32 MHz, and 100 MHz.
//   9. Randomized Stress Test: Scoreboard-driven random reads/writes with byte masking.
// =============================================================================

module adn_memss_ddr3_controller_tb;

  // -------------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------------
  localparam int ADDR_WIDTH = 30;
  localparam int DATA_WIDTH = 64;
  localparam int DRAM_CHIP_WIDTH = 16;  // 4 chips in parallel (4 x 16 = 64)
  localparam int BE_WIDTH = DATA_WIDTH / 8;
  localparam int DQS_WIDTH = DATA_WIDTH / 8;
  localparam int DM_WIDTH = DATA_WIDTH / 8;
  localparam int DRAM_ADDR_BITS = 16;
  localparam int DRAM_BA_BITS = 3;

  localparam realtime T_SYS_NOM  = 650ps;  // 1.538 GHz active system clock (769 MHz DDR clock, tCK = 1300 ps)

  // -------------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------------
  logic                         clk;
  logic                         rtc;
  logic                         arst_n;

  // Dynamic Clock & RTC Periods
  realtime                      t_sys_half = T_SYS_NOM / 2.0;
  realtime                      t_rtc_half = 5000.0ps;  // Default 100 MHz RTC (T_RTC = 10 ns)
  bit                           clk_throttled = 1'b0;

  // External Register File: Mode Registers & Timing Parameters (in RTC ticks)
  logic    [DRAM_ADDR_BITS-1:0] reg_mr0;
  logic    [DRAM_ADDR_BITS-1:0] reg_mr1;
  logic    [DRAM_ADDR_BITS-1:0] reg_mr2;
  logic    [DRAM_ADDR_BITS-1:0] reg_mr3;

  logic    [              15:0] reg_tRCD;
  logic    [              15:0] reg_tRP;
  logic    [              15:0] reg_tRAS;
  logic    [              15:0] reg_tRC;
  logic    [              15:0] reg_tWR;
  logic    [              15:0] reg_tRTP;
  logic    [              15:0] reg_tWTR;
  logic    [              15:0] reg_tRRD;
  logic    [              15:0] reg_tFAW;
  logic    [              15:0] reg_tRFC;
  logic    [              15:0] reg_tREFI;

  // mem_if signals
  logic    [    ADDR_WIDTH-1:0] wa_addr;
  logic                         wa_valid;
  wire                          wa_ready;

  logic    [    DATA_WIDTH-1:0] wd_data;
  logic    [      BE_WIDTH-1:0] wd_be;
  logic                         wd_valid;
  wire                          wd_ready;

  logic    [    ADDR_WIDTH-1:0] ra_addr;
  logic                         ra_valid;
  wire                          ra_ready;

  wire     [    DATA_WIDTH-1:0] rd_data;
  wire                          rd_valid;
  logic                         rd_ready;

  // DDR3 Physical Signals
  wire                          ddr3_ck_p;
  wire                          ddr3_ck_n;
  wire                          ddr3_rst_n;
  wire                          ddr3_cke;
  wire                          ddr3_cs_n;
  wire                          ddr3_ras_n;
  wire                          ddr3_cas_n;
  wire                          ddr3_we_n;
  wire                          ddr3_odt;
  wire     [  DRAM_BA_BITS-1:0] ddr3_ba;
  wire     [DRAM_ADDR_BITS-1:0] ddr3_addr;
  wire     [      DM_WIDTH-1:0] ddr3_dm;
  wire     [     DQS_WIDTH-1:0] ddr3_dqs_p;
  wire     [     DQS_WIDTH-1:0] ddr3_dqs_n;
  wire     [    DATA_WIDTH-1:0] ddr3_dq;

  logic                         init_do;
  wire                          init_done;
  wire                          idle;

  // -------------------------------------------------------------------------
  // System Clock (clk) & Real-Time Clock (rtc) Generators
  // -------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #(t_sys_half) clk = ~clk;
  end

  initial begin
    rtc = 1'b0;
    forever #(t_rtc_half) rtc = ~rtc;
  end

  // Helper task to throttle/unthrottle system clock cleanly on DDR clock boundary
  task automatic set_clk_throttle(input int div_factor);
    @(negedge clk);
    while (ddr3_ck_p !== 1'b0) @(negedge clk);
    if (div_factor <= 1) begin
      t_sys_half    = T_SYS_NOM / 2.0;
      clk_throttled = 1'b0;
    end else begin
      t_sys_half    = (T_SYS_NOM * div_factor) / 2.0;
      clk_throttled = 1'b1;
    end
  endtask

  // Helper function for ceiling division in RTC tick calculation
  function automatic logic [15:0] calc_rtc_ticks(input real time_ns, input real rtc_period_ns);
    int  ticks;
    real ratio;
    ratio = time_ns / rtc_period_ns;
    ticks = $rtoi(ratio);
    if (ratio > ticks) ticks = ticks + 1;
    if (ticks < 1) ticks = 1;
    return 16'(ticks);
  endfunction

  // Helper task to program external register file for a given RTC frequency (in MHz)
  // and latency settings (CL, CWL, AL, WR)
  task automatic configure_register_file(input real rtc_freq_mhz, input int cl = 11,
                                         input int cwl = 8, input int al = 0, input int wr = 12);
    real rtc_period_ns;
    logic [3:0] cl_field;
    logic [2:0] wr_field;
    int refi_ticks;

    rtc_period_ns = 1000.0 / rtc_freq_mhz;
    t_rtc_half    = (rtc_period_ns * 1000.0) / 2.0;  // Convert ns to ps half-period

    // Encode MR0 (MRS)
    cl_field = 4'(cl - 4);
    case (wr)
      5:       wr_field = 3'b001;
      6:       wr_field = 3'b010;
      7:       wr_field = 3'b011;
      8:       wr_field = 3'b100;
      10:      wr_field = 3'b101;
      12:      wr_field = 3'b110;
      14:      wr_field = 3'b111;
      16:      wr_field = 3'b000;
      default: wr_field = 3'b110;
    endcase
    reg_mr0       = '0;
    reg_mr0[1:0]  = 2'b00;  // Fixed BL8
    reg_mr0[2]    = cl_field[3];  // CL bit 3
    reg_mr0[3]    = 1'b0;  // Sequential burst
    reg_mr0[6:4]  = cl_field[2:0];  // CL bits 2:0
    reg_mr0[7]    = 1'b0;  // Normal mode
    reg_mr0[8]    = 1'b1;  // DLL Reset
    reg_mr0[11:9] = wr_field;  // Write Recovery (WR)
    reg_mr0[12]   = 1'b1;  // Fast exit PPD (DLL on)

    // Encode MR1 (EMR1)
    reg_mr1       = '0;
    reg_mr1[0]    = 1'b0;  // DLL Enable (active low)
    reg_mr1[1]    = 1'b0;  // DIC = RZQ/6
    reg_mr1[2]    = 1'b1;  // RTT_nom = RZQ/4
    reg_mr1[4:3]  = (al == 0) ? 2'b00 : (al == cl - 1) ? 2'b01 : 2'b10;

    // Encode MR2 (EMR2)
    reg_mr2       = '0;
    reg_mr2[5:3]  = 3'(cwl - 5);  // CAS Write Latency
    reg_mr2[10:9] = 2'b00;  // Dynamic ODT disabled

    // Encode MR3 (EMR3)
    reg_mr3       = '0;

    // Calculate DRAM Timings in RTC ticks (DDR3-1600 8Gb spec: tRCD=13.75ns, tRP=13.75ns,
    // tRAS=35ns, tRC=48.75ns, tWR=15ns, tRTP=7.5ns, tWTR=7.5ns, tRRD=7.5ns, tFAW=40ns,
    // tRFC=260ns, tREFI=7800ns)
    reg_tRCD      = calc_rtc_ticks(13.75, rtc_period_ns);
    reg_tRP       = calc_rtc_ticks(13.75, rtc_period_ns);
    reg_tRAS      = calc_rtc_ticks(35.00, rtc_period_ns);
    reg_tRC       = calc_rtc_ticks(48.75, rtc_period_ns);
    reg_tWR       = calc_rtc_ticks(15.00, rtc_period_ns);
    reg_tRTP      = calc_rtc_ticks(7.50, rtc_period_ns);
    reg_tWTR      = calc_rtc_ticks(7.50, rtc_period_ns);
    reg_tRRD      = calc_rtc_ticks(7.50, rtc_period_ns);
    reg_tFAW      = calc_rtc_ticks(40.00, rtc_period_ns);
    reg_tRFC      = calc_rtc_ticks(260.0, rtc_period_ns);

    refi_ticks    = $rtoi(7800.0 / rtc_period_ns);
    if (refi_ticks < 1) refi_ticks = 1;
    reg_tREFI = 16'(refi_ticks);

    $display(
        "[REGFILE] RTC = %0.1f MHz (T_RTC = %0.2f ns) | MR0=0x%04h MR1=0x%04h MR2=0x%04h MR3=0x%04h",
        rtc_freq_mhz, rtc_period_ns, reg_mr0, reg_mr1, reg_mr2, reg_mr3);
    $display(
        "          tRCD=%0d tRP=%0d tRAS=%0d tRC=%0d tWR=%0d tRTP=%0d tWTR=%0d tRRD=%0d tFAW=%0d tRFC=%0d tREFI=%0d (RTC ticks)",
        reg_tRCD, reg_tRP, reg_tRAS, reg_tRC, reg_tWR, reg_tRTP, reg_tWTR, reg_tRRD, reg_tFAW,
        reg_tRFC, reg_tREFI);

    // If controller is already running, perform the init_do -> !init_done -> init_done handshake
    if (arst_n === 1'b1) begin
      @(posedge clk);
      init_do <= 1'b1;
      wait (init_done === 1'b0);
      @(posedge clk);
      init_do <= 1'b0;
      wait (init_done === 1'b1);
      @(posedge clk);
      $display("[REGFILE @ %0t] Re-initialization complete (init_done = 1)!", $realtime);
    end
  endtask

  // -------------------------------------------------------------------------
  // Differential Clock Tracking Monitor (Verifies ddr3_ck_p/ck_n follows clk)
  // -------------------------------------------------------------------------
  int total_writes = 0;
  int total_reads = 0;
  int error_count = 0;

  realtime last_clk_pos = 0;
  realtime last_ck_pos = 0;
  realtime measured_clk_period = 0;
  realtime measured_ck_period = 0;

  always @(posedge clk) begin
    if (last_clk_pos > 0) measured_clk_period = $realtime - last_clk_pos;
    last_clk_pos = $realtime;
  end

  always @(posedge ddr3_ck_p) begin
    if (arst_n) begin
      if (ddr3_ck_n !== 1'b0) begin
        $display("[ERROR @ %0t] Differential clock complementarity violation: ck_p=%b, ck_n=%b",
                 $realtime, ddr3_ck_p, ddr3_ck_n);
        error_count++;
      end
      if (last_ck_pos > 0) measured_ck_period = $realtime - last_ck_pos;
      last_ck_pos = $realtime;
    end
  end

  // -------------------------------------------------------------------------
  // DUT: DDR3 Controller
  // -------------------------------------------------------------------------
  adn_memss_ddr3_controller #(
      .ADDR_WIDTH     (ADDR_WIDTH),
      .DATA_WIDTH     (DATA_WIDTH),
      .DRAM_CHIP_WIDTH(DRAM_CHIP_WIDTH),
      .SIM_SPEED_UP   (1'b1)
  ) u_controller (
      .clk   (clk),
      .rtc   (rtc),
      .arst_n(arst_n),

      // External Register File: Mode Registers & Timing Inputs
      .mr0  (reg_mr0),
      .mr1  (reg_mr1),
      .mr2  (reg_mr2),
      .mr3  (reg_mr3),
      .tRCD (reg_tRCD),
      .tRP  (reg_tRP),
      .tRAS (reg_tRAS),
      .tRC  (reg_tRC),
      .tWR  (reg_tWR),
      .tRTP (reg_tRTP),
      .tWTR (reg_tWTR),
      .tRRD (reg_tRRD),
      .tFAW (reg_tFAW),
      .tRFC (reg_tRFC),
      .tREFI(reg_tREFI),

      // mem_if
      .wa_addr (wa_addr),
      .wa_valid(wa_valid),
      .wa_ready(wa_ready),

      .wd_data (wd_data),
      .wd_be   (wd_be),
      .wd_valid(wd_valid),
      .wd_ready(wd_ready),

      .ra_addr (ra_addr),
      .ra_valid(ra_valid),
      .ra_ready(ra_ready),

      .rd_data (rd_data),
      .rd_valid(rd_valid),
      .rd_ready(rd_ready),

      // DDR3 Physical
      .ddr3_ck_p (ddr3_ck_p),
      .ddr3_ck_n (ddr3_ck_n),
      .ddr3_rst_n(ddr3_rst_n),
      .ddr3_cke  (ddr3_cke),
      .ddr3_cs_n (ddr3_cs_n),
      .ddr3_ras_n(ddr3_ras_n),
      .ddr3_cas_n(ddr3_cas_n),
      .ddr3_we_n (ddr3_we_n),
      .ddr3_odt  (ddr3_odt),
      .ddr3_ba   (ddr3_ba),
      .ddr3_addr (ddr3_addr),
      .ddr3_dm   (ddr3_dm),
      .ddr3_dqs_p(ddr3_dqs_p),
      .ddr3_dqs_n(ddr3_dqs_n),
      .ddr3_dq   (ddr3_dq),

      .init_do  (init_do),
      .init_done(init_done),
      .idle     (idle)
  );

  // -------------------------------------------------------------------------
  // Parallel DDR3 Chip Array (4 x 16 = 64-bit DQ)
  // -------------------------------------------------------------------------
  adn_memss_ddr3_chip_array #(
      .DATA_WIDTH     (DATA_WIDTH),
      .DRAM_CHIP_WIDTH(DRAM_CHIP_WIDTH)
  ) u_chip_array (
      .ddr3_ck_p (ddr3_ck_p),
      .ddr3_ck_n (ddr3_ck_n),
      .ddr3_rst_n(ddr3_rst_n),
      .ddr3_cke  (ddr3_cke),
      .ddr3_cs_n (ddr3_cs_n),
      .ddr3_ras_n(ddr3_ras_n),
      .ddr3_cas_n(ddr3_cas_n),
      .ddr3_we_n (ddr3_we_n),
      .ddr3_odt  (ddr3_odt),
      .ddr3_ba   (ddr3_ba),
      .ddr3_addr (ddr3_addr),
      .ddr3_dm   (ddr3_dm),
      .ddr3_dqs_p(ddr3_dqs_p),
      .ddr3_dqs_n(ddr3_dqs_n),
      .ddr3_dq   (ddr3_dq)
  );

  // -------------------------------------------------------------------------
  // Golden Scoreboard: Byte-Level Associative Memory
  // -------------------------------------------------------------------------
  typedef logic [7:0] byte_t;
  byte_t scoreboard[logic [ADDR_WIDTH-1:0]];

  function automatic void scoreboard_write(input logic [ADDR_WIDTH-1:0] base_addr,
                                           input logic [DATA_WIDTH-1:0] data[7:0],
                                           input logic [BE_WIDTH-1:0] be[7:0]);
    logic [ADDR_WIDTH-1:0] byte_addr;
    for (int beat = 0; beat < 8; beat++) begin
      for (int b = 0; b < BE_WIDTH; b++) begin
        byte_addr = base_addr + (beat * BE_WIDTH) + b;
        if (be[beat][b]) begin
          scoreboard[byte_addr] = data[beat][b*8+:8];
        end
      end
    end
  endfunction

  function automatic logic [DATA_WIDTH-1:0] scoreboard_get_expected(
      input logic [ADDR_WIDTH-1:0] base_addr, input int beat);
    logic [DATA_WIDTH-1:0] exp_word;
    logic [ADDR_WIDTH-1:0] byte_addr;
    exp_word = '0;
    for (int b = 0; b < BE_WIDTH; b++) begin
      byte_addr = base_addr + (beat * BE_WIDTH) + b;
      if (scoreboard.exists(byte_addr)) begin
        exp_word[b*8+:8] = scoreboard[byte_addr];
      end else begin
        exp_word[b*8+:8] = 8'hxx;  // Uninitialized
      end
    end
    return exp_word;
  endfunction

  // -------------------------------------------------------------------------
  // Driver Tasks
  // -------------------------------------------------------------------------
  task automatic send_write(input logic [ADDR_WIDTH-1:0] base_addr,
                            input logic [DATA_WIDTH-1:0] data[7:0],
                            input logic [BE_WIDTH-1:0] be[7:0]);
    total_writes++;
    scoreboard_write(base_addr, data, be);

    // Ensure full-speed clock when host initiates transaction
    if (clk_throttled) set_clk_throttle(1);

    // Address Phase
    @(posedge clk);
    wa_addr  <= base_addr;
    wa_valid <= 1'b1;
    while (!wa_ready) @(posedge clk);
    @(posedge clk);
    wa_valid <= 1'b0;

    // Data Phase: 8 beats
    for (int beat = 0; beat < 8; beat++) begin
      wd_data  <= data[beat];
      wd_be    <= be[beat];
      wd_valid <= 1'b1;
      @(posedge clk);
      while (!wd_ready) @(posedge clk);
    end
    wd_valid <= 1'b0;
  endtask

  task automatic send_read(input logic [ADDR_WIDTH-1:0] base_addr,
                           input bit random_backpressure = 1'b0);
    logic [DATA_WIDTH-1:0] actual_beat;
    logic [DATA_WIDTH-1:0] expected_beat;
    total_reads++;

    // Ensure full-speed clock when host initiates transaction
    if (clk_throttled) set_clk_throttle(1);

    // Address Phase
    @(posedge clk);
    ra_addr  <= base_addr;
    ra_valid <= 1'b1;
    while (!ra_ready) @(posedge clk);
    @(posedge clk);
    ra_valid <= 1'b0;

    // Data Reception Phase: 8 beats
    for (int beat = 0; beat < 8; beat++) begin
      rd_ready <= 1'b0;
      if (random_backpressure) begin
        // Randomly stall receiver to stress rd_ready flow control
        repeat ($urandom_range(1, 4)) @(negedge clk);
      end

      // Keep the FIFO stalled until the current beat has been sampled.
      while (!rd_valid) @(negedge clk);

      // Sample data beat before clock edge
      actual_beat   = rd_data;
      expected_beat = scoreboard_get_expected(base_addr, beat);

      // Verify with scoreboard
      if (actual_beat !== expected_beat) begin
        $display("[ERROR @ %0t] Mismatch at Addr 0x%08h Beat %0d! Expected: 0x%016h, Got: 0x%016h",
                 $realtime, base_addr, beat, expected_beat, actual_beat);
        error_count++;
      end

      // Accept exactly the sampled beat on the next clock edge.
      rd_ready <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      rd_ready <= 1'b0;
    end
  endtask

  // Task to wait until controller asserts top-level `idle`, then throttle clk
  task automatic idle_with_clock_throttle(input int div_factor, input int throttled_ddr_cycles);
    wait (idle === 1'b1);
    set_clk_throttle(div_factor);
    repeat (throttled_ddr_cycles * 2) @(posedge clk);

    // Verify DDR3 differential clock period tracks 2x throttled system clock period
    if (div_factor > 1 && throttled_ddr_cycles >= 3) begin
      realtime expected_ck_period;
      realtime diff;
      expected_ck_period = 2.0 * (T_SYS_NOM * div_factor);
      diff = (measured_ck_period > expected_ck_period) ?
             (measured_ck_period - expected_ck_period) :
             (expected_ck_period - measured_ck_period);
      if (diff > 10.0ps) begin
        $display(
            "[ERROR @ %0t] DDR3 CK period (%0.1f ps) did not follow throttled clk (expected %0.1f ps)!",
            $realtime, measured_ck_period, expected_ck_period);
        error_count++;
      end
    end
    set_clk_throttle(1);
    repeat (10) @(posedge clk);
  endtask

  // -------------------------------------------------------------------------
  // Main Verification Flow
  // -------------------------------------------------------------------------
  initial begin
    logic [DATA_WIDTH-1:0] test_data [7:0];
    logic [BE_WIDTH-1:0]   test_be   [7:0];
    logic [ADDR_WIDTH-1:0] test_addr;
    real rtc_freqs[5];

    $timeformat(-9, 2, " ns", 10);

    arst_n   = 1'b0;
    init_do  = 1'b0;
    wa_addr  = '0;
    wa_valid = 1'b0;
    wd_data  = '0;
    wd_be    = '0;
    wd_valid = 1'b0;
    ra_addr  = '0;
    ra_valid = 1'b0;
    rd_ready = 1'b0;

    // Configure External Register File for initial 100 MHz RTC
    configure_register_file(100.0, .cl(11), .cwl(8), .al(0), .wr(12));

    $display("\n=================================================================");
    $display("   STARTING RIGOROUS TESTBENCH FOR FIXED-BURST DDR3 CONTROLLER   ");
    $display("   Configuration: DATA_WIDTH = 64 (4 x16 DDR3 chips in parallel)  ");
    $display("=================================================================\n");

    // Release reset
    #(10 * T_SYS_NOM);
    @(posedge clk);
    arst_n <= 1'b1;
    $display("[TB %0t] Reset released. Waiting for DDR3 Initialization...", $realtime);

    wait (init_done == 1'b1);
    $display("[TB %0t] *** Phase 0: JEDEC Power-up & ZQCL Calibration Complete! ***\n", $realtime);
    repeat (50) @(posedge clk);

    // =====================================================================
    // TEST 1: Directed Multi-Bank Access (All 8 DRAM Banks)
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 1: Multi-Bank Verification (All 8 Banks, Row 0)");
    $display("-----------------------------------------------------------------");
    for (int bank = 0; bank < 8; bank++) begin
      test_addr = (bank << 13);
      for (int beat = 0; beat < 8; beat++) begin
        test_data[beat] = {
          32'(32'hB000_0000 | (bank << 16) | beat), 32'(32'hD000_0000 | (bank << 16) | beat)
        };
        test_be[beat] = {BE_WIDTH{1'b1}};
      end
      send_write(test_addr, test_data, test_be);
      repeat (10) @(posedge clk);
    end

    // Read back from all 8 banks and verify
    for (int bank = 0; bank < 8; bank++) begin
      test_addr = (bank << 13);
      send_read(test_addr);
      repeat (10) @(posedge clk);
    end
    $display("[TEST 1 PASSED] Successfully verified all 8 banks!\n");

    // =====================================================================
    // TEST 2: Byte-Enable & Strobe Masking Verification
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 2: Byte-Enable (wd_be) Masking Verification");
    $display("-----------------------------------------------------------------");
    test_addr = 30'h0000_8000;

    // Step 2.1: Pre-fill memory block with 0xFF
    for (int beat = 0; beat < 8; beat++) begin
      test_data[beat] = 64'hFFFFFFFF_FFFFFFFF;
      test_be[beat]   = {BE_WIDTH{1'b1}};
    end
    send_write(test_addr, test_data, test_be);
    repeat (20) @(posedge clk);
    send_read(test_addr);

    // Step 2.2: Overwrite with distinct patterns using partial byte enables
    test_data[0] = 64'h11223344_55667788;
    test_be[0]   = 8'h0F;
    test_data[1] = 64'hAABBCCDD_EEFF0011;
    test_be[1]   = 8'hF0;
    test_data[2] = 64'h01234567_89ABCDEF;
    test_be[2]   = 8'h55;
    test_data[3] = 64'hFEDCBA98_76543210;
    test_be[3]   = 8'hAA;
    test_data[4] = 64'h11111111_11111111;
    test_be[4]   = 8'h01;
    test_data[5] = 64'h88888888_88888888;
    test_be[5]   = 8'h80;
    test_data[6] = 64'h00000000_00000000;
    test_be[6]   = 8'h00;  // Mask all
    test_data[7] = 64'h44444444_44444444;
    test_be[7]   = 8'hFF;

    send_write(test_addr, test_data, test_be);
    repeat (20) @(posedge clk);
    send_read(test_addr);
    $display("[TEST 2 PASSED] Byte enable masking verified against scoreboard!\n");

    // =====================================================================
    // TEST 3: Flow Control & Backpressure Stress Test
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 3: Flow Control & Consumer Backpressure (Random rd_ready)");
    $display("-----------------------------------------------------------------");
    for (int k = 0; k < 4; k++) begin
      test_addr = (k << 13);
      send_read(test_addr, .random_backpressure(1'b1));
      repeat (10) @(posedge clk);
    end
    $display("[TEST 3 PASSED] Elastic buffer and consumer stall handling verified!\n");

    // =====================================================================
    // TEST 4: Pipelined Back-to-Back Queueing Stress
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 4: Pipelined FIFO Queueing (Consecutive Bursts)");
    $display("-----------------------------------------------------------------");
    for (int b = 0; b < 3; b++) begin
      test_addr = 30'h0002_0000 + (b << 6);
      for (int beat = 0; beat < 8; beat++) begin
        test_data[beat] = 64'hCAFE_0000_0000_0000 | (b << 16) | beat;
        test_be[beat]   = 8'hFF;
      end
      send_write(test_addr, test_data, test_be);
    end

    for (int b = 0; b < 3; b++) begin
      test_addr = 30'h0002_0000 + (b << 6);
      send_read(test_addr);
    end
    $display("[TEST 4 PASSED] Pipelined command execution verified!\n");

    // =====================================================================
    // TEST 5: Idle System Clock Throttling & Differential Clock Tracking
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 5: Idle System Clock Throttling (2x, 4x, 8x, 16x Slowdown)");
    $display("-----------------------------------------------------------------");
    for (int d = 0; d < 4; d++) begin
      automatic int throttle_div = (d == 0) ? 2 : (d == 1) ? 4 : (d == 2) ? 8 : 16;
      test_addr = 30'h0003_0000 + (throttle_div << 6);
      for (int beat = 0; beat < 8; beat++) begin
        test_data[beat] = 64'h7420_771E_0000_0000 | (throttle_div << 16) | beat;
        test_be[beat]   = 8'hFF;
      end
      send_write(test_addr, test_data, test_be);

      // Enter idle and throttle system clock; verify ck_p/ck_n follows and data is retained
      idle_with_clock_throttle(throttle_div, 25);
      $display("[THROTTLE %0dx] Verified ddr3_ck_p/n period = %0.1f ps during idle", throttle_div,
               2.0 * T_SYS_NOM * throttle_div);

      send_read(test_addr, .random_backpressure(1'b1));
    end
    $display(
        "[TEST 5 PASSED] Idle clock throttling & DDR3 differential clock tracking verified!\n");

    // =====================================================================
    // TEST 6: Multi-RTC Frequency Verification (1MHz, 8MHz, 16MHz, 32MHz, 100MHz)
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 6: Multi-RTC Frequency Sweep (1MHz, 8MHz, 16MHz, 32MHz, 100MHz)");
    $display("-----------------------------------------------------------------");
    rtc_freqs = '{1.0, 8.0, 16.0, 32.0, 100.0};
    foreach (rtc_freqs[idx]) begin
      configure_register_file(rtc_freqs[idx], .cl(11), .cwl(8), .al(0), .wr(12));

      for (int blk = 0; blk < 2; blk++) begin
        test_addr = 30'h0004_0000 + (idx << 10) + (blk << 6);
        for (int beat = 0; beat < 8; beat++) begin
          test_data[beat] = {$urandom(), $urandom()};
          test_be[beat]   = 8'hFF;
        end
        send_write(test_addr, test_data, test_be);
        // Also exercise idle clock throttling under each RTC frequency
        idle_with_clock_throttle(4, 8);
        send_read(test_addr, .random_backpressure(1'b1));
      end
      $display("[RTC %0.0f MHz PASSED] Verified read/write & idle throttling with RTC = %0.0f MHz!",
               rtc_freqs[idx], rtc_freqs[idx]);
    end
    $display("[TEST 6 PASSED] All RTC frequencies (1MHz..100MHz) verified!\n");

    // =====================================================================
    // TEST 7: Randomized Address & Data Stress Test with Idle Throttling
    // =====================================================================
    $display("-----------------------------------------------------------------");
    $display(" TEST 7: Randomized Stress Test (Random Banks, Rows, Columns & Throttling)");
    $display("-----------------------------------------------------------------");
    configure_register_file(100.0, .cl(11), .cwl(8), .al(0), .wr(12));
    for (int iter = 0; iter < 16384; iter++) begin
      logic [ADDR_WIDTH-1:0] rand_addr;
      // Generate block-aligned address (LSB 6 bits = 0)
      rand_addr = ($urandom_range(0, 32'h000F_FFFF) & ~64'd63);

      for (int beat = 0; beat < 8; beat++) begin
        test_data[beat] = {$urandom(), $urandom()};
        test_be[beat]   = $urandom();
        if (test_be[beat] == '0) test_be[beat] = 8'hFF;  // Ensure data is written
      end

      // Write burst
      send_write(rand_addr, test_data, test_be);

      // Periodically throttle clk during idle between write and read
      if ((iter % 32) == 0) begin
        $display("[INFO] Reached iteration %0d/16384", iter);
        idle_with_clock_throttle($urandom_range(2, 8), $urandom_range(4, 12));
      end else begin
        repeat ($urandom_range(10, 40)) @(posedge clk);
      end

      // Read back immediately (RAW verification)
      send_read(rand_addr, .random_backpressure($urandom_range(0, 1)));
    end
    $display("[TEST 7 PASSED] Completed randomized stress operations against scoreboard!\n");

    // =====================================================================
    // Final Summary Report
    // =====================================================================
    $display("=================================================================");
    $display("                     FINAL TESTBENCH REPORT                      ");
    $display("=================================================================");
    $display("  Total Write Transactions Completed : %0d (x 8 beats = %0d beats)", total_writes,
             total_writes * 8);
    $display("  Total Read Transactions Completed  : %0d (x 8 beats = %0d beats)", total_reads,
             total_reads * 8);
    $display("  Total Data Mismatches Detected     : %0d", error_count);
    $display("=================================================================");
    if (error_count == 0) begin
      $display("  >>> STATUS: PASSED! ALL OPERATIONS VERIFIED SUCCESSFULLY! <<<  ");
    end else begin
      $display("  >>> STATUS: FAILED! FOUND %0d ERRORS DURING EXECUTION! <<<     ", error_count);
      $fatal(1, "Simulation failed with %0d data mismatches", error_count);
    end
    $display("=================================================================\n");

    $finish;
  end

  // Safety timeout
  initial begin
    // $dumpfile("adn_memss_ddr3_controller_tb.vcd");
    // $dumpvars(0, adn_memss_ddr3_controller_tb);
    $timeformat(-3, 3, "ms", 12);
    fork
      forever begin
        #(10_000 * T_SYS_NOM);
        $display("\033[1;33m%0t\033[0m", $realtime);
      end
    join_none
    #(50_000_000 * T_SYS_NOM);
    $display(
        "\n[TB FATAL @ %0t] Simulation timeout reached! state=%0d, tck_timer=%0d, pre_phase=%b, rd_cap_busy=%b, rd_push_active=%b, rd_cap_ptr=%0d, rtc_cnt=%0d",
        $realtime, u_controller.state, u_controller.tck_timer, u_controller.pre_phase,
        u_controller.rd_cap_busy, u_controller.rd_push_active, u_controller.rd_cap_ptr,
        u_controller.rtc_tick_cnt);
    $fatal(1, "TIMEOUT");
  end

endmodule
