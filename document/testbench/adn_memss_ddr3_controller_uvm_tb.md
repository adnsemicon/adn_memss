# DDR3 Memory Controller UVM Testbench

**Target DUT:** `adn_memss_ddr3_controller`  
**Methodology:** SystemVerilog / UVM  
**Verification Interfaces:** `ctrl_if`, `host_if`, and `cfg_if`  
**Verification Agents:** Active `host_agent` only (No passive `ddr3_monitor` agent; protocol observation and timing checks are handled directly by the Micron DRAM Memory Model).

Related module documentation: [adn_memss_ddr3_controller](adn_memss_ddr3_controller.md) · [adn_memss_ddr3_chip_array](adn_memss_ddr3_chip_array.md)

---

## 1. Overview & Architecture Scope

This document outlines the Universal Verification Methodology (UVM) plan for the `adn_memss_ddr3_controller`. The verification environment utilizes an active `host_agent` to drive stimulus across the host interfaces, while the Micron DDR3 memory model acts as the physical responder, validating protocol compliance and timing constraints automatically.

---

## Top IO

![DDR3 controller UVM testbench top I/O](./adn_memss_ddr3_controller_uvm_tb_top.svg)

The testbench connects to the controller's host, configuration, clock/reset, status, and DDR3 physical ports. The host and configuration interfaces below are testbench abstractions; the DUT itself exposes individual ports as listed in [adn_memss_ddr3_controller.md](adn_memss_ddr3_controller.md).


## Parameters

The UVM testbench uses the following default DUT configuration.

| Name | Type | Default | Description |
|---|---|---|---|
| `ADDR_WIDTH` | `int` | `30` | Byte address width. |
| `DATA_WIDTH` | `int` | `64` | Data width per host transfer in bits. |
| `BURST_LEN` | `int` | `8` | Fixed number of transfers per block transaction. |
| `DRAM_CHIP_WIDTH` | `int` | `16` | Data width of each modeled DDR3 chip. |
| `SIM_SPEED_UP` | `bit` | `1'b1` | Enables accelerated power-up delays for simulation. |

## Ports

| Name | Direction | Type | Dimension | Description |
|---|---|---|---|---|
| `clk` | input | `logic` | — | System clock. |
| `rtc` | input | `logic` | — | Real-time clock used for DDR3 timing intervals. |
| `arst_n` | input | `logic` | — | Asynchronous active-low reset. |
| `mr0`–`mr3` | input | `logic` | `[DRAM_ADDR_BITS-1:0]` each | DDR3 Mode Register values. |
| `tRCD`, `tRP`, `tRAS`, `tRC`, `tWR`, `tRTP`, `tWTR`, `tRRD`, `tFAW`, `tRFC`, `tREFI` | input | `logic` | `[15:0]` each | DDR3 timing parameters in `rtc` ticks. |
| `wa_addr` | input | `logic` | `[ADDR_WIDTH-1:0]` | Write address. |
| `wa_valid` | input | `logic` | — | Write address valid. |
| `wa_ready` | output | `logic` | — | Write address ready. |
| `wd_data` | input | `logic` | `[DATA_WIDTH-1:0]` | Write data beat. |
| `wd_be` | input | `logic` | `[DATA_WIDTH/8-1:0]` | Write byte enables. |
| `wd_valid` | input | `logic` | — | Write data valid. |
| `wd_ready` | output | `logic` | — | Write data ready. |
| `ra_addr` | input | `logic` | `[ADDR_WIDTH-1:0]` | Read address. |
| `ra_valid` | input | `logic` | — | Read address valid. |
| `ra_ready` | output | `logic` | — | Read address ready. |
| `rd_data` | output | `logic` | `[DATA_WIDTH-1:0]` | Read data beat. |
| `rd_valid` | output | `logic` | — | Read data valid. |
| `rd_ready` | input | `logic` | — | Read data ready. |
| `ddr3_ck_p`, `ddr3_ck_n` | output | `logic` | scalar each | DDR3 differential clock. |
| `ddr3_rst_n`, `ddr3_cke`, `ddr3_cs_n`, `ddr3_ras_n`, `ddr3_cas_n`, `ddr3_we_n`, `ddr3_odt` | output | `logic` | scalar each | DDR3 reset, enable, command, and termination signals. |
| `ddr3_ba` | output | `logic` | `[DRAM_BA_BITS-1:0]` | DDR3 bank address. |
| `ddr3_addr` | output | `logic` | `[DRAM_ADDR_BITS-1:0]` | DDR3 address bus. |
| `ddr3_dm` | inout | `wire` | `[DATA_WIDTH/8-1:0]` | DDR3 data mask. |
| `ddr3_dqs_p`, `ddr3_dqs_n` | inout | `wire` | `[DATA_WIDTH/8-1:0]` each | DDR3 differential data strobes. |
| `ddr3_dq` | inout | `wire` | `[DATA_WIDTH-1:0]` | DDR3 bidirectional data bus. |
| `init_do` | input | `logic` | — | Re-initialization request. |
| `init_done` | output | `logic` | — | Initialization complete status. |
| `idle` | output | `logic` | — | Controller idle status. |

