`ifndef __GUARD_DDR3_FUNCTIONAL_COVERAGE_SV__
`define __GUARD_DDR3_FUNCTIONAL_COVERAGE_SV__ 0

// Host-transaction functional coverage.
// Receives completed transactions from host_monitor through host_agent.ap.
class ddr3_coverage extends uvm_subscriber #(host_seq_item);
  `uvm_component_utils(ddr3_coverage)

  int unsigned write_samples;
  int unsigned read_samples;

  covergroup host_transaction_cg with function sample(
    bit tr_type,
    logic [ADDR_WIDTH-1:0] addr,
    int unsigned be_mode,
    bit backpressure
  );
    option.per_instance = 1;

    cp_operation : coverpoint tr_type {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    // The controller maps addresses to 64-byte blocks.
    cp_alignment : coverpoint addr[5:0] {
      bins block_aligned = {6'd0};
      bins unaligned     = {[6'd1:6'd63]};
    }

    // 0 = no byte lanes enabled, 1 = partial, 2 = all enabled.
    cp_byte_enable : coverpoint be_mode {
      bins none    = {0};
      bins partial = {1};
      bins full    = {2};
    }

    cp_backpressure : coverpoint backpressure {
      bins no_stall = {0};
      bins stalled  = {1};
    }

    cp_operation_x_backpressure :
      cross cp_operation, cp_backpressure;

    cp_write_x_byte_enable :
      cross cp_operation, cp_byte_enable {
        // Byte enables are meaningful for writes; read items do not use them.
        ignore_bins read_byte_enable =
          binsof(cp_operation.read);
      }
  endgroup

  function new(string name = "ddr3_coverage", uvm_component parent = null);
    super.new(name, parent);
    host_transaction_cg = new();
    write_samples = 0;
    read_samples  = 0;
  endfunction

  // uvm_subscriber requires this implementation.
  virtual function void write(host_seq_item item);
    int unsigned enabled_count;
    int unsigned be_mode;
    bit bp;

    if (item == null) begin
      `uvm_error("COV_NULL", "Received a null host_seq_item")
      return;
    end

    enabled_count = 0;
    for (int beat = 0; beat < BURST_LEN; beat++) begin
      for (int lane = 0; lane < BE_WIDTH; lane++) begin
        if (item.be[beat][lane] === 1'b1)
          enabled_count++;
      end
    end

    if (enabled_count == 0)
      be_mode = 0;
    else if (enabled_count == (BURST_LEN * BE_WIDTH))
      be_mode = 2;
    else
      be_mode = 1;

    bp = item.tr_type ? item.wr_back_pressure : item.rd_back_pressure;

    host_transaction_cg.sample(item.tr_type, item.addr, be_mode, bp);

    if (item.tr_type)
      write_samples++;
    else
      read_samples++;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("DDR3_COVERAGE",
      $sformatf({"Host functional coverage = %0.2f%%\n",
                 "Completed writes sampled = %0d\n",
                 "Completed reads sampled  = %0d"},
        host_transaction_cg.get_inst_coverage(),
        write_samples, read_samples), UVM_LOW)
  endfunction
endclass

`endif
