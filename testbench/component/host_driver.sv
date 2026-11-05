`ifndef __GUARD_HOST_DRIVER_SV__
`define __GUARD_HOST_DRIVER_SV__

class host_driver extends uvm_driver #(host_seq_item);
  `uvm_component_utils(host_driver)

  localparam int BURST_BYTES = BE_WIDTH * BURST_LEN;
  localparam int DEFAULT_MAX_WAIT_CYCLES = 10000;

  virtual host_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .BE_WIDTH   (BE_WIDTH),
    .BURST_LEN  (BURST_LEN)
  ) host_vif;

  virtual cnfg_if #(.DRAM_ADDR_BITS(DRAM_ADDR_BITS)) cnfg_vif;

  int unsigned max_wait_cycles = DEFAULT_MAX_WAIT_CYCLES;

  function new(string name = "host_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual host_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH),
      .BE_WIDTH   (BE_WIDTH),
      .BURST_LEN  (BURST_LEN)
    ))::get(this, "", "host_vif", host_vif)) begin
      `uvm_fatal("NOVIF", "host_vif was not configured for host_driver")
    end

    if (!uvm_config_db #(virtual cnfg_if #(
      .DRAM_ADDR_BITS(DRAM_ADDR_BITS)
    ))::get(this, "", "cnfg_vif", cnfg_vif)) begin
      `uvm_fatal("NOVIF", "cnfg_vif was not configured for host_driver")
    end

    void'(uvm_config_db #(int unsigned)::get(
      this, "", "max_wait_cycles", max_wait_cycles
    ));

    if (max_wait_cycles == 0) begin
      `uvm_fatal("BADCFG", "max_wait_cycles must be greater than zero")
    end
  endfunction

  task automatic wait_for_controller_ready();
    wait (host_vif.arst_n === 1'b1);
    wait (cnfg_vif.init_done === 1'b1);
  endtask

  task automatic drive_write_address(input bit [ADDR_WIDTH-1:0] addr);
    int unsigned wait_cycles;

    @(negedge host_vif.clk);
    host_vif.wa_addr  <= addr;
    host_vif.wa_valid <= 1'b1;

    wait_cycles = 0;
    do begin
      @(posedge host_vif.clk);
      if (host_vif.arst_n !== 1'b1) begin
        `uvm_fatal("RESET", "Reset asserted while write address was pending")
      end
      wait_cycles++;
      if (wait_cycles > max_wait_cycles) begin
        `uvm_fatal("TIMEOUT", "Timed out waiting for wa_ready")
      end
    end while (host_vif.wa_ready !== 1'b1);

    @(negedge host_vif.clk);
    host_vif.wa_valid <= 1'b0;
  endtask

  task automatic drive_write_data(input host_seq_item item);
    int unsigned wait_cycles;

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      @(negedge host_vif.clk);
      host_vif.wd_data  <= item.data[beat];
      host_vif.wd_be    <= item.be[beat];
      host_vif.wd_valid <= 1'b1;

      wait_cycles = 0;
      do begin
        @(posedge host_vif.clk);
        if (host_vif.arst_n !== 1'b1) begin
          `uvm_fatal("RESET", "Reset asserted while write data was pending")
        end
        wait_cycles++;
        if (wait_cycles > max_wait_cycles) begin
          `uvm_fatal("TIMEOUT", $sformatf("Timed out waiting for wd_ready on beat %0d", beat))
        end
      end while (host_vif.wd_ready !== 1'b1);
    end

    @(negedge host_vif.clk);
    host_vif.wd_valid <= 1'b0;
  endtask

  task automatic drive_read_address(input bit [ADDR_WIDTH-1:0] addr);
    int unsigned wait_cycles;

    @(negedge host_vif.clk);
    host_vif.ra_addr  <= addr;
    host_vif.ra_valid <= 1'b1;

    wait_cycles = 0;
    do begin
      @(posedge host_vif.clk);
      if (host_vif.arst_n !== 1'b1) begin
        `uvm_fatal("RESET", "Reset asserted while read address was pending")
      end
      wait_cycles++;
      if (wait_cycles > max_wait_cycles) begin
        `uvm_fatal("TIMEOUT", "Timed out waiting for ra_ready")
      end
    end while (host_vif.ra_ready !== 1'b1);

    @(negedge host_vif.clk);
    host_vif.ra_valid <= 1'b0;
  endtask

  task automatic wait_for_read_response();
    int unsigned wait_cycles;

    for (int beat = 0; beat < BURST_LEN; beat++) begin
      wait_cycles = 0;
      do begin
        @(posedge host_vif.clk);
        if (host_vif.arst_n !== 1'b1) begin
          `uvm_fatal("RESET", "Reset asserted while read data was pending")
        end
        wait_cycles++;
        if (wait_cycles > max_wait_cycles) begin
          `uvm_fatal("TIMEOUT", $sformatf(
            "Timed out waiting for read data beat %0d", beat
          ))
        end
      end while (!((host_vif.rd_valid === 1'b1) &&
                   (host_vif.rd_ready === 1'b1)));
    end
  endtask

  task run_phase(uvm_phase phase);
    host_seq_item item;

    host_vif.reset_signals();
    wait_for_controller_ready();

    forever begin
      seq_item_port.get_next_item(item);
      wait_for_controller_ready();

      if ((item.addr % BURST_BYTES) != 0) begin
        `uvm_fatal("ALIGN", $sformatf(
          "Host address 0x%0h is not aligned to the %0d-byte burst size",
          item.addr, BURST_BYTES
        ))
      end

      case (item.tr_type)
        HOST_WRITE: begin
          fork
            drive_write_address(item.addr);
            drive_write_data(item);
          join
        end

        HOST_READ: begin
          drive_read_address(item.addr);
          wait_for_read_response();
        end

        default: `uvm_fatal("BADTYPE", "Unsupported host transaction type")
      endcase

      seq_item_port.item_done();
    end
  endtask
endclass

`endif