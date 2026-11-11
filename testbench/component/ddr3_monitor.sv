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

  covergroup ddr3_command_cg with function sample(
  	logic [2:0] command,
	logic [DRAM_BA_BITS-1:0] bank,
	logic auto_precharge,
	logic [9:0] column
    );

    option.per_instance = 1;

    cp_command : coverpoint command {
  	bins MRS = {3'b000};
	bins REFRESH = {3'b001};
	bins PRE = {3'b010};
	bins ACT = {3'b011};
	bins WRITE = {3'b100};
	bins READ = {3'b101};
	bins ZQCL = {3'b110};
    }

    cp_bank : coverpoint bank {
  	bins bank0 = {0};
  	bins bank1 = {1};
  	bins bank2 = {2};
  	bins bank3 = {3};
  	bins bank4 = {4};
  	bins bank5 = {5};
  	bins bank6 = {6};
  	bins bank7 = {7};
    }

    cp_auto_precharge : coverpoint auto_precharge
  	iff (command inside {3'b100, 3'b101}) {
		bins disabled = {0};
		bins enabled = {1};
    }

    cp_column : coverpoint column
  	iff (command inside {3'b100, 3'b101}) {
		bins low_column = {[0:255]};
		bins mid_column = {[256:767]};
		bins high_column = {[768:1023]};
    }

    cp_command_x_bank : cross cp_command, cp_bank;
  endgroup

  function new(string name = "ddr3_monitor", uvm_component parent = null);
    super.new(name, parent);
    ddr3_command_cg = new();
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
	    ddr3_command_cg.sample(3'b000, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[1;35m[%0t ns] [DDR3_MON] MRS  | BA=%0d Addr=0x%04h\033[0m", $time, vif.ba, vif.addr);
          end
          3'b001: begin
            ref_count++;
	    ddr3_command_cg.sample(3'b001, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[1;91m[%0t ns] [DDR3_MON] REF  | REFRESH #%0d\033[0m", $time, ref_count);
          end
          3'b010: begin
            pre_count++;
	    ddr3_command_cg.sample(3'b010, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[38;5;208m[%0t ns] [DDR3_MON] PRE  | Bank=%0d All=%0b\033[0m", $time, vif.ba, vif.addr[10]);
          end
          3'b011: begin
            act_count++;
	    ddr3_command_cg.sample(3'b011, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[1;36m[%0t ns] [DDR3_MON] ACT  | Bank=%0d Row=0x%04h\033[0m", $time, vif.ba, vif.addr);
          end
          3'b100: begin
            wr_count++;
	    ddr3_command_cg.sample(3'b100, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[1;32m[%0t ns] [DDR3_MON] WR   | Bank=%0d Col=0x%03h AP=%0b\033[0m", $time, vif.ba, {vif.addr[11], vif.addr[9:0]}, vif.addr[10]);
          end
          3'b101: begin
            rd_count++;
	    ddr3_command_cg.sample(3'b101, vif.ba, vif.addr[10], vif.addr[9:0]);
            $display("\033[1;34m[%0t ns] [DDR3_MON] RD   | Bank=%0d Col=0x%03h AP=%0b\033[0m", $time, vif.ba, {vif.addr[11], vif.addr[9:0]}, vif.addr[10]);
          end
          3'b110: begin
	    ddr3_command_cg.sample(3'b110, vif.ba, vif.addr[10], vif.addr[9:0]);
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
    $display("DDR3 command functional coverage: %0.2f%%", ddr3_command_cg.get_inst_coverage());
    $display("========================================\n");
  endfunction
endclass

`endif
