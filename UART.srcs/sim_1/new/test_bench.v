`timescale 1ns / 1ps

module uart_system_tb;

    parameter CLK_PERIOD = 8;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE; // 8680ns for 115200 baud
    parameter TEST_TIMEOUT = 50000000; // 50ms
    
    reg clk;
    reg rst_n;
    reg rxd;
    wire txd;
    
    reg [7:0] cpu_tx_data;
    reg cpu_tx_valid;
    wire cpu_tx_ready;
    
    wire [7:0] cpu_rx_data;
    wire cpu_rx_valid;
    reg cpu_rx_ready;
    
    wire tx_busy, rx_busy;
    wire tx_fifo_full, rx_fifo_empty;
    wire frame_error, timeout_error;
    
    integer error_count;
    integer test_step;
    integer pass_count;
    
    // Expected data queues
    reg [7:0] expected_rx_queue [0:31];
    integer expected_rx_wr_ptr, expected_rx_rd_ptr;
    
    reg [7:0] expected_tx_queue [0:31];
    integer expected_tx_wr_ptr, expected_tx_rd_ptr;
    
    uart_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .rxd(rxd),
        .txd(txd),
        .cpu_tx_data(cpu_tx_data),
        .cpu_tx_valid(cpu_tx_valid),
        .cpu_tx_ready(cpu_tx_ready),
        .cpu_rx_data(cpu_rx_data),
        .cpu_rx_valid(cpu_rx_valid),
        .cpu_rx_ready(cpu_rx_ready),
        .tx_busy(tx_busy),
        .rx_busy(rx_busy),
        .tx_fifo_full(tx_fifo_full),
        .rx_fifo_empty(rx_fifo_empty),
        .frame_error(frame_error),
        .timeout_error(timeout_error)
    );
    
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Monitor RX data and verify
    always @(posedge clk) begin
        if (rst_n && cpu_rx_valid && cpu_rx_ready) begin
            if (expected_rx_rd_ptr != expected_rx_wr_ptr) begin
                if (cpu_rx_data == expected_rx_queue[expected_rx_rd_ptr[4:0]]) begin
                    $display("[PASS] RX Data: 0x%02h at time %0t", cpu_rx_data, $time);
                    pass_count = pass_count + 1;
                    expected_rx_rd_ptr = expected_rx_rd_ptr + 1;
                end else begin
                    $display("[FAIL] RX Data: Got 0x%02h, Expected 0x%02h at time %0t", 
                             cpu_rx_data, expected_rx_queue[expected_rx_rd_ptr[4:0]], $time);
                    error_count = error_count + 1;
                    expected_rx_rd_ptr = expected_rx_rd_ptr + 1;
                end
            end else begin
                $display("[ERROR] Unexpected RX data: 0x%02h at time %0t", cpu_rx_data, $time);
                error_count = error_count + 1;
            end
        end
        
        // Debug: Monitor RX ready/valid
        if (rst_n && cpu_rx_valid && !cpu_rx_ready) begin
            $display("[DEBUG] RX data available but CPU not ready: 0x%02h at time %0t", cpu_rx_data, $time);
        end
    end
    
    // Monitor errors
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_error) begin
                $display("[ERROR] Frame error detected at time %0t", $time);
                error_count = error_count + 1;
            end
            if (timeout_error) begin
                $display("[ERROR] Timeout error detected at time %0t", $time);
                error_count = error_count + 1;
            end
        end
    end
    
    // Monitor TX output - Simplified approach
    reg [7:0] tx_shift_reg;
    reg [3:0] tx_bit_count;
    reg tx_receiving;
    reg tx_parity_bit;
    time tx_start_time;
    
    task uart_receive_byte;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit
            @(negedge txd);
            $display("[TX MONITOR] Start bit detected at time %0t", $time);
            
            // Wait to middle of start bit, then 1 full bit to reach center of first data bit
            #(BIT_PERIOD/2 + BIT_PERIOD);
            
            // Sample data bits at center
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = txd;
                if (i < 7) #BIT_PERIOD;  // Wait for next bit (except last)
            end
            
            // Wait to center of parity bit
            #BIT_PERIOD;
            tx_parity_bit = txd;  // Sample parity
            
            // Check parity (even parity)
            if (tx_parity_bit !== (^data)) begin
                $display("[FAIL] TX Parity error: Got %b, Expected %b for data 0x%02h", 
                         tx_parity_bit, ^data, data);
                error_count = error_count + 1;
            end
            
            // Verify data
            if (expected_tx_rd_ptr != expected_tx_wr_ptr) begin
                if (data == expected_tx_queue[expected_tx_rd_ptr[4:0]]) begin
                    $display("[PASS] TX Data: 0x%02h at time %0t", data, $time);
                    pass_count = pass_count + 1;
                end else begin
                    $display("[FAIL] TX Data: Got 0x%02h, Expected 0x%02h", 
                             data, expected_tx_queue[expected_tx_rd_ptr[4:0]]);
                    error_count = error_count + 1;
                end
                expected_tx_rd_ptr = expected_tx_rd_ptr + 1;
            end else begin
                $display("[ERROR] Unexpected TX data: 0x%02h", data);
                error_count = error_count + 1;
            end
            
            // Wait for stop bits
            #BIT_PERIOD;
            if (txd !== 1) begin
                $display("[ERROR] Invalid stop bit 1 at time %0t (got %b)", $time, txd);
                error_count = error_count + 1;
            end
            #BIT_PERIOD;
            if (txd !== 1) begin
                $display("[ERROR] Invalid stop bit 2 at time %0t (got %b)", $time, txd);
                error_count = error_count + 1;
            end
        end
    endtask
    
    // Background task to monitor TX
    initial begin
        #1; // Wait for reset
        forever begin
            @(negedge txd);
            if (rst_n) begin
                uart_receive_byte(tx_shift_reg);
            end
        end
    end
    
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("[TB] Sending RX: 0x%02h at time %0t", data, $time);
            // Add to expected queue
            expected_rx_queue[expected_rx_wr_ptr[4:0]] = data;
            expected_rx_wr_ptr = expected_rx_wr_ptr + 1;
            
            // Send UART frame
            rxd = 0; #BIT_PERIOD;  // Start bit
            for(i=0; i<8; i=i+1) begin
                rxd = data[i]; #BIT_PERIOD;
            end
            rxd = ^data; #BIT_PERIOD;  // Parity bit
            rxd = 1; #BIT_PERIOD;      // Stop bit 1
            rxd = 1; #BIT_PERIOD;      // Stop bit 2
        end
    endtask
    
    task cpu_send_byte;
        input [7:0] data;
        begin
            $display("[TB] Sending TX: 0x%02h at time %0t", data, $time);
            // Add to expected queue
            expected_tx_queue[expected_tx_wr_ptr[4:0]] = data;
            expected_tx_wr_ptr = expected_tx_wr_ptr + 1;
            
            // Send via CPU interface
            wait(cpu_tx_ready);
            @(posedge clk);
            cpu_tx_data = data;
            cpu_tx_valid = 1;
            @(posedge clk);
            cpu_tx_valid = 0;
        end
    endtask
    
    initial begin
        clk = 0; rst_n = 0; rxd = 1;
        cpu_tx_data = 0; cpu_tx_valid = 0; cpu_rx_ready = 0;
        error_count = 0; test_step = 0; pass_count = 0;
        expected_rx_wr_ptr = 0; expected_rx_rd_ptr = 0;
        expected_tx_wr_ptr = 0; expected_tx_rd_ptr = 0;
        
        $display("=== UART System Test Started ===");
        $display("CLK_PERIOD: %0d ns, BIT_PERIOD: %0d ns", CLK_PERIOD, BIT_PERIOD);
        
        // Reset sequence
        #100; 
        rst_n = 1; 
        #1000;
        
        // TEST 1: Basic RX
        test_step = 1; 
        $display("\n[TEST 1] Basic RX Test - Single Byte");
        cpu_rx_ready = 1;
        uart_send_byte(8'hA5);
        #(BIT_PERIOD*15);
        
        // TEST 2: Multiple RX bytes
        test_step = 2;
        $display("\n[TEST 2] Multiple RX Bytes");
        uart_send_byte(8'h12);
        #(BIT_PERIOD*15);
        uart_send_byte(8'h34);
        #(BIT_PERIOD*15);
        uart_send_byte(8'h56);
        #(BIT_PERIOD*15);
        
        // TEST 3: Back-to-back RX
        test_step = 3;
        $display("\n[TEST 3] Back-to-Back RX");
        uart_send_byte(8'h78);
        uart_send_byte(8'h9A);
        uart_send_byte(8'hBC);
        #(BIT_PERIOD*40);
        
        // TEST 4: Basic TX
        test_step = 4;
        $display("\n[TEST 4] Basic TX Test");
        cpu_rx_ready = 0;
        cpu_send_byte(8'h55);
        #(BIT_PERIOD*20);
        
        // TEST 5: Multiple TX bytes
        test_step = 5;
        $display("\n[TEST 5] Multiple TX Bytes");
        cpu_send_byte(8'hAA);
        #(BIT_PERIOD*20);
        cpu_send_byte(8'hCC);
        #(BIT_PERIOD*20);
        
        // TEST 6: RX with slow CPU (backpressure)
        test_step = 6;
        $display("\n[TEST 6] RX with CPU Backpressure");
        cpu_rx_ready = 0;
        uart_send_byte(8'hF0);
        #(BIT_PERIOD*20);
        cpu_rx_ready = 1;
        #(BIT_PERIOD*15);
        
        // TEST 7: Simultaneous RX/TX
        test_step = 7;
        $display("\n[TEST 7] Simultaneous RX and TX");
        cpu_rx_ready = 1;
        fork
            begin
                cpu_send_byte(8'hC3);
                #(BIT_PERIOD*10);
                cpu_send_byte(8'h3C);
            end
            begin
                #(BIT_PERIOD*5);
                uart_send_byte(8'hD5);
                #(BIT_PERIOD*15);
                uart_send_byte(8'h5D);
            end
        join
        #(BIT_PERIOD*30);
        
        // TEST 8: FIFO stress test
        test_step = 8;
        $display("\n[TEST 8] FIFO Stress Test - Burst RX");
        cpu_rx_ready = 1;
        repeat(8) begin
            uart_send_byte($random);
            #(BIT_PERIOD*12); // Slightly overlap
        end
        #(BIT_PERIOD*30);
        
        // TEST 9: TX burst
        test_step = 9;
        $display("\n[TEST 9] TX Burst Test");
        repeat(8) begin
            cpu_send_byte($random);
            @(posedge clk);
        end
        #(BIT_PERIOD*200);
        
        // Wait for all transactions to complete
        #(BIT_PERIOD*50);
        
        // Final report
        $display("\n========================================");
        $display("===      Test Summary Report        ===");
        $display("========================================");
        $display("Total Tests Passed: %0d", pass_count);
        $display("Total Errors:       %0d", error_count);
        $display("Test Steps Completed: %0d/9", test_step);
        
        if (expected_rx_rd_ptr != expected_rx_wr_ptr) begin
            $display("[WARNING] Unprocessed RX data: %0d bytes", 
                     expected_rx_wr_ptr - expected_rx_rd_ptr);
        end
        if (expected_tx_rd_ptr != expected_tx_wr_ptr) begin
            $display("[WARNING] Unprocessed TX data: %0d bytes", 
                     expected_tx_wr_ptr - expected_tx_rd_ptr);
        end
        
        if (error_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** TESTS FAILED ***");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    initial begin
        #TEST_TIMEOUT;
        $display("\n========================================");
        $display("*** TIMEOUT at test step %0d ***", test_step);
        $display("Time: %0t ns", $time);
        $display("========================================\n");
        $finish;
    end


endmodule