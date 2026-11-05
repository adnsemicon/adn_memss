`ifndef __GUARD__HOST_REQ_ITEM_SV__
`define __GUARD__HOST_REQ_ITEM_SV__

import ddr3_params_pkg::*;

class host_seq_item extends uvm_sequence_item;

  rand logic                    tr_type;
  rand logic [ADDR_WIDTH-1:0]   addr;
  rand logic [DATA_WIDTH-1:0]   data [BURST_LEN];
  rand logic [BE_WIDTH-1:0]     be   [BURST_LEN];

  // Dynamically align address based on byte width and burst length
  localparam int ALIGN_BITS = $clog2(BE_WIDTH * BURST_LEN);

  constraint c_addr_align {
    addr[ALIGN_BITS-1:0] == '0;
  }

  // XSIM-friendly explicit width replication instead of '1
  constraint c_default_be {
    foreach (be[i]) {
      be[i] == {BE_WIDTH{1'b1}};
    }
  }

  `uvm_object_utils_begin(host_seq_item)
    `uvm_field_int(tr_type, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_sarray_int(data, UVM_ALL_ON)
    `uvm_field_sarray_int(be, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "host_seq_item");
    super.new(name);
  endfunction

endclass

`endif