With the defaults above, each block transaction contains 512 data bits. Byte-enable width is `DATA_WIDTH/8` (8 bits at the default width). The physical DDR3 ports connect to the chip array described in [adn_memss_ddr3_chip_array.md](adn_memss_ddr3_chip_array.md).

---

## Test Environment

![DDR3 controller UVM testbench architecture](./adn_memss_ddr3_control_uvm_tb.svg)

The planned environment uses an active host agent, a configuration driver, a scoreboard/reference memory, protocol checking, and the Micron DDR3 model connected through the chip-array wrapper. The diagram will show their connections and transaction flow.





---

## 2. Comprehensive Test Suite & Test Cases

### 2.1 DDR3 Reset Test

**Objective:** Verify that reset clears the controller’s initialization status and that the controller initializes again after reset.

| Step | Action | Check |
|---|---|---|
| 1 | Apply reset. | `init_done` clears to 0. |
| 2 | Wait for the controller to initialize after reset. | `init_done` returns to 1. |
| 3 | Repeat the reset and initialization check once. | Both reset cycles complete successfully. |

**Expected result:** The controller clears `init_done` during reset and completes initialization after each reset.

### 2.2 DDR3 Initialization Test

**Objective:** Verify that the controller issues the expected DDR3 initialization commands for two mode-register configurations.

| Step | Action | Check |
|---|---|---|
| 1 | Apply the baseline mode-register configuration: MR0=`0x0220`, MR1=`0x0000`, MR2=`0x0000`, MR3=`0x0000`. | The controller applies the configuration before issuing mode-register commands. |
| 2 | Observe the DDR3 command interface until initialization completes. | The controller issues MRS commands for MR2, MR3, MR1, and MR0 in order, followed by ZQCL. |
| 3 | Check controller readiness after initialization and observe the idle state for 2,000 clock cycles. | `init_done` and host ready signals assert; the controller remains idle and host valid signals remain low. |
| 4 | Reset the controller and apply an alternate configuration: MR0=`0x0230`, MR1=`0x0000`, MR2=`0x0008`, MR3=`0x0000`. | The controller completes initialization using the alternate register values and command sequence. |
| 5 | Check controller readiness and idle behavior again. | Initialization completes within 20,000 clock cycles and the controller remains idle for 2,000 clock cycles. |

**Expected result:** Both configurations initialize successfully, with the expected mode-register and ZQCL commands and no host traffic during initialization.

### 2.3 Single Write/Read Test

**Objective:** Verify a basic write followed by a read from the same address.

| Step | Action | Check |
|---|---|---|
| 1 | Write one burst of randomized data to address `0x00000000`, with all byte enables set. | The write transaction completes. |
| 2 | Read a burst from address `0x00000000`. | The scoreboard compares the returned data against the stored write data. |
| 3 | Wait for the host monitor to finish processing transactions. | No write or read transactions remain pending. |

**Expected result:** The read data matches the previously written data.

### 2.4 Byte-Enable Masking Test

**Objective:** Check write and read behavior when writing with full and patterned byte enables.

| Step | Action | Check |
|---|---|---|
| 1 | Write a burst of randomized data to address `0xABCD` with all byte enables set. | The scoreboard records the enabled bytes. |
| 2 | Read from address `0xABCD`. | Returned bytes match the recorded data. |
| 3 | Write another randomized burst to `0xABCD` using the sequence’s patterned byte-enable value. | The scoreboard updates only the bytes enabled by the pattern. |
| 4 | Read from `0xABCD` again. | Enabled bytes match the latest write; bytes not enabled retain their previous values. |
| 5 | Wait for the host monitor to finish processing transactions. | No write or read transactions remain pending. |

**Expected result:** Byte-enable masking preserves previously stored values in bytes that the patterned write does not enable.

### 2.5 Back-to-Back Burst Test

**Objective:** Verify multiple consecutive writes followed by reads from the same addresses.

| Step | Action | Check |
|---|---|---|
| 1 | Issue four full-byte-enable burst writes to addresses starting at `0x1000`, increasing by one burst size each time. | All four writes complete. |
| 2 | Issue reads from the same four addresses. | Each read matches the data stored by its corresponding write. |
| 3 | Wait for the host monitor to finish processing transactions. | No transactions remain pending. |

**Expected result:** All four burst locations can be written and read back correctly.

