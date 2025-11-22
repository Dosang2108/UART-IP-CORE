`timescale 1ns / 1ps

module uart_system_tb;

    parameter CLK_PERIOD = 8;
    parameter BIT_PERIOD = 8680;
    parameter TEST_TIMEOUT = 10000000; // 10ms
    
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
    
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("[TB] Sending: 0x%02h", data);
            rxd = 0; #BIT_PERIOD;
            for(i=0; i<8; i=i+1) begin
                rxd = data[i]; #BIT_PERIOD;
            end
            rxd = ^data; #BIT_PERIOD;
            rxd = 1; #BIT_PERIOD;
            rxd = 1; #BIT_PERIOD;
        end
    endtask
    
    initial begin
        clk = 0; rst_n = 0; rxd = 1;
        cpu_tx_data = 0; cpu_tx_valid = 0; cpu_rx_ready = 0;
        error_count = 0; test_step = 0;
        
        $display("=== UART Test Started ===");
        
        // Reset
        #100; rst_n = 1; #1000;
        test_step = 1; $display("[TEST 1] Reset");
        
        // Test RX
        test_step = 2; $display("[TEST 2] RX Test");
        cpu_rx_ready = 1;
        uart_send_byte(8'h12); #(BIT_PERIOD*10);
        uart_send_byte(8'h34); #(BIT_PERIOD*10);
        uart_send_byte(8'h56); #(BIT_PERIOD*10);
        
        // Test TX
        test_step = 3; $display("[TEST 3] TX Test");
        cpu_rx_ready = 0;
        wait(cpu_tx_ready);
        @(posedge clk); cpu_tx_data = 8'h55; cpu_tx_valid = 1;
        @(posedge clk); cpu_tx_valid = 0;
        #(BIT_PERIOD*20);
        
        wait(cpu_tx_ready);
        @(posedge clk); cpu_tx_data = 8'hAA; cpu_tx_valid = 1;
        @(posedge clk); cpu_tx_valid = 0;
        #(BIT_PERIOD*20);
        
        // Simultaneous test
        test_step = 4; $display("[TEST 4] Simultaneous Test");
        cpu_rx_ready = 1;
        fork
            begin
                wait(cpu_tx_ready);
                @(posedge clk); cpu_tx_data = 8'hC0; cpu_tx_valid = 1;
                @(posedge clk); cpu_tx_valid = 0;
            end
            begin
                #(BIT_PERIOD*5);
                uart_send_byte(8'hD0);
            end
        join
        #(BIT_PERIOD*20);
        
        $display("=== Test Complete ===");
        $display("Errors: %0d", error_count);
        $finish;
    end
    
    initial begin
        #TEST_TIMEOUT;
        $display("Timeout at test step %0d", test_step);
        $finish;
    end

endmodule