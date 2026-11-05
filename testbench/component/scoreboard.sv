`ifndef __GUARD_HOST_SCOREBOARD_SV__
`define __GUARD_HOST_SCOREBOARD_SV__

class host_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(host_scoreboard)

  uvm_analysis_imp #(host_seq_item, host_scoreboard) analysis_export;

  logic [7:0] expected_memory[longint unsigned];
  int unsigned writes_seen;
  int unsigned reads_seen;
  int unsigned bytes_compared;
  int unsigned bytes_uninitialized;
  int unsigned mismatches;

  function new(string name = "host_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    analysis_export = new("analysis_export", this);
  endfunction

  function void write(host_seq_item observed);
    longint unsigned byte_addr;
    logic [7:0] expected_byte;
    logic [7:0] observed_byte;

    if (observed == null) begin
      `uvm_error("NULL_ITEM", "Monitor published a null transaction")
      return;
    end

    if ((observed.addr % (BE_WIDTH * BURST_LEN)) != 0) begin
      `uvm_error("HOST_ALIGNMENT", $sformatf(
        "Scoreboard received unaligned address 0x%0h", observed.addr
      ))
    end

    case (observed.tr_type)
      HOST_WRITE: begin
        writes_seen++;
        for (int beat = 0; beat < BURST_LEN; beat++) begin
          for (int lane = 0; lane < BE_WIDTH; lane++) begin
            byte_addr = observed.addr + (beat * BE_WIDTH) + lane;
            case (observed.be[beat][lane])
              1'b1: expected_memory[byte_addr] = observed.data[beat][lane*8 +: 8];
              1'b0: ;
              default: `uvm_error("UNKNOWN_BYTE_ENABLE", $sformatf(
                "Unknown byte enable at beat %0d lane %0d", beat, lane
              ))
            endcase
          end
        end
      end

      HOST_READ: begin
        reads_seen++;
        for (int beat = 0; beat < BURST_LEN; beat++) begin
          for (int lane = 0; lane < BE_WIDTH; lane++) begin
            byte_addr = observed.addr + (beat * BE_WIDTH) + lane;
            observed_byte = observed.data[beat][lane*8 +: 8];
            if (expected_memory.exists(byte_addr)) begin
              expected_byte = expected_memory[byte_addr];
              bytes_compared++;
              if (observed_byte !== expected_byte) begin
                mismatches++;
                `uvm_error("DATA_MISMATCH", $sformatf(
                  "Read mismatch at byte address 0x%0h: expected 0x%02h, got 0x%02h (beat %0d, lane %0d)",
                  byte_addr, expected_byte, observed_byte, beat, lane
                ))
              end
            end else begin
              bytes_uninitialized++;
            end
          end
        end
      end

      default: `uvm_error("BADTYPE", "Scoreboard received an unsupported transaction type")
    endcase
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("HOST_SCOREBOARD", $sformatf(
      "Writes=%0d Reads=%0d ComparedBytes=%0d UninitializedBytes=%0d Mismatches=%0d",
      writes_seen, reads_seen, bytes_compared, bytes_uninitialized, mismatches
    ), UVM_LOW)
  endfunction
endclass

`endif