### 2.6 Read Backpressure Test

**Objective:** Verify that read data is handled while the host applies read-side backpressure.

| Step | Action | Check |
|---|---|---|
| 1 | Issue four full-byte-enable burst writes to addresses starting at `0xAB22`, increasing by one burst size each time. | All four writes complete. |
| 2 | Read from those same four addresses with read backpressure enabled. | The read data is accepted after backpressure is released and matches the corresponding writes. |
| 3 | Wait for the host monitor to finish processing transactions. | No transactions remain pending. |

**Expected result:** Read responses are retained during backpressure and returned data matches the written data.

### 2.7 Random Stress Test

**Objective:** Exercise the host interface with a large randomized mix of reads, writes, byte enables, and backpressure.

| Step | Action | Check |
|---|---|---|
| 1 | Randomize the sequence length between 10,000 and 20,000 transactions. | A valid transaction count is selected. |
| 2 | Generate transactions with a 60% write and 40% read distribution. | Both transaction types are exercised. |
| 3 | Randomize byte enables and write/read backpressure controls for each transaction. | The controller processes the generated traffic without scoreboard read mismatches or Micron model errors. |
| 4 | Wait for the host monitor to finish processing transactions. | No transactions remain pending. |

**Expected result:** The randomized traffic completes without data mismatches or DDR3 model errors.

### 2.8 Refresh Collision Test

**Objective:** Exercise randomized host traffic while requesting a higher refresh rate.

| Step | Action | Check |
|---|---|---|
| 1 | Configure `tREFI` to 80 RTC ticks. | The controller uses the shortened refresh interval. |
| 2 | Run the randomized stress sequence. | Host reads and writes proceed while refresh operations are requested. |
| 3 | Wait for the host monitor to finish processing transactions. | No transactions remain pending and the scoreboard reports no read mismatches. |

**Expected result:** The controller handles randomized traffic with frequent refresh requests without data mismatches or DDR3 model errors.

### 2.9 Shadow Register Protection Test (`shadow_reg_protection_test`)

**Objective:** Verify that the controller's internal shadow registers (`active_*`) ignore unlatched timing parameter changes during runtime when `init_do` is not asserted.

| Step | Action | Check |
|---|---|---|
| 1 | Run a baseline write/read sequence at address `0x00000000` using the default configuration and wait for the host monitor to reach idle. | The read data matches the write data and all bus activity completes. |
| 2 | Drive modified/invalid timing parameters (`margin_ticks = -10` across `tRCD`, `tRP`, `tRAS`, `tRC`, `tWR`, `tRTP`, `tWTR`, `tRRD`, `tFAW`, `tRFC`, and `tREFI`) on the configuration ports without asserting `init_do`. | `init_done` remains high (`1`) and no MRS re-initialization commands are issued on the DDR3 bus. |
| 3 | Run another write/read sequence at address `0x00000000`. | The controller continues operating with the previously latched `active_*` timings; post-update read data matches the write data with zero Micron model timing violations. |
| 4 | Wait for the host monitor to finish processing transactions. | No write or read transactions remain pending. |

**Expected result:** The controller ignores unlatched configuration changes when `init_do` is low, preserving active timing parameters and completing all transactions without scoreboard mismatches or DDR3 model errors.

### 2.10 Re-initialization Test (`reinitialization_test`)

**Objective:** Verify that the controller safely latches updated timing parameters and Mode Register settings via a full `init_do` / `init_done` handshake and resumes host traffic after re-initialization.

| Step | Action | Check |
|---|---|---|
| 1 | Run a baseline write/read sequence at address `0x00000000` with the initial configuration and wait for the host monitor to reach idle. | The read data matches the write data and the controller returns to idle. |
| 2 | Update timing parameters (`margin_ticks` added to core timings) and new Mode Register values (e.g., `MR0 = 0x1D78`), then assert `init_do` and hold it high until `init_done` clears to `0`. | The controller acknowledges the request by driving `init_done` low (`0`) and latches the new configuration into its `active_*` registers. |
| 3 | De-assert `init_do` and wait for the controller to complete the re-initialization sequence (`init_done == 1`). | The controller executes the full boot sequence (`CKE_HIGH`, `MR2`, `MR3`, `MR1`, `MR0`, `ZQCL`, and `DLL_WAIT`) using the updated register and timing values. |
| 4 | Run a post-reinitialization write/read sequence at address `0x00000000` and wait for the host monitor to finish processing transactions. | Traffic executes under the newly latched timing intervals, read data matches the written data, and no transactions remain pending. |

**Expected result:** The controller completes the full re-initialization handshake, applies the updated Mode Register and timing parameters, and processes subsequent read/write traffic without scoreboard mismatches or DDR3 model errors.

---