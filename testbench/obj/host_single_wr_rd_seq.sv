`ifndef __GUARD_HOST_SINGLE_WR_RD_SEQ_SV__
`define __GUARD_HOST_SINGLE_WR_RD_SEQ_SV__

class host_single_wr_rd_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(host_single_wr_rd_seq)

  function new(string name = "host_single_wr_rd_seq");
    super.new(name);
  endfunction

virtual task body();
    host_seq_item item;

    // 1. Send a single Write transaction to address 0x00000000
    item = host_seq_item::type_id::create("wr_item");
    start_item(item);
    
    if (!item.randomize() with {
      tr_type == 1'b1; // HOST_WRITE
    }) begin
      `uvm_fatal("RND_FAIL", "Write item randomization failed")
    end
    
    // Directed values assignment (XSIM-friendly)
    item.addr = '0;
    foreach (item.be[i]) begin
      item.be[i] = {BE_WIDTH{1'b1}}; // Enable all bytes
    end
    
    finish_item(item);

    `uvm_info("SEQ", "Single Write transaction completed", UVM_LOW)

    // 2. Send a single Read transaction to the same address 0x00000000
    item = host_seq_item::type_id::create("rd_item");
    start_item(item);
    
    if (!item.randomize() with {
      tr_type == 1'b0; // HOST_READ
    }) begin
      `uvm_fatal("RND_FAIL", "Read item randomization failed")
    end
    
    item.addr = '0;
    
    finish_item(item);

    `uvm_info("SEQ", "Single Read transaction completed", UVM_LOW)
  endtask

endclass

`endif