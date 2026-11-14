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

    // Queues to track decoupled Write and Read channels independently
    logic [ADDR_WIDTH-1:0] wa_q[$];
    host_seq_item          wd_q[$];
    logic [ADDR_WIDTH-1:0] ra_q[$];


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

// Helper task: waits until all pending Reads and Writes have completed
  task wait_for_idle();
    // 1. Wait a few cycles for the last address handshake to enter the queue
    repeat (5) @(posedge host_vif.clk);
    
    // 2. Wait until all queued Read and Write addresses have been matched with data
    wait (ra_q.size() == 0 && wa_q.size() == 0 && wd_q.size() == 0);
    
    // 3. Small buffer for scoreboard processing
    repeat (5) @(posedge host_vif.clk);
  endtask

  task run_phase(uvm_phase phase);

    wait (host_vif.arst_n === 1'b1);

    fork      
      // Thread 1: Capture Write Address and push to queue
      forever begin
        logic [ADDR_WIDTH-1:0] w_addr;
        host_vif.monitor_wa(w_addr);
        wa_q.push_back(w_addr);
      end

      // Thread 2: Capture Write Data & Byte-Enables and push to queue
      forever begin
        host_seq_item wd_item = host_seq_item::type_id::create("wd_item");
        host_vif.monitor_wd(wd_item.data, wd_item.be);
        wd_q.push_back(wd_item);
      end

      // Thread 3: Pair Write Address with Write Data and send to Scoreboard
      forever begin
        host_seq_item wr_item;
        wait (wa_q.size() > 0 && wd_q.size() > 0);
        
        wr_item         = wd_q.pop_front();
        wr_item.addr    = wa_q.pop_front();
        wr_item.tr_type = 1'b1; // HOST_WRITE
        ap.write(wr_item);
      end

      // Thread 4: Capture Read Address and push to queue
      forever begin
        logic [ADDR_WIDTH-1:0] r_addr;
        host_vif.monitor_ra(r_addr);
        ra_q.push_back(r_addr);
      end

      // Thread 5: Capture Read Data, pop matching Read Address, and send to Scoreboard
      forever begin
        host_seq_item rd_item = host_seq_item::type_id::create("rd_item");
        host_vif.monitor_rd(rd_item.data);
        
        wait (ra_q.size() > 0);
        rd_item.addr    = ra_q.pop_front();
        rd_item.tr_type = 1'b0; // HOST_READ
        ap.write(rd_item);
      end
    join
  endtask

endclass

`endif