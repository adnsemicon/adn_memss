`ifndef __GUARD_HOST_SCOREBOARD_SV__
`define __GUARD_HOST_SCOREBOARD_SV__ 0

class host_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(host_scoreboard)

  // Analysis implementation port to receive transactions from host_monitor
  uvm_analysis_imp #(host_seq_item, host_scoreboard) ap_imp;

  // Golden sparse memory model indexed by byte address
  logic [7:0] mem_model [logic [ADDR_WIDTH-1:0]];

  // Verification statistics counters
  int unsigned num_writes      = 0;
  int unsigned num_reads       = 0;
  int unsigned num_matches     = 0;
  int unsigned num_mismatches  = 0;

  function new(string name = "host_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  // Automatically triggered when host_monitor calls ap.write(item)
  virtual function void write(host_seq_item item);
    case (item.tr_type)
      1'b1: process_write(item);
      1'b0:  process_read(item);
      default:    `uvm_error("SCB", "Unsupported transaction type received")
    endcase
  endfunction

  // Update golden memory model on HOST_WRITE respecting byte-enables (wd_be)
  protected function void process_write(host_seq_item item);
    logic [ADDR_WIDTH-1:0] byte_addr;

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      for (int b = 0; b < BE_WIDTH; b++) begin
        byte_addr = item.addr + (beat * BE_WIDTH) + b;
        if (item.be[beat][b] === 1'b1) begin
          mem_model[byte_addr] = item.data[beat][b*8 +: 8];
        end
      end
    end

    num_writes++;
    `uvm_info("SCB_WR", $sformatf("Stored 8-beat WRITE at Addr=0x%08h", item.addr), UVM_MEDIUM)
  endfunction

  // Compare incoming HOST_READ burst against golden memory model
  protected function void process_read(host_seq_item item);
    logic [ADDR_WIDTH-1:0] byte_addr;
    logic [DATA_WIDTH-1:0] exp_data;
    bit                    burst_ok = 1'b1;

    num_reads++;

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      exp_data = '0;

      // Reconstruct expected 64-bit word from byte-addressable golden memory
      for (int b = 0; b < BE_WIDTH; b++) begin
        byte_addr = item.addr + (beat * BE_WIDTH) + b;
        if (mem_model.exists(byte_addr)) begin
          exp_data[b*8 +: 8] = mem_model[byte_addr];
        end else begin
          exp_data[b*8 +: 8] = 8'h00; // Default uninitialized bytes to 0x00
        end
      end

      if (item.data[beat] !== exp_data) begin
        `uvm_error("SCB_MISMATCH", $sformatf(
          "Addr=0x%08h Beat=%0d | Expected=0x%016h, Actual=0x%016h",
          item.addr, beat, exp_data, item.data[beat]
        ))
        burst_ok = 1'b0;
      end
    end

    if (burst_ok) begin
      num_matches++;
      `uvm_info("SCB_MATCH", $sformatf("Verified 8-beat READ at Addr=0x%08h", item.addr), UVM_MEDIUM)
    end else begin
      num_mismatches++;
    end
  endfunction

  // Print final verification summary at the end of simulation
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf(
      "\n========================================\n" ,
      "       DDR3 SCOREBOARD SUMMARY          \n" ,
      "========================================\n" ,
      " Total Writes     : %0d\n"                  ,
      " Total Reads      : %0d\n"                  ,
      " Read Matches     : %0d\n"                  ,
      " Read Mismatches  : %0d\n"                  ,
      "========================================\n" ,
      num_writes, num_reads, num_matches, num_mismatches
    ), UVM_LOW)

    if (num_mismatches > 0) begin
      `uvm_fatal("SCB_FAIL", $sformatf("Test FAILED with %0d read mismatches!", num_mismatches))
    end
  endfunction

endclass

`endif
