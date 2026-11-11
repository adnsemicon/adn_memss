`ifndef __GUARD_BYTE_ENABLE_SEQ_SV__
`define __GUARD_BYTE_ENABLE_SEQ_SV__

class byte_enable_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(byte_enable_seq)

  function new(string name = "byte_enable_seq");
    super.new(name);
  endfunction

virtual task body();
    // 1. Send a single Write transaction to address 0x00000000
    `uvm_do_with(req, {
      tr_type == 1'b1; // HOST_WRITE
      addr    == 'hABCD;    // Address 0x00000000
      foreach (be[i]) be[i] == {BE_WIDTH{1'b1}}; // Enable all byte enables
    })
    `uvm_info("SEQ", $sformatf("Write data(wr_data = %p) for Byte enable test (be = %p)", req.data, req.be), UVM_LOW)

    // 2. Send a single Read transaction to address 0x00000000
    `uvm_do_with(req, {
      tr_type == 1'b0;   // HOST_READ
      addr    == 'hABCD; // Address 0x00000000
    })
    `uvm_info("SEQ", $sformatf("Read data for Byte enable test (be = %p)", req.be), UVM_LOW)

    `uvm_do_with(req, {
      tr_type == 1'b1; // HOST_WRITE
      addr    == 'hABCD;
      foreach (be[i]) be[i] == {BE_WIDTH/2{2'b10}}; // Disable all byte enables
    })
    `uvm_info("SEQ", $sformatf("Write data(wr_data = %p) for Byte enable test (be = %p)", req.data, req.be), UVM_LOW)

    `uvm_do_with(req, {
      tr_type == 1'b0;   // HOST_READ
      addr    == 'hABCD;
    })
    `uvm_info("SEQ", $sformatf("Read data for Byte enable test (be = %p)", req.be), UVM_LOW)


  endtask

endclass

`endif