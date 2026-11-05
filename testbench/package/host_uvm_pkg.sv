`ifndef __GUARD_DDR3_CONTROLLER_UVM_PKG_SV__
`define __GUARD_DDR3_CONTROLLER_UVM_PKG_SV__

package ddr3_controller_uvm_pkg;
  import uvm_pkg::*;
  import ddr3_params_pkg::*;
  `include "uvm_macros.svh"

  `include "obj/host_seq_item.sv"
  `include "component/host_sequencer.sv"
  `include "component/host_driver.sv"
  `include "component/host_monitor.sv"
  `include "component/scoreboard.sv"
  `include "component/env.sv"
endpackage

`endif
