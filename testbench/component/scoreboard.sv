`ifndef __GUARD_HOST_SCOREBOARD_SV__
`define __GUARD_HOST_SCOREBOARD_SV__ 0

class host_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(host_scoreboard)

  // ANSI Color Codes for Terminal Output
  string GREEN = "\033[32m";
  string RED   = "\033[31m";
  string RESET = "\033[0m";

  // Analysis implementation port to receive transactions from host_monitor
  uvm_analysis_imp #(host_seq_item, host_scoreboard) ap_imp;

  // Golden sparse memory model indexed by byte address
  logic [7:0] mem_model [logic [ADDR_WIDTH-1:0]];

  // Verification statistics counters
  int unsigned num_writes      = 0;
  int unsigned num_reads       = 0;
  int unsigned num_matches     = 0;
  int unsigned num_mismatches  = 0;
  bit          expect_reads    = 1'b1;

  function new(string name = "host_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(bit)::get(this, "", "expect_reads", expect_reads))
      expect_reads = 1'b1;
  endfunction

  // Automatically triggered when host_monitor calls ap.write(item)
  virtual function void write(host_seq_item item);
    case (item.tr_type)
      1'b1: process_write(item);
      1'b0: process_read(item);
      default: `uvm_error("SCB", "Unsupported transaction type received")
    endcase
  endfunction


// Update golden memory model on HOST_WRITE respecting byte-enables (wd_be)
  protected function void process_write(host_seq_item item);
    logic [ADDR_WIDTH-1:0] aligned_addr;
    logic [ADDR_WIDTH-1:0] byte_addr;

    aligned_addr = {item.addr[ADDR_WIDTH-1:6], 6'b000000};

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      for (int b = 0; b < BE_WIDTH; b++) begin
        byte_addr = aligned_addr + (beat * BE_WIDTH) + b;
        if (item.be[beat][b] === 1'b1) begin
          mem_model[byte_addr] = item.data[beat][b*8 +: 8];
        end
      end
    end

    num_writes++;
    $display("%s[PASS] [SCB_WR] Stored 8-beat WRITE at Addr=0x%08h (Aligned=0x%08h)%s",
                 GREEN, item.addr, aligned_addr, RESET);
  endfunction

  // Compare incoming HOST_READ burst against golden memory model
  protected function void process_read(host_seq_item item);
    logic [ADDR_WIDTH-1:0] aligned_addr;
    logic [ADDR_WIDTH-1:0] byte_addr;
    logic [DATA_WIDTH-1:0] exp_data;
    bit                    burst_ok = 1'b1;

    num_reads++;
    aligned_addr = {item.addr[ADDR_WIDTH-1:6], 6'b000000};

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      exp_data = '0;

      for (int b = 0; b < BE_WIDTH; b++) begin
        byte_addr = aligned_addr + (beat * BE_WIDTH) + b;
        if (mem_model.exists(byte_addr)) begin
          exp_data[b*8 +: 8] = mem_model[byte_addr];
        end else begin
          exp_data[b*8 +: 8] = item.data[beat][b*8 +: 8];
        end
      end

      if (item.data[beat] !== exp_data) begin
        $display("%s[FAIL] [SCB_MISMATCH] Addr=0x%08h Beat=%0d | Expected=0x%016h, Actual=0x%016h%s",
          RED, item.addr, beat, exp_data, item.data[beat], RESET
        );
        burst_ok = 1'b0;
      end
    end

    if (burst_ok) begin
      num_matches++;
      $display("%s[PASS] [SCB_MATCH] Verified 8-beat READ at Addr=0x%08h%s", GREEN, item.addr, RESET);
    end else begin
      num_mismatches++;
    end
  endfunction

  // Print final verification summary at the end of simulation
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    
    if (num_mismatches == 0 && num_reads > 0) begin
      $display("%s", GREEN);
    end else begin
      $display("%s", RED);
    end

    `uvm_info("SCB_SUMMARY", $sformatf({
      "\n========================================\n",
      "        DDR3 SCOREBOARD SUMMARY         \n",
      "========================================\n",
      " Total Writes     : %0d\n",
      " Total Reads      : %0d\n",
      " Read Matches     : %0d\n",
      " Read Mismatches  : %0d\n",
      "========================================\n"},
      num_writes, num_reads, num_matches, num_mismatches
    ), UVM_LOW)
    
    $display("%s", RESET);

    if (num_mismatches > 0)
      `uvm_error("SCB_FAIL", $sformatf("%0d read mismatches", num_mismatches))
    if (expect_reads && num_reads == 0)
      `uvm_error("SCB_EMPTY", "No reads checked, test passed vacuously")
  endfunction

endclass

`endif
