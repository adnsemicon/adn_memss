`ifndef __GUARD_HOST_DRIVER_SV__
`define __GUARD_HOST_DRIVER_SV__ 0

`include "obj/host_seq_item.sv"

class host_driver extends uvm_driver #(host_seq_item);
  `uvm_component_utils(host_driver)

  virtual host_if #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .BE_WIDTH   (BE_WIDTH),
    .BURST_LEN  (BURST_LEN)
  ) host_vif;

  virtual cnfg_if #(.DRAM_ADDR_BITS(DRAM_ADDR_BITS)) cnfg_vif;
  virtual ctrl_if ctrl_vif;

  function new(string name = "host_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

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

    if (!uvm_config_db #(virtual ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
      `uvm_fatal("NOVIF", "ctrl_vif was not configured for host_driver")
    end
  endfunction

  task automatic wait_for_controller_ready();
    wait (host_vif.arst_n === 1'b1);
    wait (cnfg_vif.init_done === 1'b1);
  endtask

  task run_phase(uvm_phase phase);
    host_seq_item item;

    host_vif.reset_signals();
    wait_for_controller_ready();

    forever begin
      seq_item_port.get_next_item(item);
      wait_for_controller_ready();

      case (item.tr_type)
        1'b1: begin
          // Only stall/backpressure if the sequence explicitly requested it for this transaction
        while (host_vif.wa_ready === 1'b0) begin
            @(posedge host_vif.clk);
          end
          while (host_vif.wd_ready === 1'b0) begin
            @(posedge host_vif.clk);
          end
          host_vif.write(item.addr, item.data, item.be);
        end

        1'b0: begin
          if (item.rd_back_pressure) begin
            fork
              host_vif.set_rd_backpressure(80); // 80 cycles is plenty for 4 DRAM reads
            join_none
          end
          host_vif.read_req(item.addr);

        end

        default: `uvm_fatal("BADTYPE", "Unsupported host transaction type")
      endcase

      seq_item_port.item_done();
    end
  endtask
endclass
`endif
