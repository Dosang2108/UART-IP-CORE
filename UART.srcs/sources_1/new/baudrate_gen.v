module baud_gen #(
    parameter INTERNAL_CLOCK = 125000000,
    parameter BAUD_RATE = 115200
) (
    input clk,
    input rst_n,
    output reg baud_tx_en,     
    output reg baud_rx_en      
);

    // Calculate divisors với kiểm tra hợp lệ
    localparam MIN_DIVISOR = 2;
    localparam TX_DIVISOR = (INTERNAL_CLOCK / BAUD_RATE) > MIN_DIVISOR ? 
                           (INTERNAL_CLOCK / BAUD_RATE) : MIN_DIVISOR;
    localparam RX_DIVISOR = (INTERNAL_CLOCK / (BAUD_RATE * 16)) > MIN_DIVISOR ? 
                           (INTERNAL_CLOCK / (BAUD_RATE * 16)) : MIN_DIVISOR;
    
    // SỬA: Đảm bảo counter width đủ lớn
    localparam COUNTER_WIDTH = $clog2(TX_DIVISOR > RX_DIVISOR ? TX_DIVISOR : RX_DIVISOR) + 1;
    
    reg [COUNTER_WIDTH-1:0] tx_counter;
    reg [COUNTER_WIDTH-1:0] rx_counter;
    reg [3:0] sample_counter;
    
    // TX baud generator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_counter <= 0;
            baud_tx_en <= 0;
        end else begin
            baud_tx_en <= 0; // Default
            if (tx_counter >= TX_DIVISOR - 1) begin
                tx_counter <= 0;
                baud_tx_en <= 1;
            end else begin
                tx_counter <= tx_counter + 1;
            end
        end
    end   
    // RX baud generator (16x oversampling)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_counter <= 0;
            sample_counter <= 0;
            baud_rx_en <= 0;
        end else begin
            baud_rx_en <= 0; // Default
            if (rx_counter >= RX_DIVISOR - 1) begin
                rx_counter <= 0;
                sample_counter <= sample_counter + 1;
                
                // Generate sample enable at middle of bit
                if (sample_counter == 7) begin
                    baud_rx_en <= 1;
                end
                
                if (sample_counter == 15) begin
                    sample_counter <= 0;
                end
            end else begin
                rx_counter <= rx_counter + 1;
            end
        end
    end

endmodule