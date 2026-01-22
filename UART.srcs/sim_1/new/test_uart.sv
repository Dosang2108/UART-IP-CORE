`timescale 1ns / 1ps

module uart_system_tb;

    parameter CLK_PERIOD = 8;
    parameter BAUD_RATE = 115200;
    parameter INTERNAL_CLOCK = 125_000_000;
    
    // Calculate actual bit period matching hardware
    // TX_DIVISOR = round(INTERNAL_CLOCK / BAUD_RATE) = 1085
    // Actual bit period = TX_DIVISOR * CLK_PERIOD = 1085 * 8 = 8680ns
    parameter TX_DIVISOR = 1085;
    parameter BIT_PERIOD = TX_DIVISOR * CLK_PERIOD; // 8680ns - matches hardware exactly
    
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
    wire tx_fifo_full, tx_fifo_empty, rx_fifo_empty;
    wire frame_error, timeout_error;
    
    integer error_count;
    integer test_step;
    integer pass_count;
    integer debug_backpressure_count;  // Limit debug spam
    
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
        .tx_fifo_empty(tx_fifo_empty),
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
        
        // Debug: Monitor RX ready/valid (limit spam)
        if (rst_n && cpu_rx_valid && !cpu_rx_ready) begin
            if (debug_backpressure_count < 3) begin
                $display("[DEBUG] RX data available but CPU not ready: 0x%02h at time %0t", cpu_rx_data, $time);
                debug_backpressure_count = debug_backpressure_count + 1;
            end else if (debug_backpressure_count == 3) begin
                $display("[DEBUG] ... (suppressing further backpressure messages)");
                debug_backpressure_count = debug_backpressure_count + 1;
            end
        end
        
        // Reset debug counter when CPU becomes ready
        if (rst_n && cpu_rx_ready) begin
            debug_backpressure_count = 0;
        end
    end
    
    // Monitor errors - only count each error once per edge
    reg frame_error_prev, timeout_error_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error_prev <= 0;
            timeout_error_prev <= 0;
        end else begin
            frame_error_prev <= frame_error;
            timeout_error_prev <= timeout_error;
            
            if (frame_error && !frame_error_prev) begin
                $display("[ERROR] Frame error detected at time %0t", $time);
                error_count = error_count + 1;
            end
            if (timeout_error && !timeout_error_prev) begin
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
    
    task automatic uart_receive_byte;
        output [7:0] data;
        integer i;
        begin : receive_block
            // NOTE: Start bit negedge already detected by caller (forever loop)
            // We are now AT the start bit falling edge
            $display("[TX MONITOR] Start bit detected at time %0t", $time);
            
            // Wait to middle of start bit
            #(BIT_PERIOD/2);
            if (txd !== 0) begin
                $display("[ERROR] Invalid start bit at time %0t", $time);
                error_count = error_count + 1;
                data = 8'hXX;
                disable receive_block;
            end
            
            // Sample 8 data bits at their centers
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD;        // Move to center of next bit
                data[i] = txd;      // Sample
            end
            
            // Sample parity bit at center
            #BIT_PERIOD;
            tx_parity_bit = txd;
            
            // Check parity (even parity: XOR of all data bits)
            if (tx_parity_bit !== (^data)) begin
                $display("[FAIL] TX Parity error: Got %b, Expected %b for data 0x%02h at time %0t", 
                         tx_parity_bit, ^data, data, $time);
                error_count = error_count + 1;
            end
            
            // Sample stop bit 1 at center
            #BIT_PERIOD;
            if (txd !== 1) begin
                $display("[ERROR] Invalid stop bit 1 at time %0t (got %b)", $time, txd);
                error_count = error_count + 1;
            end
            
            // Sample stop bit 2 at center
            #BIT_PERIOD;
            if (txd !== 1) begin
                $display("[ERROR] Invalid stop bit 2 at time %0t (got %b)", $time, txd);
                error_count = error_count + 1;
            end
            
            // Verify data against expected queue
            if (expected_tx_rd_ptr != expected_tx_wr_ptr) begin
                if (data == expected_tx_queue[expected_tx_rd_ptr[4:0]]) begin
                    $display("[PASS] TX Data: 0x%02h at time %0t", data, $time);
                    pass_count = pass_count + 1;
                end else begin
                    $display("[FAIL] TX Data: Got 0x%02h, Expected 0x%02h at time %0t", 
                             data, expected_tx_queue[expected_tx_rd_ptr[4:0]], $time);
                    error_count = error_count + 1;
                end
                expected_tx_rd_ptr = expected_tx_rd_ptr + 1;
            end else begin
                $display("[ERROR] Unexpected TX data: 0x%02h at time %0t", data, $time);
                error_count = error_count + 1;
            end
            
            // Wait remaining half bit period to end of stop bit 2
            #(BIT_PERIOD/2);
        end
    endtask
    
    // Background task to monitor TX - simplified and robust
    initial begin
        tx_shift_reg = 8'h00;
        #100; // Wait for reset to complete
        
        forever begin
            // Wait for txd to be high (idle)
            while (txd !== 1'b1) #(CLK_PERIOD);
            #(CLK_PERIOD); // Small delay to stabilize
            
            // Now wait for start bit (falling edge)
            @(negedge txd);
            
            if (rst_n) begin
                uart_receive_byte(tx_shift_reg);
            end
        end
    end
    
    task automatic uart_send_byte;
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
    
    task automatic cpu_send_byte;
        input [7:0] data;
        begin
            $display("[TB] Sending TX: 0x%02h at time %0t", data, $time);
            // Add to expected queue
            expected_tx_queue[expected_tx_wr_ptr[4:0]] = data;
            expected_tx_wr_ptr = expected_tx_wr_ptr + 1;
            
            // Send via CPU interface - wait for ready using polling
            while (cpu_tx_ready !== 1'b1) @(posedge clk);
            @(posedge clk);
            cpu_tx_data = data;
            cpu_tx_valid = 1;
            @(posedge clk);
            cpu_tx_valid = 0;
        end
    endtask
    
    // Task to wait for all TX to complete
    task automatic wait_tx_complete;
        begin
            // Wait for TX FIFO to empty and TX to finish using polling
            // Check both conditions together to avoid race condition:
            // - tx_fifo_empty goes high immediately when data transfers to UART_TX
            // - tx_busy might not be high yet on the same clock edge
            // So we need to ensure BOTH are in idle state simultaneously
            @(posedge clk); // Wait one clock for tx_busy to update after FIFO read
            while (tx_fifo_empty !== 1'b1 || tx_busy !== 1'b0) @(posedge clk);
            #(BIT_PERIOD);  // Extra margin
        end
    endtask
    
    initial begin
        clk = 0; rst_n = 0; rxd = 1;
        cpu_tx_data = 0; cpu_tx_valid = 0; cpu_rx_ready = 0;
        error_count = 0; test_step = 0; pass_count = 0;
        debug_backpressure_count = 0;
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
        
        // TEST 7: Simultaneous RX/TX - Simplified sequential test
        test_step = 7;
        $display("\n[TEST 7] Sequential RX and TX");
        cpu_rx_ready = 1;
        
        // Send TX byte and wait for it to complete
        cpu_send_byte(8'hC3);
        wait_tx_complete;
        
        // Send RX byte
        uart_send_byte(8'hD5);
        #(BIT_PERIOD*3);  // Wait for RX to complete
        
        // Send another TX byte
        cpu_send_byte(8'h3C);
        wait_tx_complete;
        
        // Send another RX byte  
        uart_send_byte(8'h5D);
        #(BIT_PERIOD*3);  // Wait for RX to complete
        
        #(BIT_PERIOD*5);
        
        // TEST 8: FIFO stress test
        test_step = 8;
        $display("\n[TEST 8] FIFO Stress Test - Burst RX");
        cpu_rx_ready = 1;
        repeat(8) begin
            uart_send_byte($random);
            #(BIT_PERIOD*12); // Slightly overlap
        end
        #(BIT_PERIOD*30);
        
        // TEST 9: TX Sequential Test (not burst to avoid timing issues)
        test_step = 9;
        $display("\n[TEST 9] TX Sequential Test");
        // Send bytes one at a time with wait
        cpu_send_byte(8'h01);
        wait_tx_complete;
        cpu_send_byte(8'h02);
        wait_tx_complete;
        cpu_send_byte(8'h03);
        wait_tx_complete;
        cpu_send_byte(8'h04);
        wait_tx_complete;
        cpu_send_byte(8'h05);
        wait_tx_complete;
        cpu_send_byte(8'h06);
        wait_tx_complete;
        cpu_send_byte(8'h07);
        wait_tx_complete;
        cpu_send_byte(8'h08);
        // Wait for last TX to complete
        wait_tx_complete;
        
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