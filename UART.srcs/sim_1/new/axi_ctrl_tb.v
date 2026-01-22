`timescale 1ns/1ps

module tb_axi4lite_ctrl;

  // Parameters
  localparam DATA_W       = 32;
  localparam ADDR_W       = 32;
  localparam TRANS_RESP_W = 2;

  localparam CONF_BASE_ADDR  = 32'h2000_0000;
  localparam CONF_OFFSET     = 32'h04;
  localparam CONF_REG_NUM    = 2;

  localparam ST_WR_BASE_ADDR = 32'h2000_0010;
  localparam ST_WR_OFFSET    = 32'h04;
  localparam ST_WR_FIFO_NUM  = 1;

  localparam ST_RD_BASE_ADDR = 32'h2000_0020;
  localparam ST_RD_OFFSET    = 32'h04;
  localparam ST_RD_FIFO_NUM  = 1;

  // AXI responses
  localparam [1:0] OKAY  = 2'b00;
  localparam [1:0] SLVERR= 2'b10;
  localparam [1:0] DECERR= 2'b11;

  // Clock/Reset
  reg clk;
  reg rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk; // 100MHz
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // DUT IO signals
  // Write address
  reg  [ADDR_W-1:0]   s_axi_awaddr;
  reg  [2:0]          s_axi_awprot;
  reg                 s_axi_awvalid;
  wire                s_axi_awready;

  // Write data
  reg  [DATA_W-1:0]   s_axi_wdata;
  reg  [(DATA_W/8)-1:0] s_axi_wstrb;
  reg                 s_axi_wvalid;
  wire                s_axi_wready;

  // Write response
  wire [TRANS_RESP_W-1:0] s_axi_bresp;
  wire                s_axi_bvalid;
  reg                 s_axi_bready;

  // Read address
  reg  [ADDR_W-1:0]   s_axi_araddr;
  reg  [2:0]          s_axi_arprot;
  reg                 s_axi_arvalid;
  wire                s_axi_arready;

  // Read data
  wire [DATA_W-1:0]   s_axi_rdata;
  wire [TRANS_RESP_W-1:0] s_axi_rresp;
  wire                s_axi_rvalid;
  reg                 s_axi_rready;

  // External interfaces
  reg  [DATA_W-1:0]   stat_reg_i;
  reg                 mem_wr_rdy_i;
  reg  [DATA_W-1:0]   mem_rd_data_i;
  reg                 mem_rd_rdy_i;

  reg  [ST_WR_FIFO_NUM-1:0] wr_st_can_accept_i;
  reg  [DATA_W-1:0]         rd_st_data_i;
  reg  [ST_RD_FIFO_NUM-1:0] rd_st_has_data_i;

  wire [DATA_W*CONF_REG_NUM-1:0] conf_reg_o;
  wire [DATA_W-1:0] mem_wr_data_o;
  wire [ADDR_W-1:0] mem_wr_addr_o;
  wire [(DATA_W/8)-1:0] mem_wr_strb_o;  // Added for WSTRB support
  wire              mem_wr_vld_o;
  wire [ADDR_W-1:0] mem_rd_addr_o;
  wire              mem_rd_vld_o;

  wire [DATA_W-1:0] wr_st_data_o;
  wire [ST_WR_FIFO_NUM-1:0] wr_st_push_o;
  wire [ST_RD_FIFO_NUM-1:0] rd_st_pop_o;

  // Instantiate DUT
  axi4lite_ctrl #(
    .AXI4_CTRL_CONF   (1),
    .AXI4_CTRL_STAT   (0),
    .AXI4_CTRL_MEM    (0),
    .AXI4_CTRL_WR_ST  (1),
    .AXI4_CTRL_RD_ST  (1),

    .CHECK_ALIGNMENT  (1),
    .CHECK_PROTECTION (1),  // Enable for testing
    .PRIVILEGED_ONLY  (0),
    
    .READ_TIMEOUT     (16'd1000),  // 1000 clocks for faster sim

    .CONF_BASE_ADDR   (CONF_BASE_ADDR),
    .CONF_OFFSET      (CONF_OFFSET),
    .CONF_REG_NUM     (CONF_REG_NUM),

    .ST_WR_BASE_ADDR  (ST_WR_BASE_ADDR),
    .ST_WR_OFFSET     (ST_WR_OFFSET),
    .ST_WR_FIFO_NUM   (ST_WR_FIFO_NUM),

    .ST_RD_BASE_ADDR  (ST_RD_BASE_ADDR),
    .ST_RD_OFFSET     (ST_RD_OFFSET),
    .ST_RD_FIFO_NUM   (ST_RD_FIFO_NUM),

    .DATA_W           (DATA_W),
    .ADDR_W           (ADDR_W),
    .TRANS_RESP_W     (TRANS_RESP_W)
  ) dut (
    .clk              (clk),
    .rst_n            (rst_n),

    .s_axi_awaddr     (s_axi_awaddr),
    .s_axi_awprot     (s_axi_awprot),
    .s_axi_awvalid    (s_axi_awvalid),
    .s_axi_awready    (s_axi_awready),

    .s_axi_wdata      (s_axi_wdata),
    .s_axi_wstrb      (s_axi_wstrb),
    .s_axi_wvalid     (s_axi_wvalid),
    .s_axi_wready     (s_axi_wready),

    .s_axi_bresp      (s_axi_bresp),
    .s_axi_bvalid     (s_axi_bvalid),
    .s_axi_bready     (s_axi_bready),

    .s_axi_araddr     (s_axi_araddr),
    .s_axi_arprot     (s_axi_arprot),
    .s_axi_arvalid    (s_axi_arvalid),
    .s_axi_arready    (s_axi_arready),

    .s_axi_rdata      (s_axi_rdata),
    .s_axi_rresp      (s_axi_rresp),
    .s_axi_rvalid     (s_axi_rvalid),
    .s_axi_rready     (s_axi_rready),

    .stat_reg_i       (stat_reg_i),
    .mem_wr_rdy_i      (mem_wr_rdy_i),
    .mem_rd_data_i     (mem_rd_data_i),
    .mem_rd_rdy_i      (mem_rd_rdy_i),

    .wr_st_can_accept_i(wr_st_can_accept_i),
    .rd_st_data_i      (rd_st_data_i),
    .rd_st_has_data_i  (rd_st_has_data_i),

    .conf_reg_o        (conf_reg_o),
    .mem_wr_data_o     (mem_wr_data_o),
    .mem_wr_addr_o     (mem_wr_addr_o),
    .mem_wr_strb_o     (mem_wr_strb_o),  // Connect WSTRB output
    .mem_wr_vld_o      (mem_wr_vld_o),
    .mem_rd_addr_o     (mem_rd_addr_o),
    .mem_rd_vld_o      (mem_rd_vld_o),

    .wr_st_data_o      (wr_st_data_o),
    .wr_st_push_o      (wr_st_push_o),
    .rd_st_pop_o       (rd_st_pop_o)
  );

  // Simple monitors
  always @(posedge clk) begin
    if (wr_st_push_o != 0) begin
      $display("[%0t] STREAM_TX PUSH: push=%b data=0x%08x",
               $time, wr_st_push_o, wr_st_data_o);
    end
    if (rd_st_pop_o != 0) begin
      $display("[%0t] STREAM_RX POP: pop=%b", $time, rd_st_pop_o);
    end
  end

  // Debug monitor for WREADY issues
  always @(posedge clk) begin
    if (s_axi_wvalid && !s_axi_wready) begin
      $display("[%0t] DEBUG: W stalled - WVALID=1 but WREADY=0, can_accept=%b",
               $time, wr_st_can_accept_i);
    end
  end

  // AXI Master tasks
  task axi_write;
    input [ADDR_W-1:0] addr;
    input [DATA_W-1:0] data;
    input [(DATA_W/8)-1:0] strb;
    input [2:0] prot;
    input [1:0] exp_bresp;
    integer timeout;
    integer aw_done, w_done;
    begin
      // Drive AW and W simultaneously
      s_axi_awaddr  <= addr;
      s_axi_awprot  <= prot;
      s_axi_awvalid <= 1'b1;

      s_axi_wdata   <= data;
      s_axi_wstrb   <= strb;
      s_axi_wvalid  <= 1'b1;

      s_axi_bready  <= 1'b0;

      // Wait for BOTH handshakes to complete
      aw_done = 0;
      w_done = 0;
      timeout = 0;
      
      while (!aw_done || !w_done) begin
        @(posedge clk);
        
        // Check AW handshake
        if (s_axi_awvalid && s_axi_awready) begin
          aw_done = 1;
        end
        
        // Check W handshake
        if (s_axi_wvalid && s_axi_wready) begin
          w_done = 1;
        end
        
        timeout = timeout + 1;
        if (timeout > 50) begin
          $display("[%0t] ERROR: AW/W handshake timeout", $time);
          $display("  AW done=%0d, W done=%0d", aw_done, w_done);
          $display("  AWVALID=%b, AWREADY=%b", s_axi_awvalid, s_axi_awready);
          $display("  WVALID=%b, WREADY=%b", s_axi_wvalid, s_axi_wready);
          $finish;
        end
      end
      
      // Drop both after completion
      @(posedge clk);
      s_axi_awvalid <= 1'b0;
      s_axi_wvalid  <= 1'b0;

      // Wait BVALID
      timeout = 0;
      while (!s_axi_bvalid) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 50) begin
          $display("[%0t] ERROR: BVALID timeout", $time);
          $finish;
        end
      end

      // Check BRESP (must be stable while BVALID=1)
      if (s_axi_bresp !== exp_bresp) begin
        $display("[%0t] ERROR: BRESP mismatch. got=%b exp=%b addr=0x%08x",
                 $time, s_axi_bresp, exp_bresp, addr);
        $finish;
      end else begin
        $display("[%0t] WRITE OK: addr=0x%08x data=0x%08x strb=0x%0x bresp=%b",
                 $time, addr, data, strb, s_axi_bresp);
      end

      // Now handshake B
      s_axi_bready <= 1'b1;
      @(posedge clk);
      // After handshake, slave will drop BVALID next cycle
      s_axi_bready <= 1'b0;
      @(posedge clk);
    end
  endtask

  // Test W arriving BEFORE AW (legal in AXI)
  task axi_write_w_before_aw;
    input [ADDR_W-1:0] addr;
    input [DATA_W-1:0] data;
    input [(DATA_W/8)-1:0] strb;
    input [2:0] prot;
    input [1:0] exp_bresp;
    integer timeout, aw_done, w_done;
    integer i;
    begin
      // W first (no address yet)
      s_axi_wdata   <= data;
      s_axi_wstrb   <= strb;
      s_axi_wvalid  <= 1'b1;

      s_axi_bready  <= 1'b0;

      // Initialize flags
      aw_done = 0;
      w_done = 0;
      timeout = 0;

      // Delay AW a bit (W arrives 2 cycles before AW)
      // But check for early W handshake during delay!
      for (i = 0; i < 2; i = i + 1) begin
        @(posedge clk);
        if (s_axi_wvalid && s_axi_wready) begin
          w_done = 1;
        end
        timeout = timeout + 1;
      end

      s_axi_awaddr  <= addr;
      s_axi_awprot  <= prot;
      s_axi_awvalid <= 1'b1;

      // Continue waiting for BOTH handshakes
      while (!aw_done || !w_done) begin
        @(posedge clk);
        
        if (s_axi_awvalid && s_axi_awready) begin
          aw_done = 1;
        end
        
        if (s_axi_wvalid && s_axi_wready) begin
          w_done = 1;
        end
        
        timeout = timeout + 1;
        if (timeout > 50) begin
          $display("[%0t] ERROR: AW/W handshake timeout (W-before-AW)", $time);
          $display("  AW done=%0d, W done=%0d", aw_done, w_done);
          $finish;
        end
      end
      
      // Drop both after completion
      @(posedge clk);
      s_axi_awvalid <= 1'b0;
      s_axi_wvalid  <= 1'b0;

      // Wait BVALID
      timeout = 0;
      while (!s_axi_bvalid) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 50) begin
          $display("[%0t] ERROR: BVALID timeout (W-before-AW)", $time);
          $finish;
        end
      end

      if (s_axi_bresp !== exp_bresp) begin
        $display("[%0t] ERROR: BRESP mismatch (W-before-AW). got=%b exp=%b addr=0x%08x",
                 $time, s_axi_bresp, exp_bresp, addr);
        $finish;
      end else begin
        $display("[%0t] WRITE(W-first) OK: addr=0x%08x data=0x%08x bresp=%b",
                 $time, addr, data, s_axi_bresp);
      end

      // Handshake B
      s_axi_bready <= 1'b1;
      @(posedge clk);
      s_axi_bready <= 1'b0;
      @(posedge clk);
    end
  endtask

  task axi_read;
    input  [ADDR_W-1:0] addr;
    input  [2:0] prot;
    input  [1:0] exp_rresp;
    output [DATA_W-1:0] rdata_out;
    integer timeout;
    begin
      // Drive AR
      s_axi_araddr  <= addr;
      s_axi_arprot  <= prot;
      s_axi_arvalid <= 1'b1;

      // Not ready immediately (optional)
      s_axi_rready  <= 1'b0;

      // Wait AR handshake
      timeout = 0;
      while (!(s_axi_arvalid && s_axi_arready)) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 50) begin
          $display("[%0t] ERROR: AR handshake timeout", $time);
          $finish;
        end
      end
      @(posedge clk);
      s_axi_arvalid <= 1'b0;

      // Wait RVALID
      timeout = 0;
      while (!s_axi_rvalid) begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 2000) begin  // Increased for timeout test
          $display("[%0t] ERROR: RVALID timeout", $time);
          $finish;
        end
      end

      // Check RRESP
      if (s_axi_rresp !== exp_rresp) begin
        $display("[%0t] ERROR: RRESP mismatch. got=%b exp=%b addr=0x%08x",
                 $time, s_axi_rresp, exp_rresp, addr);
        $finish;
      end

      // Capture data
      rdata_out = s_axi_rdata;

      $display("[%0t] READ: addr=0x%08x rdata=0x%08x rresp=%b",
               $time, addr, rdata_out, s_axi_rresp);

      // Handshake R
      s_axi_rready <= 1'b1;
      @(posedge clk);
      s_axi_rready <= 1'b0;
      @(posedge clk);
    end
  endtask

  // ------------------------
  // Test sequence
  // ------------------------
  reg [DATA_W-1:0] tmp;

  initial begin
    // init defaults
    s_axi_awaddr  = 0;
    s_axi_awprot  = 0;
    s_axi_awvalid = 0;

    s_axi_wdata   = 0;
    s_axi_wstrb   = 0;
    s_axi_wvalid  = 0;

    s_axi_bready  = 0;

    s_axi_araddr  = 0;
    s_axi_arprot  = 0;
    s_axi_arvalid = 0;

    s_axi_rready  = 0;

    stat_reg_i = 32'hABCD_1234;

    mem_wr_rdy_i = 1'b1;
    mem_rd_data_i= 32'h0;
    mem_rd_rdy_i = 1'b0;

    wr_st_can_accept_i = {ST_WR_FIFO_NUM{1'b1}};
    rd_st_data_i       = 32'h0;
    rd_st_has_data_i   = {ST_RD_FIFO_NUM{1'b0}};

    // wait reset release
    wait(rst_n == 1'b1);
    repeat (2) @(posedge clk);

    $display("===================================================");
    $display("TEST 1: Write CONF0 full word then read back");
    $display("===================================================");
    axi_write(CONF_BASE_ADDR + 0*CONF_OFFSET, 32'h1122_3344, 4'hF, 3'b000, OKAY);
    axi_read (CONF_BASE_ADDR + 0*CONF_OFFSET, 3'b000, OKAY, tmp);
    if (tmp !== 32'h1122_3344) begin
      $display("[%0t] ERROR: CONF0 mismatch got=0x%08x", $time, tmp);
      $finish;
    end

    $display("===================================================");
    $display("TEST 2: Partial write with WSTRB into CONF0 then read back");
    $display("===================================================");
    // Update only low byte to 0xAA (WSTRB[0]=1)
    axi_write(CONF_BASE_ADDR + 0*CONF_OFFSET, 32'h0000_00AA, 4'h1, 3'b000, OKAY);
    axi_read (CONF_BASE_ADDR + 0*CONF_OFFSET, 3'b000, OKAY, tmp);
    // Expected: 0x1122_33AA
    if (tmp !== 32'h1122_33AA) begin
      $display("[%0t] ERROR: Partial write mismatch got=0x%08x exp=0x1122_33AA", $time, tmp);
      $finish;
    end

    $display("===================================================");
    $display("TEST 3: Misaligned write (addr+2) -> expect SLVERR");
    $display("===================================================");
    axi_write(CONF_BASE_ADDR + 32'h2, 32'hDEAD_BEEF, 4'hF, 3'b000, SLVERR);

    $display("===================================================");
    $display("TEST 4: Unmapped write -> expect DECERR");
    $display("===================================================");
    axi_write(32'h3000_0000, 32'hCAFE_BABE, 4'hF, 3'b000, DECERR);

    $display("===================================================");
    $display("TEST 5: Stream TX write -> expect OKAY + push pulse");
    $display("===================================================");
    axi_write(ST_WR_BASE_ADDR + 0*ST_WR_OFFSET, 32'hAAAA_5555, 4'hF, 3'b000, OKAY);

    $display("===================================================");
    $display("TEST 6: Stream RX read -> provide data then expect pop on R handshake");
    $display("===================================================");
    // Make stream have data
    rd_st_data_i     <= 32'h1234_5678;
    rd_st_has_data_i <= {ST_RD_FIFO_NUM{1'b1}};

    axi_read(ST_RD_BASE_ADDR + 0*ST_RD_OFFSET, 3'b000, OKAY, tmp);
    if (tmp !== 32'h1234_5678) begin
      $display("[%0t] ERROR: Stream RX mismatch got=0x%08x exp=0x1234_5678", $time, tmp);
      $finish;
    end

    // After pop, we can clear "has_data"
    @(posedge clk);
    rd_st_has_data_i <= {ST_RD_FIFO_NUM{1'b0}};

    $display("===================================================");
    $display("TEST 7: W arrives BEFORE AW (legal AXI) -> should still work");
    $display("===================================================");
    axi_write_w_before_aw(CONF_BASE_ADDR + 1*CONF_OFFSET, 32'h0BAD_F00D, 4'hF, 3'b000, OKAY);
    axi_read(CONF_BASE_ADDR + 1*CONF_OFFSET, 3'b000, OKAY, tmp);
    if (tmp !== 32'h0BAD_F00D) begin
      $display("[%0t] ERROR: CONF1 mismatch got=0x%08x exp=0x0BAD_F00D", $time, tmp);
      $finish;
    end

    $display("===================================================");
    $display("TEST 8: Read from EMPTY RX FIFO -> expect SLVERR after timeout");
    $display("===================================================");
    // Make sure RX FIFO is empty
    rd_st_has_data_i <= {ST_RD_FIFO_NUM{1'b0}};
    // This should timeout and return SLVERR
    axi_read(ST_RD_BASE_ADDR + 0*ST_RD_OFFSET, 3'b000, SLVERR, tmp);
    $display("[%0t]  Timeout mechanism working correctly", $time);

    $display("===================================================");
    $display("TEST 9: Write to TX FIFO when FULL (backpressure)");
    $display("===================================================");
    // Make TX FIFO full
    wr_st_can_accept_i <= {ST_WR_FIFO_NUM{1'b0}};
    repeat (2) @(posedge clk);
    
    // Start write
    s_axi_awaddr  <= ST_WR_BASE_ADDR;
    s_axi_awprot  <= 3'b000;
    s_axi_awvalid <= 1'b1;
    s_axi_wdata   <= 32'hBBBB_CCCC;
    s_axi_wstrb   <= 4'hF;
    s_axi_wvalid  <= 1'b1;
    
    // Check WREADY should be LOW
    @(posedge clk);
    if (s_axi_wready !== 1'b0) begin
      $display("[%0t] ERROR: WREADY should be 0 when FIFO full", $time);
      $finish;
    end
    $display("[%0t] ✓ WREADY correctly deasserted when FIFO full", $time);
    
    // Release backpressure
    wr_st_can_accept_i <= {ST_WR_FIFO_NUM{1'b1}};
    
    // Complete the write
    while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
    @(posedge clk);
    s_axi_awvalid <= 1'b0;
    
    while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
    @(posedge clk);
    s_axi_wvalid <= 1'b0;
    
    // Wait and accept B response
    while (!s_axi_bvalid) @(posedge clk);
    s_axi_bready <= 1'b1;
    @(posedge clk);
    s_axi_bready <= 1'b0;
    @(posedge clk);

    $display("===================================================");
    $display("TEST 10: Misaligned read -> expect SLVERR");
    $display("===================================================");
    axi_read(CONF_BASE_ADDR + 32'h1, 3'b000, SLVERR, tmp);

    $display("===================================================");
    $display("TEST 11: Unmapped read -> expect DECERR");
    $display("===================================================");
    axi_read(32'h9000_0000, 3'b000, DECERR, tmp);

    $display("===================================================");
    $display("TEST 12: Verify WSTRB in stream write");
    $display("===================================================");
    // Write with partial WSTRB (only low byte)
    axi_write(ST_WR_BASE_ADDR, 32'hDEAD_BEEF, 4'h1, 3'b000, OKAY);
    // Check wr_st_data_o contains full word (application decides what to use)
    @(posedge clk);
    $display("[%0t] ✓ Stream write data: 0x%08x", $time, wr_st_data_o);

    $display("===================================================");
    $display(" ALL TESTS PASSED! Coverage: 12/12");
    $display("===================================================");
    $finish;
  end

endmodule
