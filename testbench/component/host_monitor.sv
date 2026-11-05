`ifndef __GUARD_HOST_MONITOR_SV__
`define __GUARD_HOST_MONITOR_SV__

class host_monitor extends uvm_monitor;
  `uvm_component_utils(host_monitor)

  localparam int BURST_BYTES = BE_WIDTH * BURST_LEN;

  virtual host_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .BE_WIDTH   (BE_WIDTH),
    .BURST_LEN  (BURST_LEN)
  ) host_vif;

  uvm_analysis_port #(host_seq_item) ap;

  logic [ADDR_WIDTH-1:0] pending_write_addresses[$];
  host_seq_item pending_write_data[$];
  logic [ADDR_WIDTH-1:0] pending_read_addresses[$];
  host_seq_item pending_read_data[$];

  host_seq_item active_write_data;
  host_seq_item active_read_data;
  int unsigned write_beat_count;
  int unsigned read_beat_count;

  bit previous_wa_stalled;
  logic [ADDR_WIDTH-1:0] previous_wa_addr;
  bit previous_wd_stalled;
  logic [DATA_WIDTH-1:0] previous_wd_data;
  logic [BE_WIDTH-1:0] previous_wd_be;
  bit previous_ra_stalled;
  logic [ADDR_WIDTH-1:0] previous_ra_addr;
  bit previous_rd_stalled;
  logic [DATA_WIDTH-1:0] previous_rd_data;

  function new(string name = "host_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(virtual host_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH),
      .BE_WIDTH   (BE_WIDTH),
      .BURST_LEN  (BURST_LEN)
    ))::get(this, "", "host_vif", host_vif)) begin
      `uvm_fatal("NOVIF", "host_vif was not configured for host_monitor")
    end
  endfunction

  function void clear_pending();
    pending_write_addresses.delete();
    pending_write_data.delete();
    pending_read_addresses.delete();
    pending_read_data.delete();
    active_write_data = null;
    active_read_data = null;
    write_beat_count = 0;
    read_beat_count = 0;
    previous_wa_stalled = 0;
    previous_wd_stalled = 0;
    previous_ra_stalled = 0;
    previous_rd_stalled = 0;
  endfunction

  function void publish_completed_transactions();
    host_seq_item write_data_item;
    host_seq_item read_data_item;
    host_seq_item completed_item;

    while ((pending_write_addresses.size() != 0) &&
           (pending_write_data.size() != 0)) begin
      write_data_item = pending_write_data.pop_front();
      completed_item = host_seq_item::type_id::create("completed_write", this);
      completed_item.tr_type = HOST_WRITE;
      completed_item.addr = pending_write_addresses.pop_front();
      completed_item.data = write_data_item.data;
      completed_item.be = write_data_item.be;
      ap.write(completed_item);
    end

    while ((pending_read_addresses.size() != 0) &&
           (pending_read_data.size() != 0)) begin
      read_data_item = pending_read_data.pop_front();
      completed_item = host_seq_item::type_id::create("completed_read", this);
      completed_item.tr_type = HOST_READ;
      completed_item.addr = pending_read_addresses.pop_front();
      completed_item.data = read_data_item.data;
      ap.write(completed_item);
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if ((pending_write_addresses.size() != 0) ||
        (pending_write_data.size() != 0) ||
        (pending_read_addresses.size() != 0) ||
        (pending_read_data.size() != 0) ||
        (active_write_data != null) ||
        (active_read_data != null)) begin
      `uvm_error("INCOMPLETE_TRANSACTION", $sformatf(
        "Unmatched host traffic at end of test: WA=%0d WD=%0d RA=%0d RD=%0d write_beats=%0d read_beats=%0d",
        pending_write_addresses.size(), pending_write_data.size(),
        pending_read_addresses.size(), pending_read_data.size(),
        write_beat_count, read_beat_count
      ))
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge host_vif.clk);

      if (host_vif.arst_n !== 1'b1) begin
        clear_pending();
        continue;
      end

      if ($isunknown({
        host_vif.wa_valid, host_vif.wa_ready,
        host_vif.wd_valid, host_vif.wd_ready,
        host_vif.ra_valid, host_vif.ra_ready,
        host_vif.rd_valid, host_vif.rd_ready
      })) begin
        `uvm_error("HOST_CONTROL_X", "Unknown value on a host ready/valid control signal")
      end

      if (previous_wa_stalled &&
          ((host_vif.wa_valid !== 1'b1) || (host_vif.wa_addr !== previous_wa_addr))) begin
        `uvm_error("HOST_PROTOCOL", "Write address changed before its ready/valid handshake")
      end
      if (previous_wd_stalled &&
          ((host_vif.wd_valid !== 1'b1) ||
           (host_vif.wd_data !== previous_wd_data) ||
           (host_vif.wd_be !== previous_wd_be))) begin
        `uvm_error("HOST_PROTOCOL", "Write data changed before its ready/valid handshake")
      end
      if (previous_ra_stalled &&
          ((host_vif.ra_valid !== 1'b1) || (host_vif.ra_addr !== previous_ra_addr))) begin
        `uvm_error("HOST_PROTOCOL", "Read address changed before its ready/valid handshake")
      end
      if (previous_rd_stalled &&
          ((host_vif.rd_valid !== 1'b1) || (host_vif.rd_data !== previous_rd_data))) begin
        `uvm_error("HOST_PROTOCOL", "Read data changed before its ready/valid handshake")
      end

      previous_wa_stalled = (host_vif.wa_valid === 1'b1) && (host_vif.wa_ready === 1'b0);
      previous_wa_addr = host_vif.wa_addr;
      previous_wd_stalled = (host_vif.wd_valid === 1'b1) && (host_vif.wd_ready === 1'b0);
      previous_wd_data = host_vif.wd_data;
      previous_wd_be = host_vif.wd_be;
      previous_ra_stalled = (host_vif.ra_valid === 1'b1) && (host_vif.ra_ready === 1'b0);
      previous_ra_addr = host_vif.ra_addr;
      previous_rd_stalled = (host_vif.rd_valid === 1'b1) && (host_vif.rd_ready === 1'b0);
      previous_rd_data = host_vif.rd_data;

      if ((host_vif.wa_valid === 1'b1) && (host_vif.wa_ready === 1'b1)) begin
        if ((host_vif.wa_addr % BURST_BYTES) != 0) begin
          `uvm_error("HOST_ALIGNMENT", $sformatf(
            "Observed unaligned write address 0x%0h", host_vif.wa_addr
          ))
        end
        pending_write_addresses.push_back(host_vif.wa_addr);
      end

      if ((host_vif.wd_valid === 1'b1) && (host_vif.wd_ready === 1'b1)) begin
        if (active_write_data == null) begin
          active_write_data = host_seq_item::type_id::create("observed_write_data", this);
          active_write_data.tr_type = HOST_WRITE;
        end
        active_write_data.data[write_beat_count] = host_vif.wd_data;
        active_write_data.be[write_beat_count] = host_vif.wd_be;
        write_beat_count++;
        if (write_beat_count == BURST_LEN) begin
          pending_write_data.push_back(active_write_data);
          active_write_data = null;
          write_beat_count = 0;
        end
      end

      if ((host_vif.ra_valid === 1'b1) && (host_vif.ra_ready === 1'b1)) begin
        if ((host_vif.ra_addr % BURST_BYTES) != 0) begin
          `uvm_error("HOST_ALIGNMENT", $sformatf(
            "Observed unaligned read address 0x%0h", host_vif.ra_addr
          ))
        end
        pending_read_addresses.push_back(host_vif.ra_addr);
      end

      if ((host_vif.rd_valid === 1'b1) && (host_vif.rd_ready === 1'b1)) begin
        if (active_read_data == null) begin
          active_read_data = host_seq_item::type_id::create("observed_read_data", this);
          active_read_data.tr_type = HOST_READ;
        end
        active_read_data.data[read_beat_count] = host_vif.rd_data;
        read_beat_count++;
        if (read_beat_count == BURST_LEN) begin
          pending_read_data.push_back(active_read_data);
          active_read_data = null;
          read_beat_count = 0;
        end
      end

      publish_completed_transactions();
    end
  endtask
endclass

`endif