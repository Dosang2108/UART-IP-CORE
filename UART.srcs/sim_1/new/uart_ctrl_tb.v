`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/21/2026 08:18:46 PM
// Design Name: 
// Module Name: uart_ctrl_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench for UART Controller with AXI4-Lite interface
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module uart_ctrl_tb();

    // Parameters - sử dụng baud rate nhanh hơn để giảm thời gian simulation
    parameter DATA_WIDTH = 8;
    parameter DATA_W = 32;
    parameter ADDR_W = 32;
    parameter INTERNAL_CLOCK = 125000000;
    parameter BAUD_RATE = 115200;
    parameter FIFO_DEPTH = 16;
    parameter CLK_PERIOD = 8;  // 125MHz = 8ns period
    
    // AXI Address Map
    parameter ADDR_STATUS   = 32'h2000_0008;
    parameter ADDR_TX_FIFO  = 32'h2000_0010;
    parameter ADDR_RX_FIFO  = 32'h2000_0020;
    
    // Testbench signals
    reg clk;
    reg rst_n;
    
    // UART Physical Interface
    wire rxd;
    wire txd;
    
    // AXI4-Lite Interface
    reg  [ADDR_W-1:0]   s_axi_awaddr;
    reg  [2:0]          s_axi_awprot;
    reg                 s_axi_awvalid;
    wire                s_axi_awready;
    reg  [DATA_W-1:0]   s_axi_wdata;
    reg  [(DATA_W/8)-1:0] s_axi_wstrb;
    reg                 s_axi_wvalid;
    wire                s_axi_wready;
    wire [1:0]          s_axi_bresp;
    wire                s_axi_bvalid;
    reg                 s_axi_bready;
    reg  [ADDR_W-1:0]   s_axi_araddr;
    reg  [2:0]          s_axi_arprot;
    reg                 s_axi_arvalid;
    wire                s_axi_arready;
    wire [DATA_W-1:0]   s_axi_rdata;
    wire [1:0]          s_axi_rresp;
    wire                s_axi_rvalid;
    reg                 s_axi_rready;
    
    // UART loopback connection
    wire uart_loopback;
    assign uart_loopback = txd;
    assign rxd = uart_loopback;
    
    // Test variables
    integer i;
    reg [7:0] test_data;
    reg [DATA_W-1:0] read_data;
    
    // DUT instantiation
    uart_ctrl #(
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .INTERNAL_CLOCK(INTERNAL_CLOCK),
        .BAUD_RATE(BAUD_RATE),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rxd(rxd),
        .txd(txd),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // AXI4-Lite Write Task
    task axi_write;
        input [ADDR_W-1:0] addr;
        input [DATA_W-1:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            s_axi_awprot = 0;
            s_axi_wdata = data;
            s_axi_wstrb = 4'b1111;
            s_axi_wvalid = 1;
            s_axi_bready = 1;
            
            // Wait for address acceptance
            wait(s_axi_awready);
            @(posedge clk);
            s_axi_awvalid = 0;
            
            // Wait for data acceptance
            wait(s_axi_wready);
            @(posedge clk);
            s_axi_wvalid = 0;
            
            // Wait for write response
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready = 0;
            
            if (s_axi_bresp != 2'b00) begin
                $display("[%0t] ERROR: AXI Write to 0x%h failed with response: %b", $time, addr, s_axi_bresp);
            end else begin
                $display("[%0t] AXI Write: addr=0x%h, data=0x%h", $time, addr, data);
            end
        end
    endtask
    
    // AXI4-Lite Read Task
    task axi_read;
        input [ADDR_W-1:0] addr;
        output [DATA_W-1:0] data;
        begin
            @(posedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            s_axi_arprot = 0;
            s_axi_rready = 1;
            
            // Wait for address acceptance
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 0;
            
            // Wait for read data
            wait(s_axi_rvalid);
            @(posedge clk);
            data = s_axi_rdata;
            s_axi_rready = 0;
            
            if (s_axi_rresp != 2'b00) begin
                $display("[%0t] ERROR: AXI Read from 0x%h failed with response: %b", $time, addr, s_axi_rresp);
            end else begin
                //$display("[%0t] AXI Read: addr=0x%h, data=0x%h", $time, addr, data);
            end
        end
    endtask
    
    // Task: Wait until RX FIFO has data
    task wait_rx_data;
        reg [DATA_W-1:0] status;
        begin
            $display("[%0t] Waiting for RX data...", $time);
            axi_read(ADDR_STATUS, status);
            while (status[1] == 1) begin  // bit 1 = rx_fifo_empty
                #(CLK_PERIOD * 10);
                axi_read(ADDR_STATUS, status);
            end
            $display("[%0t] RX data available!", $time);
        end
    endtask
    
    // Task: Wait until TX FIFO is not full
    task wait_tx_ready;
        reg [DATA_W-1:0] status;
        begin
            axi_read(ADDR_STATUS, status);
            while (status[0] == 1) begin  // bit 0 = tx_fifo_full
                $display("[%0t] TX FIFO full, waiting...", $time);
                #(CLK_PERIOD * 100);
                axi_read(ADDR_STATUS, status);
            end
        end
    endtask
    
    // Initialize AXI signals
    initial begin
        s_axi_awaddr = 0;
        s_axi_awprot = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arprot = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
    end
    
    // Main test sequence
    initial begin
        $display("========================================");
        $display("UART Controller Testbench Started");
        $display("Clock Period: %0d ns", CLK_PERIOD);
        $display("Baud Rate: %0d", BAUD_RATE);
        $display("========================================");
        
        // Reset sequence
        rst_n = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);
        
        $display("\n[TEST 1] Read Status Register");
        axi_read(ADDR_STATUS, read_data);
        $display("Status Register = 0x%h", read_data);
        $display("  tx_fifo_full = %b", read_data[0]);
        $display("  rx_fifo_empty = %b", read_data[1]);
        $display("  tx_busy = %b", read_data[4]);
        $display("  rx_busy = %b", read_data[5]);
        
        #(CLK_PERIOD * 20);
        
        $display("\n[TEST 2] Write Single Byte to TX FIFO (Loopback Test)");
        test_data = 8'hA5;
        wait_tx_ready();
        axi_write(ADDR_TX_FIFO, {24'h0, test_data});
        
        $display("\n[TEST 3] Wait and Read Received Byte from RX FIFO");
        wait_rx_data();
        axi_read(ADDR_RX_FIFO, read_data);
        if (read_data[7:0] == test_data) begin
            $display("SUCCESS: Loopback data matched! Sent: 0x%h, Received: 0x%h", test_data, read_data[7:0]);
        end else begin
            $display("ERROR: Loopback data mismatch! Sent: 0x%h, Received: 0x%h", test_data, read_data[7:0]);
        end
        
        #(CLK_PERIOD * 100);
        
        $display("\n[TEST 4] Write Multiple Bytes");
        for (i = 0; i < 5; i = i + 1) begin
            test_data = 8'h30 + i;  // ASCII '0', '1', '2', '3', '4'
            $display("Sending byte %0d: 0x%h (ASCII '%c')", i, test_data, test_data);
            wait_tx_ready();
            axi_write(ADDR_TX_FIFO, {24'h0, test_data});
            #(CLK_PERIOD * 100);  // Delay between writes
        end
        
        $display("\n[TEST 5] Read Multiple Bytes from RX FIFO");
        for (i = 0; i < 5; i = i + 1) begin
            wait_rx_data();
            axi_read(ADDR_RX_FIFO, read_data);
            test_data = 8'h30 + i;
            if (read_data[7:0] == test_data) begin
                $display("  [PASS]: Byte %0d MATCH: Expected 0x%h, Got 0x%h (ASCII '%c')", i, test_data, read_data[7:0], read_data[7:0]);
            end else begin
                $display("  [FALSE]: Byte %0d ERROR: Expected 0x%h, Got 0x%h (ASCII '%c')", i, test_data, read_data[7:0], read_data[7:0]);
            end
        end
        
        #(CLK_PERIOD * 100);
        
        $display("\n[TEST 6] Check Status Register After Operations");
        axi_read(ADDR_STATUS, read_data);
        $display("Final Status Register = 0x%h", read_data);
        
        #(CLK_PERIOD * 100);
        
        $display("\n========================================");
        $display("UART Controller Testbench Completed");
        $display("========================================");
        
        #1000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000000;  // 50ms timeout
        $display("\n========================================");
        $display("ERROR: Simulation Timeout!");
        $display("========================================");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("uart_ctrl_tb.vcd");
        $dumpvars(0, uart_ctrl_tb);
    end

endmodule
