`ifndef __GUARD_HOST_SCOREBOARD_SV__
`define __GUARD_HOST_SCOREBOARD_SV__ 0

import micron_ddr3_msg_pkg::msg_t;

class host_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(host_scoreboard)

  string GREEN  = "\033[32m";
  string RED    = "\033[31m";
  string YELLOW = "\033[33m";
  string CYAN   = "\033[36m";
  string RESET  = "\033[0m";

  uvm_analysis_imp #(host_seq_item, host_scoreboard) ap_imp;


  mailbox #(msg_t) dram_info_mbx;
  mailbox #(msg_t) dram_warning_mbx;
  mailbox #(msg_t) dram_error_mbx;

  // Golden sparse memory model indexed by byte address
  logic [7:0] mem_model [logic [ADDR_WIDTH-1:0]];

  int unsigned num_writes      = 0;
  int unsigned num_reads       = 0;
  int unsigned num_matches     = 0;
  int unsigned num_mismatches  = 0;
  int unsigned num_dram_errors = 0;
  int unsigned num_dram_warns  = 0;
  bit          expect_reads    = 1'b1;

  function new(string name = "host_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_imp = new("ap_imp", this);
    if (!uvm_config_db#(bit)::get(this, "", "expect_reads", expect_reads))
      expect_reads = 1'b1;
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
        #1step;

        if (!uvm_config_db #(mailbox #(msg_t))::get(this, "", "dram_info_mbx", dram_info_mbx))
          `uvm_fatal("SCB_MBX", "dram_info_mbx not found in uvm_config_db!")
        if (!uvm_config_db #(mailbox #(msg_t))::get(this, "", "dram_warning_mbx", dram_warning_mbx))
          `uvm_fatal("SCB_MBX", "dram_warning_mbx not found in uvm_config_db!")
        if (!uvm_config_db #(mailbox #(msg_t))::get(this, "", "dram_error_mbx", dram_error_mbx))
          `uvm_fatal("SCB_MBX", "dram_error_mbx not found in uvm_config_db!")

        fork

          forever begin
            msg_t err_msg;
            dram_error_mbx.get(err_msg);
            num_dram_errors++;
            $display("%s[DRAM_ERROR] @ %0t: %s%s", RED, err_msg.msg_time, err_msg.msg_body, RESET);
            `uvm_error("DRAM_MDL_ERR", $sformatf("[ID:%0d @ %0t] %s", err_msg.msg_id, err_msg.msg_time, err_msg.msg_body))
          end


          forever begin
            msg_t warn_msg;
            dram_warning_mbx.get(warn_msg);
            num_dram_warns++;
            $display("%s[DRAM_WARN] @ %0t: %s%s", YELLOW, warn_msg.msg_time, warn_msg.msg_body, RESET);
            `uvm_warning("DRAM_MDL_WARN", $sformatf("[ID:%0d @ %0t] %s", warn_msg.msg_id, warn_msg.msg_time, warn_msg.msg_body))
          end


          forever begin
            msg_t info_msg;
            dram_info_mbx.get(info_msg);
            if (uvm_is_match("*gen_ddr3_chips[0]*", info_msg.msg_body)) begin
              // $display("%s[DRAM_INFO] @ %0t: %s%s", CYAN, info_msg.msg_time, info_msg.msg_body, RESET);
            end
          end
        join_none
  endtask


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
    
    if (num_mismatches == 0 && num_dram_errors == 0 && num_reads > 0) begin
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
      " DRAM Mdl Warns   : %0d\n",
      " DRAM Mdl Errors  : %0d\n",
      "========================================\n"},
      num_writes, num_reads, num_matches, num_mismatches, num_dram_warns, num_dram_errors
    ), UVM_LOW)
    
    $display("%s", RESET);

    if (num_mismatches > 0)
      `uvm_error("SCB_FAIL", $sformatf("%0d read mismatches", num_mismatches))
    if (num_dram_errors > 0)
      `uvm_error("SCB_DRAM_FAIL", $sformatf("%0d Micron DDR3 model errors detected", num_dram_errors))
    if (expect_reads && num_reads == 0)
      `uvm_error("SCB_EMPTY", "No reads checked, test passed vacuously")
  endfunction

endclass

`endif
