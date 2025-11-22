module uart_tx #(
    parameter DATA_WIDTH = 8
) (
    input                               clk,
    input                               rst_n,
    
    // CPU Interface
    input [DATA_WIDTH-1:0]              data_i,
    input                               data_valid_i,
    output reg                          ready_o,
    
    // Baud Rate Interface
    input                               baudrate_clk_en,
    output                              transaction_en,
    
    // UART Physical Interface
    output reg                          TX,
    
    // Status
    output                              tx_busy
);

    // Fixed configuration - phải khớp với RX
    localparam DATA_WIDTH_SELECT = 8;           // 8-bit data
    localparam PARITY_SELECT = 1;               // 1 = Even parity
    localparam STOP_BIT_SELECT = 1;             // 1 = 2 stop bits
    
    // State definitions
    localparam IDLE_STATE      = 3'b000;
    localparam START_BIT_STATE = 3'b001;
    localparam DATA_STATE      = 3'b010;
    localparam PARITY_STATE    = 3'b011;
    localparam STOP_BIT_STATE  = 3'b100;
    
    // Internal registers
    reg [2:0] tx_state;
    reg [DATA_WIDTH-1:0] tx_buffer;
    reg [2:0] bit_counter;
    reg [1:0] stop_bit_counter;
    reg transaction_en_reg;
    
    // Parity calculation
    wire parity_bit = ^tx_buffer; // Even parity
    
    // Output assignments
    assign transaction_en = transaction_en_reg;
    assign tx_busy = (tx_state != IDLE_STATE);
    
    // Main TX state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= IDLE_STATE;
            TX <= 1'b1; // Idle state is high
            ready_o <= 1'b1;
            transaction_en_reg <= 1'b0;
            tx_buffer <= 0;
            bit_counter <= 0;
            stop_bit_counter <= 0;
        end else begin
            case (tx_state)
                IDLE_STATE: begin
                    TX <= 1'b1;
                    ready_o <= 1'b1;
                    transaction_en_reg <= 1'b0;
                    
                    if (data_valid_i && ready_o) begin
                        tx_state <= START_BIT_STATE;
                        tx_buffer <= data_i;
                        ready_o <= 1'b0;
                        transaction_en_reg <= 1'b1;
                        $display("[TX] Starting transmission, data=0x%02h", data_i);
                    end
                end
                
                START_BIT_STATE: begin
                    TX <= 1'b0; // Start bit
                    if (baudrate_clk_en) begin
                        tx_state <= DATA_STATE;
                        bit_counter <= 0;
                        $display("[TX] Start bit sent, moving to DATA state");
                    end
                end
                
                DATA_STATE: begin
                    TX <= tx_buffer[bit_counter]; // LSB first
                    if (baudrate_clk_en) begin
                        if (bit_counter == DATA_WIDTH - 1) begin
                            if (PARITY_SELECT != 0) begin
                                tx_state <= PARITY_STATE;
                                $display("[TX] All data bits sent, moving to PARITY state");
                            end else begin
                                tx_state <= STOP_BIT_STATE;
                                stop_bit_counter <= STOP_BIT_SELECT;
                                $display("[TX] All data bits sent (no parity), moving to STOP state");
                            end
                        end else begin
                            bit_counter <= bit_counter + 1;
                            $display("[TX] Sent data bit %0d = %b", bit_counter, tx_buffer[bit_counter]);
                        end
                    end
                end
                
                PARITY_STATE: begin
                    TX <= parity_bit;
                    if (baudrate_clk_en) begin
                        tx_state <= STOP_BIT_STATE;
                        stop_bit_counter <= STOP_BIT_SELECT;
                        $display("[TX] Parity bit sent = %b, moving to STOP state", parity_bit);
                    end
                end
                
                STOP_BIT_STATE: begin
                    TX <= 1'b1; // Stop bit
                    if (baudrate_clk_en) begin
                        if (stop_bit_counter == 0) begin
                            tx_state <= IDLE_STATE;
                            transaction_en_reg <= 1'b0;
                            $display("[TX] All stop bits sent, transmission complete");
                        end else begin
                            stop_bit_counter <= stop_bit_counter - 1;
                            $display("[TX] Sent stop bit %0d", STOP_BIT_SELECT - stop_bit_counter + 1);
                        end
                    end
                end
                
                default: tx_state <= IDLE_STATE;
            endcase
        end
    end

endmodule