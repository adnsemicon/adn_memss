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

  bit internal_clk = 1'b0;
  bit clk_en       = 1'b0;  // Starts disabled; enabled after reset via start_clock()

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Sequentials
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // 1. System Clock (clk) Internal Oscillator
  always begin
    realtime tp_local;
    tp_local = tp;
    #(tp_local / 2.0);
    internal_clk <= 1'b1;
    #(tp_local / 2.0);
    internal_clk <= 1'b0;
  end

  // Glitch-free gating for System Clock (clk stays 0 until clk_en = 1)
  always begin
    @(posedge internal_clk);
    clk <= clk_en;
    @(negedge internal_clk);
    clk <= 1'b0;
  end

  // 2. Real-Time Clock (rtc) Generator — Free-running right from 0ns!
  initial begin
    rtc = 1'b0;
    forever begin
      realtime rtc_tp_local;
      rtc_tp_local = rtc_tp;
      #(rtc_tp_local / 2.0);
      rtc <= 1'b1;
      #(rtc_tp_local / 2.0);
      rtc <= 1'b0;
    end
  end

  //////////////////////////////////////////////////////////////////////////////////////////////////
  // Methods
  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Enable / Disable System Clock
  function void set_clk_en(input bit en = 1'b1);
    clk_en = en;
  endfunction

  // Dynamically change System Clock frequency on-the-fly
  function void set_clk_freq(input real freq);
    tp = 1s / freq;
  endfunction

  // Start System Clock (Call after reset in configure_phase)
  task automatic start_clock(input real freq = 1_538_461_538.0);
    tp = 1s / freq;
    set_clk_en(1'b1);
    @(posedge clk);
  endtask

  // Asynchronous Reset Control
  task automatic apply_reset(input realtime duration   = 100ns,
                             input realtime pre_delay  = duration / 10.0,
                             input realtime post_delay = pre_delay);
    arst_n <= 1'b1;
    #(pre_delay);
    arst_n <= 1'b0;
    #(duration);
    arst_n <= 1'b1;
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