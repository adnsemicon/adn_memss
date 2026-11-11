`ifndef __GUARD_RANDOM_STRESS_SEQ_SV__
`define __GUARD_RANDOM_STRESS_SEQ_SV__ 0

class random_stress_seq extends uvm_sequence #(host_seq_item);
  `uvm_object_utils(random_stress_seq)

  rand int num_transactions;
  constraint c_num_txns { 
      num_transactions inside {[100:200]}; 
    }

  function new(string name = "random_stress_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("STRESS_SEQ", $sformatf("Starting random stress sequence with %0d transactions...", num_transactions), UVM_LOW)

    repeat (num_transactions) begin
      `uvm_do_with(req, {
        // 60% writes, 40% reads to ensure we write before reading back
        tr_type          dist { 1'b1 :/ 60, 1'b0 :/ 40 };
        //addr             inside {[0 : 'h3FFFF]};
        
        // Random byte enables (some bytes masked, some fully enabled)
        foreach (be[i])  be[i] inside {0, 1};
        
        // Random backpressure control (e.g., 20% chance of backpressure)
        wr_back_pressure dist { 1'b1 :/ 20, 1'b0 :/ 80 };
        rd_back_pressure dist { 1'b1 :/ 20, 1'b0 :/ 80 };
      })
    end

    `uvm_info("STRESS_SEQ", "Random stress sequence generation completed!", UVM_LOW)
  endtask
endclass
`endif
