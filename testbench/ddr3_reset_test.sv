import ddr3_params_pkg::*;

module ddr3_reset_test (
  input logic start,
  output logic done,
  ctrl_if u_ctrl_if,
  host_if u_host_if,
  cnfg_if u_cnfg_if,
  input logic idle,
  input logic ddr3_rst_n, ddr3_cke, ddr3_cs_n,
  input logic ddr3_ras_n, ddr3_cas_n, ddr3_we_n,
  input logic [DRAM_BA_BITS-1:0] ddr3_ba,
  input logic [DRAM_ADDR_BITS-1:0] ddr3_addr
);

localparam int BURST_BYTES = BE_WIDTH * BURST_LEN;
localparam int INIT_TIMEOUT_CYCLES = 1000000;

logic [7:0] reference_memory[longint unsigned];
logic [ADDR_WIDTH-1:0] written_addresses[$];
bit traffic_write_q[$];
logic [ADDR_WIDTH-1:0] traffic_addr_q[$];
int unsigned traffic_completed;

task automatic ddr3_reset_check_outputs(input string phase_name);
  if (u_cnfg_if.init_done !== 1'b0 || idle !== 1'b0 ||
      ddr3_rst_n !== 1'b0 || ddr3_cke !== 1'b0 ||
      ddr3_cs_n !== 1'b1 || u_host_if.wa_ready !== 1'b0 ||
      u_host_if.wd_ready !== 1'b0 || u_host_if.ra_ready !== 1'b0 ||
      u_host_if.rd_valid !== 1'b0) begin
    $fatal(1, "DDR3 Reset Test: reset output check failed during %s", phase_name);
  end
endtask

task automatic ddr3_reset_write_reference(
  input logic [ADDR_WIDTH-1:0] addr,
  input logic [DATA_WIDTH-1:0] data[BURST_LEN],
  input logic [BE_WIDTH-1:0] be[BURST_LEN]
);
  longint unsigned byte_addr;
  for (int beat = 0; beat < BURST_LEN; beat++) begin
    for (int lane = 0; lane < BE_WIDTH; lane++) begin
      byte_addr = addr + (beat * BE_WIDTH) + lane;
      if (be[beat][lane])
        reference_memory[byte_addr] = data[beat][lane*8 +: 8];
    end
  end
endtask

task automatic ddr3_reset_compare_read(
  input logic [ADDR_WIDTH-1:0] addr,
  input logic [DATA_WIDTH-1:0] observed[BURST_LEN]
);
  longint unsigned byte_addr;
  for (int beat = 0; beat < BURST_LEN; beat++) begin
    for (int lane = 0; lane < BE_WIDTH; lane++) begin
      byte_addr = addr + (beat * BE_WIDTH) + lane;
      if (!reference_memory.exists(byte_addr))
        $fatal(1, "DDR3 Reset Test: scoreboard has no expected byte at 0x%0h", byte_addr);
      if (observed[beat][lane*8 +: 8] !== reference_memory[byte_addr])
        $fatal(1, "DDR3 Reset Test: mismatch at 0x%0h (expected %h, got %h)",
               byte_addr, reference_memory[byte_addr], observed[beat][lane*8 +: 8]);
    end
  end
endtask

task automatic ddr3_reset_apply_cfg_and_wait_init;
  int cycles;

  cycles = 0;
  fork
    begin
      u_cnfg_if.apply_cfg();
    end
    begin
      // apply_cfg pulses init_do; wait for the controller to acknowledge it.
      wait (u_cnfg_if.init_done === 1'b0);
      while ((u_cnfg_if.init_done !== 1'b1) && (cycles < INIT_TIMEOUT_CYCLES)) begin
        @(posedge u_ctrl_if.clk);
        cycles++;
      end
    end
  join_any
  disable fork;

  if (u_cnfg_if.init_done !== 1'b1)
    $fatal(1, "DDR3 Reset Test: init_done timeout after %0d clocks", INIT_TIMEOUT_CYCLES);
endtask

task automatic ddr3_reset_write_read_check(input logic [ADDR_WIDTH-1:0] addr);
  logic [DATA_WIDTH-1:0] expected[BURST_LEN];
  logic [DATA_WIDTH-1:0] observed[BURST_LEN];
  logic [BE_WIDTH-1:0] be[BURST_LEN];

  foreach (expected[beat]) begin
    expected[beat] = {$urandom, $urandom};
    be[beat] = '1;
  end

  u_host_if.write(addr, expected, be);
  ddr3_reset_write_reference(addr, expected, be);
  u_host_if.read_req(addr);
  u_host_if.monitor_rd(observed);
  ddr3_reset_compare_read(addr, observed);
endtask

task automatic ddr3_reset_random_traffic(input int transaction_count = 40);
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] data[BURST_LEN];
  logic [DATA_WIDTH-1:0] observed[BURST_LEN];
  logic [BE_WIDTH-1:0] be[BURST_LEN];
  traffic_completed = 0;
  traffic_write_q.delete();
  traffic_addr_q.delete();
  written_addresses.delete();
  for (int tx = 0; tx < (transaction_count / 2); tx++) begin
    addr = $urandom;
    addr = (addr / BURST_BYTES) * BURST_BYTES;
    traffic_write_q.push_back(1'b1);
    traffic_addr_q.push_back(addr);
    traffic_write_q.push_back(1'b0);
    traffic_addr_q.push_back(addr);
  end

  while (traffic_write_q.size() != 0) begin
    if (traffic_write_q.pop_front()) begin
      addr = traffic_addr_q.pop_front();
      foreach (data[beat]) begin
        data[beat] = {$urandom, $urandom};
        be[beat] = '1;
      end
      u_host_if.write(addr, data, be);
      ddr3_reset_write_reference(addr, data, be);
      written_addresses.push_back(addr);
    end else begin
      addr = traffic_addr_q.pop_front();
      u_host_if.read_req(addr);
      u_host_if.monitor_rd(observed);
      ddr3_reset_compare_read(addr, observed);
    end
    traffic_completed++;
  end
endtask

task automatic ddr3_reset_run_random_traffic_then_reset(input int hold_cycles);
  traffic_completed = 0;
  fork
    begin : traffic_sequence
      ddr3_reset_random_traffic(40);
    end
    begin : asynchronous_reset
      wait (traffic_completed >= 1);
      repeat ($urandom_range(1, 20)) @(posedge u_ctrl_if.clk);
      #(1ps) u_ctrl_if.arst_n = 1'b0;
      u_host_if.reset_signals();
    end
  join_any
  disable fork;

  repeat (2) begin
    @(posedge u_ctrl_if.clk);
    ddr3_reset_check_outputs("asynchronous reset during randomized traffic");
  end
  repeat (hold_cycles) @(posedge u_ctrl_if.clk);

  // The direct test's scoreboard and pending transaction queues are reset here.
  reference_memory.delete();
  written_addresses.delete();
  traffic_write_q.delete();
  traffic_addr_q.delete();
  if (reference_memory.num() != 0 || written_addresses.size() != 0 ||
      traffic_write_q.size() != 0 || traffic_addr_q.size() != 0)
    $fatal(1, "DDR3 Reset Test: local scoreboard flush failed");
endtask

task automatic run_ddr3_reset_test;
  int reset_cycles[3] = '{2, 5, 20};
  bit command_seen;
  int reset_iter;
  logic [ADDR_WIDTH-1:0] address;

  $display("[DDR3 Reset Test] Starting");

  reference_memory.delete();
  written_addresses.delete();
  traffic_write_q.delete();
  traffic_addr_q.delete();

  // Steps 1-2: power-up reset widths and one extra RTC period.
  foreach (reset_cycles[i]) begin
    u_ctrl_if.arst_n = 1'b0;
    repeat (reset_cycles[i]) begin
      @(posedge u_ctrl_if.clk);
      ddr3_reset_check_outputs($sformatf("power-up reset, N=%0d", reset_cycles[i]));
    end
    @(posedge u_ctrl_if.rtc);
    ddr3_reset_check_outputs("extra RTC period");
    u_ctrl_if.arst_n = 1'b1;
    repeat (2) @(posedge u_ctrl_if.clk);
  end

  // Steps 3-4: released reset with no configuration must remain inactive.
  command_seen = 0;
  repeat (5000) begin
    @(posedge u_ctrl_if.clk);
    ddr3_reset_check_outputs("reset released without configuration");
    if ((ddr3_cs_n === 1'b0) &&
        ({ddr3_cs_n, ddr3_ras_n, ddr3_cas_n, ddr3_we_n} != 4'b0111))
      command_seen = 1;
    if (u_cnfg_if.init_done !== 1'b0 || ddr3_cke !== 1'b0 ||
        u_host_if.wa_ready !== 1'b0 || u_host_if.wd_ready !== 1'b0 ||
        u_host_if.ra_ready !== 1'b0)
      $fatal(1, "DDR3 Reset Test: controller active before apply_cfg");
  end
  if (command_seen)
    $fatal(1, "DDR3 Reset Test: DDR command issued before apply_cfg");

  // Steps 5-12: initialize, exercise traffic, asynchronously reset, recover,
  // and repeat with varying reset hold widths.
  for (reset_iter = 0; reset_iter < 20; reset_iter++) begin
    ddr3_reset_apply_cfg_and_wait_init();

    // Steps 6-9: run mixed traffic, asynchronously reset at a random point,
    // stop the driver, and clear the pending/reference scoreboard state.
    ddr3_reset_run_random_traffic_then_reset(reset_cycles[reset_iter % 3]);
    u_host_if.reset_signals();

    // Step 10: recover and verify the full mode-register sequence again.
    u_ctrl_if.arst_n = 1'b1;
    ddr3_reset_apply_cfg_and_wait_init();

    // Step 11: issue all eight writes first, then eight reads to fresh addresses.
    begin
      logic [DATA_WIDTH-1:0] expected_data[8][BURST_LEN];
      logic [DATA_WIDTH-1:0] observed_data[BURST_LEN];
      logic [BE_WIDTH-1:0] be[BURST_LEN];
      logic [ADDR_WIDTH-1:0] fresh_addresses[8];

      foreach (be[beat]) be[beat] = '1;
      for (int tx = 0; tx < 8; tx++) begin
        fresh_addresses[tx] = 30'h80000 + (reset_iter * 32'h1000) + (tx * 64);
        for (int beat = 0; beat < BURST_LEN; beat++)
          expected_data[tx][beat] = {$urandom, $urandom};
        u_host_if.write(fresh_addresses[tx], expected_data[tx], be);
        ddr3_reset_write_reference(fresh_addresses[tx], expected_data[tx], be);
      end
      for (int tx = 0; tx < 8; tx++) begin
        u_host_if.read_req(fresh_addresses[tx]);
        u_host_if.monitor_rd(observed_data);
        ddr3_reset_compare_read(fresh_addresses[tx], observed_data);
      end
    end
    wait (idle === 1'b1);
  end

  // Step 13: channel idle check. Micron-model diagnostics are emitted by its model.
  if (u_host_if.wa_valid || u_host_if.wd_valid ||
      u_host_if.ra_valid || u_host_if.rd_valid ||
      traffic_write_q.size() != 0 || traffic_addr_q.size() != 0)
    $fatal(1, "DDR3 Reset Test: host channels active at end of test");
  $display("[DDR3 Reset Test] PASS");
endtask

initial begin
  done = 1'b0;
  wait (start === 1'b1);
  u_cnfg_if.reset_cfg();
  u_host_if.reset_signals();
  run_ddr3_reset_test();
  done = 1'b1;
end

endmodule
