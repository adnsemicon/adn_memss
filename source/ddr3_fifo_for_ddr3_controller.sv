module ddr3_fifo_for_ddr3_controller #(
    parameter string NAME = "",
    parameter int WIDTH = 64,
    parameter int DEPTH = 16
) (
    input logic clk,
    input logic arst_n,

    // Write Port
    input  logic                   winc,
    input  logic [      WIDTH-1:0] wdata,
    output logic                   full,
    output logic                   almost_full,
    output logic [$clog2(DEPTH):0] count,

    // Read Port
    input  logic             rinc,
    output logic [WIDTH-1:0] rdata,
    output logic             empty
);

  localparam int ADDR_W = $clog2(DEPTH);

  logic [WIDTH-1:0] mem  [DEPTH-1:0];
  logic [ ADDR_W:0] wptr;
  logic [ ADDR_W:0] rptr;

  assign empty       = (wptr == rptr);
  assign full        = (wptr[ADDR_W] != rptr[ADDR_W]) && (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);
  assign count       = wptr - rptr;
  assign almost_full = (count >= (DEPTH - 8));  // Room for less than an 8-beat burst
  assign rdata       = mem[rptr[ADDR_W-1:0]];

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      wptr <= '0;
      rptr <= '0;
    end else begin
      if (winc && !full) begin
        mem[wptr[ADDR_W-1:0]] <= wdata;
        wptr <= wptr + 1'b1;
      end
      if (rinc && !empty) begin
        rptr <= rptr + 1'b1;
      end
    end
  end

endmodule
