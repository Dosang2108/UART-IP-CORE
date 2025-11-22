`timescale 1ns / 1ps

module uart_comprehensive_tb;

    // Parameters
    parameter CLK_PERIOD = 8;          // 125MHz
    parameter BIT_PERIOD = 8680;       // 115200 baud
    parameter TEST_TIMEOUT = 20000000; // 20ms timeout
    
    // System Signals
    reg clk;
    reg rst_n;
    
    // UART Physical Interface
    reg rxd;
    wire txd;
    
    // CPU Interface
    reg [7:0] cpu_tx_data;
    reg cpu_tx_valid;
    wire cpu_tx_ready;
    
    wire [7:0] cpu_rx_data;
    wire cpu_rx_valid;
    reg cpu_rx_ready;
    
    // Status Signals
    wire tx_busy;
    wire rx_busy;
    wire tx_fifo_full;
    wire rx_fifo_empty;
    wire frame_error;
    wire timeout_error;
    
    // Test Control
    integer test_case;
    integer error_count;
    integer warning_count;
    integer total_tx_bytes;
    integer total_rx_bytes;
    integer tx_monitor_count;
    integer rx_monitor_count;
    
    // Data Storage
    reg [7:0] tx_expected_data [0:255];
    reg [7:0] tx_captured_data [0:255];
    reg [7:0] rx_expected_data [0:255];
    reg [7:0] rx_captured_data [0:255];
    
    // Performance Metrics
    real total_simulation_time;
    real start_time, end_time;
    integer tx_fifo_full_count;
    integer rx_fifo_full_count;
    
    // UUT Instantiation
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
    
    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // =============================================
    // TEST TASKS
    // =============================================
    
    // Task: Send UART byte with configurable parameters
    task uart_send_byte;
        input [7:0] data;
        input parity_error;
        input invalid_stop_bit;
        input real jitter; // Timing jitter in nanoseconds
        integer i;
        real actual_bit_period;
        begin
            actual_bit_period = BIT_PERIOD + jitter;
            
            if (parity_error) 
                $display("[UART_TX_TASK] Sending: 0x%02h WITH PARITY ERROR (jitter: %0.1fns)", data, jitter);
            else if (invalid_stop_bit)
                $display("[UART_TX_TASK] Sending: 0x%02h WITH INVALID STOP BIT (jitter: %0.1fns)", data, jitter);
            else
                $display("[UART_TX_TASK] Sending: 0x%02h (jitter: %0.1fns)", data, jitter);
            
            // Start bit
            rxd = 1'b0;
            #(actual_bit_period);
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rxd = data[i];
                #(actual_bit_period);
            end
            
            // Parity bit
            if (parity_error)
                rxd = ~(^data); // Wrong parity
            else
                rxd = ^data;    // Correct even parity
            #(actual_bit_period);
            
            // Stop bits
            if (invalid_stop_bit) begin
                rxd = 1'b0;     // Invalid stop bit
                #(actual_bit_period);
                rxd = 1'b1;
            end else begin
                rxd = 1'b1;     // Valid stop bits
                #(actual_bit_period);
                rxd = 1'b1;
            end
            #(actual_bit_period);
        end
    endtask
    
    // Task: Send burst of UART bytes
    task uart_send_burst;
        input [7:0] data [];
        input integer burst_size;
        input real min_jitter;
        input real max_jitter;
        integer i;
        real jitter;
        begin
            $display("[UART_BURST] Starting burst of %0d bytes", burst_size);
            for (i = 0; i < burst_size; i = i + 1) begin
                // Calculate random jitter
                jitter = min_jitter + ($random % integer'(max_jitter - min_jitter));
                uart_send_byte(data[i], 0, 0, jitter);
                
                // Store expected data
                if (total_rx_bytes < 256) begin
                    rx_expected_data[total_rx_bytes] = data[i];
                    total_rx_bytes = total_rx_bytes + 1;
                end
                
                // Small random delay between bytes
                #(($random % 100) + 50);
            end
            $display("[UART_BURST] Burst transmission completed");
        end
    endtask
    
    // Task: CPU send data with flow control
    task cpu_send_data;
        input [7:0] data;
        input integer max_wait_cycles;
        integer wait_count;
        begin
            wait_count = 0;
            
            // Wait for TX ready with timeout
            while (cpu_tx_ready !== 1'b1 && wait_count < max_wait_cycles) begin
                @(posedge clk);
                wait_count = wait_count + 1;
            end
            
            if (cpu_tx_ready === 1'b1) begin
                @(posedge clk);
                cpu_tx_data = data;
                cpu_tx_valid = 1'b1;
                @(posedge clk);
                cpu_tx_valid = 1'b0;
                
                // Store expected data
                if (total_tx_bytes < 256) begin
                    tx_expected_data[total_tx_bytes] = data;
                    total_tx_bytes = total_tx_bytes + 1;
                end
                
                $display("[CPU_TX_TASK] Sent: 0x%02h (waited %0d cycles)", data, wait_count);
            end else begin
                $display("[CPU_TX_TASK] TIMEOUT: Could not send 0x%02h (FIFO full)", data);
                warning_count = warning_count + 1;
            end
        end
    endtask
    
    // Task: CPU send burst with backpressure handling
    task cpu_send_burst;
        input [7:0] data [];
        input integer burst_size;
        input integer inter_byte_delay;
        integer i;
        begin
            $display("[CPU_BURST] Starting CPU burst of %0d bytes", burst_size);
            for (i = 0; i < burst_size; i = i + 1) begin
                cpu_send_data(data[i], 1000); // 1000 cycle timeout
                
                // Inter-byte delay
                repeat (inter_byte_delay) @(posedge clk);
            end
            $display("[CPU_BURST] CPU burst transmission completed");
        end
    endtask
    
    // =============================================
    // MONITORS
    // =============================================
    
    // TX Monitor with robust timing
    reg [7:0] current_tx_byte;
    integer tx_bit_count;
    reg tx_monitoring;
    
    initial begin
        tx_monitoring = 0;
        forever begin
            // Wait for start bit with timeout
            wait(txd === 1'b0);
            tx_monitoring = 1;
            current_tx_byte = 8'h00;
            tx_bit_count = 0;
            
            // Wait to middle of first data bit
            #(BIT_PERIOD * 1.5);
            
            // Sample data bits (LSB first)
            for (tx_bit_count = 0; tx_bit_count < 8; tx_bit_count = tx_bit_count + 1) begin
                current_tx_byte[tx_bit_count] = txd;
                #(BIT_PERIOD);
            end
            
            // Skip parity and stop bits
            #(BIT_PERIOD * 3);
            
            // Store captured data
            if (tx_monitor_count < 256) begin
                tx_captured_data[tx_monitor_count] = current_tx_byte;
                tx_monitor_count = tx_monitor_count + 1;
                $display("[TX_MONITOR] Captured: 0x%02h", current_tx_byte);
            end
            
            tx_monitoring = 0;
            // Prevent false start bit detection
            #(BIT_PERIOD / 2);
        end
    end
    
    // RX Data Monitor
    always @(posedge clk) begin
        if (cpu_rx_valid && cpu_rx_ready) begin
            if (rx_monitor_count < 256) begin
                rx_captured_data[rx_monitor_count] = cpu_rx_data;
                rx_monitor_count = rx_monitor_count + 1;
            end
            $display("[RX_MONITOR] CPU Received: 0x%02h", cpu_rx_data);
        end
    end
    
    // Error Monitor
    always @(posedge frame_error) begin
        $display("[ERROR_MONITOR] Frame error detected at time %0t ns", $time);
        error_count = error_count + 1;
    end
    
    always @(posedge timeout_error) begin
        $display("[ERROR_MONITOR] Timeout error detected at time %0t ns", $time);
        error_count = error_count + 1;
    end
    
    // Performance Monitor
    always @(posedge clk) begin
        if (tx_fifo_full) begin
            tx_fifo_full_count = tx_fifo_full_count + 1;
        end
        if (rx_fifo_empty === 1'b0 && cpu_rx_ready === 1'b0) begin
            rx_fifo_full_count = rx_fifo_full_count + 1;
        end
    end
    
    // =============================================
    // TEST CASES
    // =============================================
    
    // Test Case 1: Basic Functionality
    task test_basic_functionality;
        begin
            test_case = 1;
            $display("\n=== TEST CASE %0d: Basic Functionality ===", test_case);
            
            // Test single byte TX
            cpu_send_data(8'h55, 100);
            #(BIT_PERIOD * 20);
            
            // Test single byte RX
            uart_send_byte(8'hAA, 0, 0, 0);
            #(BIT_PERIOD * 10);
            
            // Test multiple bytes
            cpu_send_burst('{8'h01, 8'h02, 8'h03, 8'h04}, 4, 10);
            #(BIT_PERIOD * 50);
            
            $display("[TEST_CASE_%0d] Basic functionality test completed", test_case);
        end
    endtask
    
    // Test Case 2: FIFO Stress Test
    task test_fifo_stress;
        reg [7:0] stress_data [0:31];
        integer i;
        begin
            test_case = 2;
            $display("\n=== TEST CASE %0d: FIFO Stress Test ===", test_case);
            
            // Generate test data
            for (i = 0; i < 32; i = i + 1) begin
                stress_data[i] = 8'h40 + i;
            end
            
            // Fill TX FIFO quickly
            cpu_send_burst(stress_data, 32, 1);
            
            // Wait for TX to drain
            #(BIT_PERIOD * 500);
            
            // Fill RX FIFO
            cpu_rx_ready = 1'b0; // Stop reading
            uart_send_burst(stress_data, 16, -100.0, 100.0); // With jitter
            
            // Wait then start reading
            #(BIT_PERIOD * 100);
            cpu_rx_ready = 1'b1;
            #(BIT_PERIOD * 200);
            
            $display("[TEST_CASE_%0d] FIFO stress test completed", test_case);
        end
    endtask
    
    // Test Case 3: Error Conditions
    task test_error_conditions;
        begin
            test_case = 3;
            $display("\n=== TEST CASE %0d: Error Conditions ===", test_case);
            
            // Test parity error
            uart_send_byte(8'hF0, 1, 0, 0); // Parity error
            #(BIT_PERIOD * 15);
            
            // Test invalid stop bit
            uart_send_byte(8'hF1, 0, 1, 0); // Invalid stop bit
            #(BIT_PERIOD * 15);
            
            // Test with timing jitter
            uart_send_byte(8'hF2, 0, 0, 50.0); // Positive jitter
            uart_send_byte(8'hF3, 0, 0, -50.0); // Negative jitter
            #(BIT_PERIOD * 30);
            
            $display("[TEST_CASE_%0d] Error conditions test completed", test_case);
        end
    endtask
    
    // Test Case 4: Simultaneous TX/RX
    task test_simultaneous_operation;
        reg [7:0] tx_data [0:7];
        reg [7:0] rx_data [0:7];
        integer i;
        begin
            test_case = 4;
            $display("\n=== TEST CASE %0d: Simultaneous TX/RX ===", test_case);
            
            // Generate test data
            for (i = 0; i < 8; i = i + 1) begin
                tx_data[i] = 8'hC0 + i;
                rx_data[i] = 8'hD0 + i;
            end
            
            fork
                // TX thread
                begin
                    cpu_send_burst(tx_data, 8, 20);
                end
                
                // RX thread
                begin
                    #(BIT_PERIOD * 5);
                    uart_send_burst(rx_data, 8, -50.0, 50.0);
                end
                
                // Monitor thread
                begin
                    #(BIT_PERIOD * 100);
                    $display("[TEST_CASE_%0d] Simultaneous operation in progress...", test_case);
                end
            join
            
            #(BIT_PERIOD * 100);
            $display("[TEST_CASE_%0d] Simultaneous operation test completed", test_case);
        end
    endtask
    
    // Test Case 5: Performance and Timing
    task test_performance;
        reg [7:0] perf_data [0:15];
        integer i;
        real perf_start_time, perf_end_time;
        begin
            test_case = 5;
            $display("\n=== TEST CASE %0d: Performance Test ===", test_case);
            
            // Generate test data
            for (i = 0; i < 16; i = i + 1) begin
                perf_data[i] = 8'h20 + i;
            end
            
            // Measure TX performance
            perf_start_time = $time;
            cpu_send_burst(perf_data, 16, 1);
            
            // Wait for all transmissions to complete
            wait(tx_busy === 1'b0);
            #(BIT_PERIOD * 10);
            perf_end_time = $time;
            
            $display("[TEST_CASE_%0d] TX Performance: %0d bytes in %0.0f ns", 
                     test_case, 16, perf_end_time - perf_start_time);
            $display("[TEST_CASE_%0d] Average TX time per byte: %0.0f ns", 
                     test_case, (perf_end_time - perf_start_time) / 16);
            
            // Measure RX performance
            cpu_rx_ready = 1'b1;
            perf_start_time = $time;
            uart_send_burst(perf_data, 16, 0, 0);
            
            // Wait for all receptions to complete
            wait(rx_busy === 1'b0);
            #(BIT_PERIOD * 10);
            perf_end_time = $time;
            
            $display("[TEST_CASE_%0d] RX Performance: %0d bytes in %0.0f ns", 
                     test_case, 16, perf_end_time - perf_start_time);
            $display("[TEST_CASE_%0d] Average RX time per byte: %0.0f ns", 
                     test_case, (perf_end_time - perf_start_time) / 16);
        end
    endtask
    
    // Test Case 6: Reset Recovery
    task test_reset_recovery;
        begin
            test_case = 6;
            $display("\n=== TEST CASE %0d: Reset Recovery ===", test_case);
            
            // Start transmission
            cpu_send_data(8'hAA, 100);
            #(BIT_PERIOD * 5);
            
            // Assert reset during transmission
            $display("[TEST_CASE_%0d] Asserting reset during active transmission", test_case);
            rst_n = 1'b0;
            #(CLK_PERIOD * 10);
            
            // Check if system is idle
            if (tx_busy !== 1'b0 || rx_busy !== 1'b0) begin
                $display("[TEST_CASE_%0d] WARNING: System not fully idle after reset", test_case);
                warning_count = warning_count + 1;
            end
            
            // Release reset
            rst_n = 1'b1;
            #(CLK_PERIOD * 20);
            
            // Verify system can operate after reset
            cpu_send_data(8'hBB, 100);
            #(BIT_PERIOD * 10);
            uart_send_byte(8'hCC, 0, 0, 0);
            #(BIT_PERIOD * 15);
            
            $display("[TEST_CASE_%0d] Reset recovery test completed", test_case);
        end
    endtask
    
    // Test Case 7: Corner Cases
    task test_corner_cases;
        begin
            test_case = 7;
            $display("\n=== TEST CASE %0d: Corner Cases ===", test_case);
            
            // Test minimum data value
            cpu_send_data(8'h00, 100);
            uart_send_byte(8'h00, 0, 0, 0);
            #(BIT_PERIOD * 20);
            
            // Test maximum data value
            cpu_send_data(8'hFF, 100);
            uart_send_byte(8'hFF, 0, 0, 0);
            #(BIT_PERIOD * 20);
            
            // Test rapid back-to-back transmission
            fork
                begin
                    repeat (5) begin
                        cpu_send_data(8'h11, 100);
                        #(CLK_PERIOD * 2);
                    end
                end
                begin
                    #(BIT_PERIOD * 10);
                    repeat (5) begin
                        uart_send_byte(8'h22, 0, 0, 0);
                        #(BIT_PERIOD * 2);
                    end
                end
            join
            
            #(BIT_PERIOD * 50);
            $display("[TEST_CASE_%0d] Corner cases test completed", test_case);
        end
    endtask
    
    // =============================================
    // VERIFICATION FUNCTIONS
    // =============================================
    
    // Verify TX data
    function integer verify_tx_data;
        integer i, errors;
        begin
            errors = 0;
            $display("\n--- TX Data Verification ---");
            for (i = 0; i < tx_monitor_count && i < total_tx_bytes; i = i + 1) begin
                if (tx_captured_data[i] === tx_expected_data[i]) begin
                    $display("TX[%0d] PASS: Expected=0x%02h, Received=0x%02h", 
                             i, tx_expected_data[i], tx_captured_data[i]);
                end else begin
                    $display("TX[%0d] FAIL: Expected=0x%02h, Received=0x%02h", 
                             i, tx_expected_data[i], tx_captured_data[i]);
                    errors = errors + 1;
                end
            end
            verify_tx_data = errors;
        end
    endfunction
    
    // Verify RX data
    function integer verify_rx_data;
        integer i, errors;
        begin
            errors = 0;
            $display("\n--- RX Data Verification ---");
            for (i = 0; i < rx_monitor_count && i < total_rx_bytes; i = i + 1) begin
                if (rx_captured_data[i] === rx_expected_data[i]) begin
                    $display("RX[%0d] PASS: Expected=0x%02h, Received=0x%02h", 
                             i, rx_expected_data[i], rx_captured_data[i]);
                end else begin
                    $display("RX[%0d] FAIL: Expected=0x%02h, Received=0x%02h", 
                             i, rx_expected_data[i], rx_captured_data[i]);
                    errors = errors + 1;
                end
            end
            verify_rx_data = errors;
        end
    endfunction
    
    // =============================================
    // MAIN TEST SEQUENCE
    // =============================================
    
    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        rxd = 1'b1;
        cpu_tx_data = 8'h00;
        cpu_tx_valid = 1'b0;
        cpu_rx_ready = 1'b1;
        
        test_case = 0;
        error_count = 0;
        warning_count = 0;
        total_tx_bytes = 0;
        total_rx_bytes = 0;
        tx_monitor_count = 0;
        rx_monitor_count = 0;
        tx_fifo_full_count = 0;
        rx_fifo_full_count = 0;
        
        $display("================================================");
        $display("UART COMPREHENSIVE TESTBENCH");
        $display("================================================");
        
        start_time = $time;
        
        // Extended reset sequence
        #100;
        rst_n = 1'b1;
        #1000;
        
        $display("[INIT] Reset completed, starting comprehensive tests...");
        
        // Execute all test cases
        test_basic_functionality();
        #1000;
        
        test_fifo_stress();
        #1000;
        
        test_error_conditions();
        #1000;
        
        test_simultaneous_operation();
        #1000;
        
        test_performance();
        #1000;
        
        test_reset_recovery();
        #1000;
        
        test_corner_cases();
        #1000;
        
        // Final verification and reporting
        end_time = $time;
        total_simulation_time = end_time - start_time;
        
        // Data verification
        error_count = error_count + verify_tx_data();
        error_count = error_count + verify_rx_data();
        
        // Final comprehensive report
        $display("\n================================================");
        $display("COMPREHENSIVE TEST SUMMARY");
        $display("================================================");
        $display("Simulation Time: %0.0f ns", total_simulation_time);
        $display("Test Cases Executed: %0d", test_case);
        $display("Total TX Bytes: %0d", total_tx_bytes);
        $display("Total RX Bytes: %0d", total_rx_bytes);
        $display("TX Frames Verified: %0d", tx_monitor_count);
        $display("RX Frames Verified: %0d", rx_monitor_count);
        $display("TX FIFO Full Events: %0d", tx_fifo_full_count);
        $display("RX FIFO Full Events: %0d", rx_fifo_full_count);
        $display("Errors Detected: %0d", error_count);
        $display("Warnings: %0d", warning_count);
        $display("");
        $display("Final Status:");
        $display("  TX Busy: %b", tx_busy);
        $display("  RX Busy: %b", rx_busy);
        $display("  TX FIFO Full: %b", tx_fifo_full);
        $display("  RX FIFO Empty: %b", rx_fifo_empty);
        $display("  Frame Error: %b", frame_error);
        $display("  Timeout Error: %b", timeout_error);
        
        if (error_count == 0) begin
            $display("\n✓✓✓ ALL TESTS PASSED ✓✓✓");
        end else begin
            $display("\n!!! %0d TESTS FAILED !!!", error_count);
        end
        
        $display("================================================");
        
        // End simulation
        #1000;
        $finish;
    end
    
    // Timeout protection
    initial begin
        #(TEST_TIMEOUT);
        $display("\n!!! TEST TIMEOUT - SIMULATION TOO LONG !!!");
        $display("Current Test Case: %0d", test_case);
        $display("Errors: %0d, Warnings: %0d", error_count, warning_count);
        $finish;
    end

endmodule