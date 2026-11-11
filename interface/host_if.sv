interface host_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 64,
  parameter int BE_WIDTH   = DATA_WIDTH / 8,
  parameter int BURST_LEN  = 8
) (
  input logic clk,
  input logic arst_n
);

  // -------------------------------------------------------------------------
  // 1. Channel Signals
  // -------------------------------------------------------------------------
  // Write Address Channel (wa)
  logic [ADDR_WIDTH-1:0] wa_addr;
  logic                  wa_valid;
  logic                  wa_ready;

  // Write Data Channel (wd)
  logic [DATA_WIDTH-1:0] wd_data;
  logic [BE_WIDTH-1:0]   wd_be;
  logic                  wd_valid;
  logic                  wd_ready;

  // Read Address Channel (ra)
  logic [ADDR_WIDTH-1:0] ra_addr;
  logic                  ra_valid;
  logic                  ra_ready;

  // Read Data Channel (rd)
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  rd_valid;
  logic                  rd_ready;


  task automatic reset_signals();
    wa_valid <= 1'b0;
    wa_addr  <= '0;
    wd_valid <= 1'b0;
    wd_data  <= '0;
    wd_be    <= '0;
    ra_valid <= 1'b0;
    ra_addr  <= '0;
    rd_ready <= 1'b1;
  endtask

  task automatic drive_wa(input logic [ADDR_WIDTH-1:0] addr, input int delay = 0);
    repeat (delay) @(posedge clk);
    wa_addr  <= addr;
    wa_valid <= 1'b1;
    do begin
      @(posedge clk);
    end while (!wa_ready);
    wa_valid <= 1'b0;
  endtask

  // Drive 8-beat Write Data Burst (wd)
  task automatic drive_wd(
    input logic [DATA_WIDTH-1:0] data [BURST_LEN],
    input logic [BE_WIDTH-1:0]   be   [BURST_LEN],
    input int                    delay = 0
  );
    repeat (delay) @(posedge clk);
    //@(posedge clk);
    for (int i = 0; i < BURST_LEN; i++) begin
      wd_data  <= data[i];
      wd_be    <= be[i];
      wd_valid <= 1'b1;
      do begin
        @(posedge clk);
      end while (!wd_ready);
    end
    wd_valid <= 1'b0;
  endtask

  // Combined Full Write Task
  task automatic write(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] data [BURST_LEN],
    input logic [BE_WIDTH-1:0]   be   [BURST_LEN],
    input int                    wa_delay = 0,
    input int                    wd_delay = 0
  );
    fork
      drive_wa(addr, wa_delay);
      drive_wd(data, be, wd_delay);
    join
  endtask

  // Drive Read Address Request (ra)
  task automatic read_req(input logic [ADDR_WIDTH-1:0] addr, input int delay = 0);
    repeat (delay) @(posedge clk);
    @(posedge clk);
    ra_addr  <= addr;
    ra_valid <= 1'b1;
    do begin
      @(posedge clk);
    end while (!ra_ready);
    ra_valid <= 1'b0;
  endtask

  // Control Read Backpressure (rd_ready)
  task automatic set_rd_backpressure(input int delay = 20);
    if (rd_ready === 1'b0) return;
    @(posedge clk);
    rd_ready <= '0;
    wait (rd_valid === 1'b1);
    repeat (delay) @(posedge clk);
    rd_ready <= '1;
  endtask


  // =========================================================================
  // 3. MONITOR TASKS (Called by host_monitor in parallel threads)
  // =========================================================================

  // Capture a valid Write Address handshake
  task automatic monitor_wa(output logic [ADDR_WIDTH-1:0] addr);
    do begin
      @(posedge clk);
    end while (!(wa_valid && wa_ready));
    addr = wa_addr;
  endtask

  // Capture a complete 8-beat Write Data burst
  task automatic monitor_wd(
    output logic [DATA_WIDTH-1:0] data [BURST_LEN],
    output logic [BE_WIDTH-1:0]   be   [BURST_LEN]
  );
    for (int i = 0; i < BURST_LEN; i++) begin
      do begin
        @(posedge clk);
      end while (!(wd_valid && wd_ready));
      data[i] = wd_data;
      be[i]   = wd_be;
    end
  endtask

  // Capture a valid Read Address handshake
  task automatic monitor_ra(output logic [ADDR_WIDTH-1:0] addr);
    do begin
      @(posedge clk);
    end while (!(ra_valid && ra_ready));
    addr = ra_addr;
  endtask

  // Capture a complete 8-beat Read Data burst
  task automatic monitor_rd(output logic [DATA_WIDTH-1:0] data [BURST_LEN]);
    for (int i = 0; i < BURST_LEN; i++) begin
      do begin
        @(posedge clk);
      end while (!(rd_valid && rd_ready));
      data[i] = rd_data;
    end
  endtask
endinterface
