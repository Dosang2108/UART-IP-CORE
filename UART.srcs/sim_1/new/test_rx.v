`timescale 1ns/1ps

module test_uc_rx_fixed;

    parameter CLK_PERIOD = 8;          // 125MHz
    parameter BIT_PERIOD = 8680;       // 115200 baud
    parameter BAUD_DIVIDER = 1085;     // 125000000 / 115200 ≈ 1085
    
    reg clk, rst_n, RX;
    reg baudrate_clk_en;
    wire transaction_en;
    wire [7:0] data_out_rx;
    wire fifo_wr, frame_error, timeout_error;
    // Baud rate counter
    reg [10:0] baud_counter;
    
    uart_rx uut (
        .clk(clk),
        .rst_n(rst_n),
        .RX(RX),
        .baudrate_clk_en(baudrate_clk_en),
        .transaction_en(transaction_en),
        .data_out_rx(data_out_rx),
        .fifo_wr(fifo_wr),
        .frame_error(frame_error),
        .timeout_error(timeout_error)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Baud rate generator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= 0;
            baudrate_clk_en <= 0;
        end else begin
            if (baud_counter == BAUD_DIVIDER - 1) begin
                baud_counter <= 0;
                baudrate_clk_en <= 1;
            end else begin
                baud_counter <= baud_counter + 1;
                baudrate_clk_en <= 0;
            end
        end
    end
    
    // Task to send UART frame with fixed configuration
    task uart_send_frame;
        input [7:0] data;
        integer i;
        begin
            $display("[TX] Sending frame: 0x%02h", data);
            
            // Start bit
            RX = 1'b0;
            #(BIT_PERIOD);
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                RX = data[i];
                #(BIT_PERIOD);
            end
            
            // Even parity bit
            RX = ^data; // Even parity
            #(BIT_PERIOD);
            
            // Two stop bits
            RX = 1'b1;
            #(BIT_PERIOD);
            RX = 1'b1;
            #(BIT_PERIOD);
            
            $display("[TX] Frame sent: 0x%02h", data);
        end
    endtask
    
    // Test sequence
    initial begin
        clk = 0;
        rst_n = 0;
        RX = 1'b1;
        baud_counter = 0;
        
        // Create VCD file for waveform analysis
        $dumpfile("uart_rx_fixed.vcd");
        $dumpvars(0, test_uc_rx_fixed);
        
        $display("=== UART RX Fixed Configuration Test ===");
        $display("Configuration: 8-bit data, Even parity, 2 stop bits");
        
        // Reset
        #100;
        rst_n = 1;
        #1000;
        
        $display("Reset completed, starting tests...");
        
        // Test 1: Simple byte
        $display("\n--- Test 1: Byte 0x55 ---");
        uart_send_frame(8'h55); // 01010101 - Even parity should be 0
        #(BIT_PERIOD * 4);
        
        $display("\n--- Test 2: Byte 0xAA ---");
        uart_send_frame(8'hAA); // 10101010 - Even parity should be 0  
        #(BIT_PERIOD * 4);
        
        $display("\n--- Test 3: Byte 0xbb ---");
        uart_send_frame(8'hbb); // 01011011 - Even parity should be 0
        #(BIT_PERIOD * 4);
        
        // Test 2: Another byte
        $display("\n--- Test 4: Byte 0xCC ---");
        uart_send_frame(8'hcc); // 11001100 - Even parity should be 0  
        #(BIT_PERIOD * 4);
        
        
        // Test 1: Simple byte
        $display("\n--- Test 1: Byte 0x12 ---");
        uart_send_frame(8'h12); // 00010010 - Even parity should be 0
        #(BIT_PERIOD * 4);
        
        // Test 2: Another byte
        $display("\n--- Test 2: Byte 0x34 ---");
        uart_send_frame(8'h34); // 00110100 - Even parity should be 0  
        #(BIT_PERIOD * 4);
        
        // Test 1: Simple byte
        $display("\n--- Test 3: Byte 0xcd ---");
        uart_send_frame(8'hcd); // 11001101 - Even parity should be 0
        #(BIT_PERIOD * 4);
        
        // Test 2: Another byte
        $display("\n--- Test 4: Byte 0x99 ---");
        uart_send_frame(8'h99); // 10011001 - Even parity should be 0  
        #(BIT_PERIOD * 4);


        // Test 3: Byte with parity error (for testing)
        $display("\n--- Test 3: Byte 0x57 (correct parity) ---");
        uart_send_frame(8'h57); // 01010111 - Even parity should be 1
        #(BIT_PERIOD * 4);
        
        // Test 4: Sequential bytes
        $display("\n--- Test 4: Sequential Bytes ---");
        uart_send_frame(8'h01);
        #(BIT_PERIOD * 2);
        uart_send_frame(8'h02);
        #(BIT_PERIOD * 2);
        uart_send_frame(8'h03);
        #(BIT_PERIOD * 4);
        
        // Test 5: All zeros and ones
        $display("\n--- Test 5: Special Patterns ---");
        uart_send_frame(8'h00); // All zeros - Even parity should be 0
        #(BIT_PERIOD * 3);
        uart_send_frame(8'hFF); // All ones - Even parity should be 0
        #(BIT_PERIOD * 3);
        
        // Final delay
        #(BIT_PERIOD * 10);
        $display("\n=== All Tests Completed ===");
        $finish;
    end
    
    // Monitor for received data
    always @(posedge fifo_wr) begin
        $display("[MONITOR] FIFO Write: data=0x%02h, valid_flag=%b", 
                 data_out_rx, transaction_en);
    end
    
    // Monitor transaction state
    always @(posedge clk) begin
        if (baudrate_clk_en) begin
            $display("[BAUD] Baud clock enable, RX=%b", RX);
        end
    end
    
    // Timeout protection
    initial begin
        #5000000; // 5ms timeout
        $display("!!! TIMEOUT: Simulation took too long !!!");
        $finish;
    end

endmodule