`ifndef __GUARD_HOST_SINGLE_WR_RD_SEQ_SV__
`define __GUARD_HOST_SINGLE_WR_RD_SEQ_SV__

class host_single_wr_rd_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(host_single_wr_rd_seq)

  function new(string name = "host_single_wr_rd_seq");
    super.new(name);
  endfunction

  virtual task body();
    // 1. Send a single Write transaction to address 0x00000000
    `uvm_do_with(req, {
      tr_type == 1'b1; // HOST_WRITE
      addr    == 'h0;    // Address 0x00000000
      foreach (be[i]) be[i] == {BE_WIDTH{1'b1}}; // Enable all byte enables 
      wr_back_pressure == 1'b0; // Ensure no write back-pressure  
    })
    `uvm_info("SEQ", "Single Write transaction completed", UVM_LOW)

    // 2. Send a single Read transaction to address 0x00000000
    `uvm_do_with(req, {
      tr_type == 1'b0;   // HOST_READ
      addr    == 'h0; // Address 0x00000000
      rd_back_pressure == 1'b0; // Ensure no read back-pressure
    })
    `uvm_info("SEQ", "Single Read transaction completed", UVM_LOW)
  endtask

endclass

`endif
