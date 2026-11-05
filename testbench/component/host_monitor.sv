`ifndef __GUARD_HOST_MONITOR_SV__
`define __GUARD_HOST_MONITOR_SV__ 0

`include "obj/host_seq_item.sv"

class host_monitor extends uvm_monitor;
  `uvm_component_utils(host_monitor)

  virtual host_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .BE_WIDTH   (BE_WIDTH),
    .BURST_LEN  (BURST_LEN)
  ) host_vif;

  uvm_analysis_port #(host_seq_item) ap;

  function new(string name = "host_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction


  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (!uvm_config_db #(virtual host_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH),
      .BE_WIDTH   (BE_WIDTH),
      .BURST_LEN  (BURST_LEN)
    ))::get(this, "", "host_vif", host_vif)) begin
      `uvm_fatal("NOVIF", "host_vif was not configured for host_monitor")
    end
  endfunction

  task run_phase(uvm_phase phase);
    host_seq_item item;

    wait (host_vif.arst_n === 1'b1);

    forever begin
      // Create a single item for the current transaction
      item = host_seq_item::type_id::create("item");

      fork
        // Branch 1: Wait for a Write transaction
        begin
          fork
            host_vif.monitor_wa(item.addr);
            host_vif.monitor_wd(item.data, item.be);
          join
          item.tr_type = 1'b1; // HOST_WRITE
        end

        // Branch 2: Wait for a Read transaction
        begin
          fork
            host_vif.monitor_ra(item.addr);
            host_vif.monitor_rd(item.data);
          join
          item.tr_type = 1'b0; // HOST_READ
        end
      join_any
      disable fork; // Kill the unused branch once Write or Read completes

      // Send the single captured item to the scoreboard
      ap.write(item);
    end
  endtask

endclass

`endif