`ifndef __GUARD__HOST_REQ_ITEM_SV__
`define __GUARD__HOST_REQ_ITEM_SV__ 0

import uvm_pkg::*;
import host_params_pkg::*;
`include "uvm_macros.svh"

class host_seq_item extends uvm_sequence_item;

  rand bit                     tr_type;
  rand logic [ADDR_WIDTH-1:0]  addr;
  rand logic [DATA_WIDTH-1:0]  data [BURST_LEN];
  rand logic [BE_WIDTH-1:0]    be   [BURST_LEN];

  // Dynamically align address based on byte width and burst length
  localparam int ALIGN_BITS = $clog2(BE_WIDTH * BURST_LEN);

  constraint c_addr_align {
    addr[ALIGN_BITS-1:0] == '0;
  }

  constraint c_default_be {
    foreach (be[i]) soft be[i] == '1;
  }

  `uvm_object_utils_begin(host_seq_item)
    `uvm_field_enum(tr_type_e, tr_type, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_sarray_int(data, UVM_ALL_ON)
    `uvm_field_sarray_int(be, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "host_seq_item");
    super.new(name);
  endfunction

endclass
`endif
