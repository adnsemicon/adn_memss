`ifndef __GUARD_DDR3_MONITOR_SV__
`define __GUARD_DDR3_MONITOR_SV__ 0

class ddr3_monitor extends uvm_monitor;
  `uvm_component_utils(ddr3_monitor)

  // virtual ddr3_if #(
  //   .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
  //   .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
  //   .DM_WIDTH       (DM_WIDTH      ),  
  //   .DQS_WIDTH      (DQS_WIDTH     ),  
  //   .DATA_WIDTH     (DATA_WIDTH    )     
  // ) vif;

  virtual ddr3_if #(
    .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
    .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
    .DM_WIDTH       (DM_WIDTH      ),  
    .DQS_WIDTH      (DQS_WIDTH     ),  
    .DATA_WIDTH     (DATA_WIDTH    )    
  ) vif;
  
  int ref_count = 0;
  int act_count = 0;
  int wr_count  = 0;
  int rd_count  = 0;
  int pre_count = 0;
  int mr_count  = 0;

  function new(string name = "ddr3_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // virtual function void build_phase(uvm_phase phase);
  //   super.build_phase(phase);
    // if (!uvm_config_db #(virtual ddr3_if #(
    //   .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
    //   .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
    //   .DM_WIDTH       (DM_WIDTH      ),  
    //   .DQS_WIDTH      (DQS_WIDTH     ),  
    //   .DATA_WIDTH     (DATA_WIDTH    )     
    // ))::get(this, "", "ddr3_vif", vif)); begin
    //   `uvm_fatal("NOVIF", "Virtual interface ddr3_if not set for ddr3_monitor!")
    //end
    // if (!uvm_config_db #(virtual ddr3_if)::get(this, "", "ddr3_vif", vif)) begin
    //   `uvm_fatal("NOVIF", "Virtual interface ddr3_if not set for ddr3_monitor!")
    // end
  //   if (!uvm_config_db #(virtual ddr3_if)::get(this, "", "ddr3_vif", vif)) begin
  //     `uvm_fatal("NOVIF", $sformatf("Virtual interface ddr3_if not set for %s! Check config_db path.", get_full_name()))
  //   end
  // endfunction

virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // গেট করার সময়ও হবহু একই প্যারামিটার রাখতে হবে
    if (!uvm_config_db #(virtual ddr3_if #(
      .DRAM_BA_BITS   (DRAM_BA_BITS  ),  
      .DRAM_ADDR_BITS (DRAM_ADDR_BITS),   
      .DM_WIDTH       (DM_WIDTH      ),  
      .DQS_WIDTH      (DQS_WIDTH     ),  
      .DATA_WIDTH     (DATA_WIDTH    )    
    ))::get(this, "", "ddr3_vif", vif)) begin
      `uvm_fatal("NOVIF", "Virtual interface ddr3_if not set for ddr3_monitor!")
    end
  endfunction

  virtual task track_bus_commands();
    forever begin
      @(posedge vif.ck_p);
      if (vif.rst_n === 1'b1 && vif.cke === 1'b1 && vif.cs_n === 1'b0) begin
        case ({vif.ras_n, vif.cas_n, vif.we_n})
          3'b000: begin
            mr_count++;
            $display("\033[1;35m[%0t ns] [DDR3_MON] MRS  | BA=%0d Addr=0x%04h\033[0m", $time, vif.ba, vif.addr);
          end
          3'b001: begin
            ref_count++;
            $display("\033[1;91m[%0t ns] [DDR3_MON] REF  | REFRESH #%0d\033[0m", $time, ref_count);
          end
          3'b010: begin
            pre_count++;
            $display("\033[38;5;208m[%0t ns] [DDR3_MON] PRE  | Bank=%0d All=%0b\033[0m", $time, vif.ba, vif.addr[10]);
          end
          3'b011: begin
            act_count++;
            $display("\033[1;36m[%0t ns] [DDR3_MON] ACT  | Bank=%0d Row=0x%04h\033[0m", $time, vif.ba, vif.addr);
          end
          3'b100: begin
            wr_count++;
            $display("\033[1;32m[%0t ns] [DDR3_MON] WR   | Bank=%0d Col=0x%03h AP=%0b\033[0m", $time, vif.ba, {vif.addr[11], vif.addr[9:0]}, vif.addr[10]);
          end
          3'b101: begin
            rd_count++;
            $display("\033[1;34m[%0t ns] [DDR3_MON] RD   | Bank=%0d Col=0x%03h AP=%0b\033[0m", $time, vif.ba, {vif.addr[11], vif.addr[9:0]}, vif.addr[10]);
          end
          3'b110: begin
            $display("\033[0;37m[%0t ns] [DDR3_MON] ZQCL\033[0m", $time);
          end
          default: ;
        endcase
      end
    end
  endtask

virtual task track_fsm_states();
    string last_state = "";
    forever begin
      @(posedge vif.ck_p);
      if (vif.current_fsm_state != "" && vif.current_fsm_state != last_state) begin
        $display("\033[1;33m[%0t ns] [FSM] %s\033[0m", $time, vif.current_fsm_state);
        last_state = vif.current_fsm_state;
      end
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    fork
      track_bus_commands();
      track_fsm_states();
    join_none
  endtask


  virtual function void report_phase(uvm_phase phase);
    $display("\n========================================");
    $display("       DDR3 BUS COMMAND SUMMARY         ");
    $display("========================================");
    $display(" MRS     : %0d",  mr_count);
    $display(" ACTIVATE: %0d",  act_count);
    $display(" WRITE   : %0d",  wr_count);
    $display(" READ    : %0d",  rd_count);
    $display(" PRECHARGE: %0d", pre_count);
    $display(" REFRESH : %0d",  ref_count);
    $display("========================================\n");
  endfunction
endclass

`endif
