`ifndef __GUARD__HOST_REQ_ITEM_SV__
`define __GUARD__HOST_REQ_ITEM_SV__

import ddr3_params_pkg::*;

class host_seq_item extends uvm_sequence_item;

  rand logic                    tr_type;
  rand logic [ADDR_WIDTH-1:0]   addr;
  rand logic [DATA_WIDTH-1:0]   data [BURST_LEN];
  rand logic [BE_WIDTH-1:0]     be   [BURST_LEN];
  rand bit                      rd_back_pressure; // Indicates if the read transaction is back-pressured
  rand bit                      wr_back_pressure; // Indicates if the write transaction is back-pressured

  `uvm_object_utils_begin(host_seq_item)
    `uvm_field_int(tr_type, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_sarray_int(data, UVM_ALL_ON)
    `uvm_field_sarray_int(be, UVM_ALL_ON)
    `uvm_field_int(rd_back_pressure, UVM_ALL_ON)
    `uvm_field_int(wr_back_pressure, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "host_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("tr_type=%0b, addr=0x%0h, data=%p, be=%p, rd_back_pressure=%0b, wr_back_pressure=%0b",
                     tr_type, addr, data, be, rd_back_pressure, wr_back_pressure);
  endfunction
endclass

`endif
