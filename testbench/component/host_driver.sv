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

      if ($isunknown(item.addr) ||
          ((item.addr % (BE_WIDTH * BURST_LEN)) != 0)) begin
        `uvm_fatal("ALIGN", $sformatf(
          "Host address 0x%0h is unknown or not aligned to the %0d-byte burst size",
          item.addr, BE_WIDTH * BURST_LEN
        ))
      end

      case (item.tr_type)
        1'b1: begin
          host_vif.write(item.addr, item.data, item.be);
        end

        1'b0: begin
          fork
            host_vif.read_req(item.addr);
            host_vif.monitor_rd(item.data); // Directly store read data into item.data
          join
        end

        default: `uvm_fatal("BADTYPE", "Unsupported host transaction type")
      endcase

      seq_item_port.item_done();
    end
  endtask
endclass
`endif
