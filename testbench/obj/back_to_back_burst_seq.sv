`ifndef __GUARD_BACK_TO_BACK_BURST_SEQ_SV__
`define __GUARD_BACK_TO_BACK_BURST_SEQ_SV__

class back_to_back_burst_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(back_to_back_burst_seq)

  function new(string name = "back_to_back_burst_seq");
    super.new(name);
  endfunction


virtual task body();
    int seq_length;

    if (!uvm_config_db#(int)::get(uvm_root::get(), "parameter", "seq_length", seq_length)) begin
        seq_length = 1;
    end

    `uvm_info("SEQ", $sformatf("Back-to-back burst sequence length: %0d", seq_length), UVM_LOW)
    for (int i = 0; i < seq_length; i++) begin
        `uvm_do_with(req, {
            tr_type == 1'b1; // HOST_WRITE
            addr    == 'h1000 + (i * (BE_WIDTH * BURST_LEN)); // Increment address for each transaction
            foreach (be[j]) be[j] == {BE_WIDTH{1'b1}}; // Enable all byte enables
            wr_back_pressure == 1'b0; // Ensure no write back-pressure
        })
        `uvm_info("SEQ", $sformatf("Back-to-back Write transaction %0d completed", i), UVM_LOW)
    end
    for (int i = 0; i < seq_length; i++) begin
        `uvm_do_with(req, {
            tr_type == 1'b0;   // HOST_READ
            addr    == 'h1000 + (i * (BE_WIDTH * BURST_LEN)); // Same address as write
            rd_back_pressure == 1'b0; // Ensure no read back-pressure
        })
        `uvm_info("SEQ", $sformatf("Back-to-back Read transaction %0d completed", i), UVM_LOW)
    end
  endtask

endclass

`endif