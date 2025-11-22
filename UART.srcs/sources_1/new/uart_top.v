module uart_top #(
    parameter DATA_WIDTH = 8,
    parameter INTERNAL_CLOCK = 125000000,
    parameter BAUD_RATE = 115200,
    parameter FIFO_DEPTH = 16
) (
    input clk,
    input rst_n,
    
    // UART Physical Interface
    input rxd,
    output txd,
    
    // CPU Interface - TX
    input [DATA_WIDTH-1:0] cpu_tx_data,
    input cpu_tx_valid,
    output cpu_tx_ready,
    
    // CPU Interface - RX
    output [DATA_WIDTH-1:0] cpu_rx_data,
    output cpu_rx_valid,
    input cpu_rx_ready,
    
    // Status Indicators
    output tx_busy,
    output rx_busy,
    output tx_fifo_full,
    output rx_fifo_empty,
    output frame_error,
    output timeout_error
);

    // Internal signals
    wire baud_tx_en, baud_rx_en;
    
    // TX FIFO signals
    wire [DATA_WIDTH-1:0] tx_fifo_data_out;
    wire tx_fifo_empty;
    wire tx_fifo_rd_en;
    wire tx_fifo_full;
    
    // RX FIFO signals
    wire [DATA_WIDTH-1:0] rx_fifo_data_in;
    wire rx_fifo_wr_en;
    wire rx_fifo_full;
    wire rx_fifo_empty;
    
    wire tx_ready;
    wire rx_timeout_error;
    wire rx_frame_error;
    
    // Statistics counters
    reg [31:0] tx_byte_count;
    reg [31:0] rx_byte_count;
    reg [31:0] frame_error_count;
    reg [31:0] timeout_error_count;
    
    baud_gen #(
        .INTERNAL_CLOCK(INTERNAL_CLOCK),
        .BAUD_RATE(BAUD_RATE)
    ) baud_gen_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_tx_en(baud_tx_en),
        .baud_rx_en(baud_rx_en)
    );
    
    asyn_fifo #(
        .ASFIFO_TYPE(1),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ALMOST_FULL_TH(FIFO_DEPTH - 2),
        .ALMOST_EMPTY_TH(2)
    ) fifo_tx (
        .clk_wr_domain(clk),
        .clk_rd_domain(clk),
        .data_i(cpu_tx_data),
        .data_o(tx_fifo_data_out),
        .wr_valid_i(cpu_tx_valid),
        .rd_valid_i(tx_fifo_rd_en),
        .empty_o(tx_fifo_empty),
        .full_o(tx_fifo_full),
        .wr_ready_o(cpu_tx_ready),
        .rd_ready_o(),
        .almost_empty_o(),
        .almost_full_o(),
        .rst_n(rst_n)
    );
    
    wire tx_transaction_en;
    
    uart_tx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uart_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_i(tx_fifo_data_out),
        .data_valid_i(tx_fifo_rd_en),
        .ready_o(tx_ready),
        .baudrate_clk_en(baud_tx_en),
        .transaction_en(tx_transaction_en),
        .TX(txd),
        .tx_busy(tx_busy)
    );
    
    assign tx_fifo_rd_en = tx_ready && !tx_fifo_empty;
    
    wire rx_transaction_en;
    
    // SỬA: Thêm parameter DATA_WIDTH
    uart_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .TIMEOUT_CYCLES(16)
    ) uart_rx_inst (
        .clk(clk),
        .rst_n(rst_n),          
        .RX(rxd),
        .baudrate_clk_en(baud_rx_en),
        .transaction_en(rx_transaction_en),
        .data_out_rx(rx_fifo_data_in),
        .fifo_wr(rx_fifo_wr_en),
        .frame_error(rx_frame_error),
        .timeout_error(rx_timeout_error)
    );
    
    asyn_fifo #(
        .ASFIFO_TYPE(1),
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ALMOST_FULL_TH(FIFO_DEPTH - 2),
        .ALMOST_EMPTY_TH(2)
    ) fifo_rx (
        .clk_wr_domain(clk),
        .clk_rd_domain(clk),
        .data_i(rx_fifo_data_in),
        .data_o(cpu_rx_data),
        .wr_valid_i(rx_fifo_wr_en),
        .rd_valid_i(cpu_rx_ready),
        .empty_o(rx_fifo_empty),
        .full_o(rx_fifo_full),
        .wr_ready_o(),
        .rd_ready_o(cpu_rx_valid),
        .almost_empty_o(),
        .almost_full_o(),
        .rst_n(rst_n)
    );
    
    assign rx_busy = rx_transaction_en;
    assign frame_error = rx_frame_error;
    assign timeout_error = rx_timeout_error;
    
    // Statistics counting
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_byte_count <= 0;
            rx_byte_count <= 0;
            frame_error_count <= 0;
            timeout_error_count <= 0;
        end else begin
            // Count transmitted bytes
            if (tx_fifo_rd_en) begin
                tx_byte_count <= tx_byte_count + 1;
            end
            
            // Count received bytes
            if (cpu_rx_valid && cpu_rx_ready) begin
                rx_byte_count <= rx_byte_count + 1;
            end
            
            // Count frame errors
            if (rx_frame_error && rx_fifo_wr_en) begin
                frame_error_count <= frame_error_count + 1;
            end
            
            // Count timeout errors
            if (rx_timeout_error) begin
                timeout_error_count <= timeout_error_count + 1;
            end
        end
    end

endmodule