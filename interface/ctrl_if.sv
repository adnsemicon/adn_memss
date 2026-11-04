interface ctrl_if;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Signals
  //////////////////////////////////////////////////////////////////////////////////////////////////

  logic arst_n;
  logic clk;
  logic rtc;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Variables
  //////////////////////////////////////////////////////////////////////////////////////////////////

  realtime tp     = 650ps;  // Default System Clock period (~1.54 GHz -> DDR3-1600)
  realtime rtc_tp = 10ns;   // Default Real-Time Clock period (100 MHz)

  bit internal_clk;
  bit clk_en;

  bit internal_rtc;
  bit rtc_en;

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Sequentials
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // System Clock (clk) Generator
  always begin
    realtime tp_local;
    tp_local = tp;
    #(tp_local / 2.0);
    internal_clk <= '1;
    #(tp_local / 2.0);
    internal_clk <= '0;
  end

  always begin
    @(posedge internal_clk);
    clk <= clk_en;
    @(negedge internal_clk);
    clk <= '0;
  end

  // Real-Time Clock (rtc) Generator
  always begin
    realtime rtc_tp_local;
    rtc_tp_local = rtc_tp;
    #(rtc_tp_local / 2.0);
    internal_rtc <= '1;
    #(rtc_tp_local / 2.0);
    internal_rtc <= '0;
  end

  always begin
    @(posedge internal_rtc);
    rtc <= rtc_en;
    @(negedge internal_rtc);
    rtc <= '0;
  end

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Methods
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Enable / Disable Clocks (Glitch-free gating)
  function void set_clk_en(input bit en = 1);
    clk_en = en;
  endfunction

  function void set_rtc_en(input bit en = 1);
    rtc_en = en;
  endfunction

  // Dynamically change System Clock frequency on-the-fly (for Idle Clock Throttling test)
  function void set_clk_freq(input real freq);
    tp = 1s / freq;
  endfunction

  // Start System Clock (Default: 1.538 GHz -> 650ps period)
  task automatic start_clock(input real freq = 1_538_461_538.0);
    tp = 1s / freq;
    set_clk_en('1);
    @(posedge clk);
  endtask

  // Start Real-Time Clock (Default: 100 MHz -> 10ns period)
  task automatic start_rtc(input real freq = 100_000_000.0);
    rtc_tp = 1s / freq;
    set_rtc_en('1);
    @(posedge rtc);
  endtask

  // Start both clk and rtc concurrently
  task automatic start_all_clocks(input real sys_freq = 1_538_461_538.0,
                                  input real rtc_freq = 100_000_000.0);
    fork
      start_clock(sys_freq);
      start_rtc(rtc_freq);
    join
  endtask

  // Asynchronous Reset Control
  task automatic apply_reset(input realtime duration   = 100ns,
                             input realtime pre_delay  = duration / 10.0,
                             input realtime post_delay = pre_delay);
    arst_n <= '1;
    #(pre_delay);
    arst_n <= '0;
    #(duration);
    arst_n <= '1;
    #(post_delay);
  endtask

  // Wait Helper Tasks
  task automatic wait_clks(input int n = 1);
    repeat (n) @(posedge clk);
  endtask

  task automatic wait_rtc_ticks(input int n = 1);
    repeat (n) @(posedge rtc);
  endtask

endinterface
