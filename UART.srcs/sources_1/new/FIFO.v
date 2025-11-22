module asyn_fifo(
    clk_wr_domain,
    clk_rd_domain,
    data_i,
    data_o,
    wr_valid_i,
    rd_valid_i,
    empty_o,
    full_o,
    wr_ready_o,
    rd_ready_o,
    almost_empty_o,
    almost_full_o,
    rst_n
);

parameter ASFIFO_TYPE = 0;
parameter DATA_WIDTH = 8;
parameter FIFO_DEPTH = 32;
parameter NUM_SYNC_FF = 2;
parameter ALMOST_FULL_TH = 30;
parameter ALMOST_EMPTY_TH = 2;

// Calculate address width
localparam ADDR_WIDTH = (FIFO_DEPTH > 1) ? clog2(FIFO_DEPTH) : 1;
localparam ADDR_OVF_WIDTH = ADDR_WIDTH + 1;

input clk_wr_domain;
input clk_rd_domain;
input [DATA_WIDTH-1:0] data_i;
output [DATA_WIDTH-1:0] data_o;
input wr_valid_i;
input rd_valid_i;
output empty_o;
output full_o;
output wr_ready_o;
output rd_ready_o;
output almost_empty_o;
output almost_full_o;
input rst_n;

// Internal signals
wire [ADDR_OVF_WIDTH-1:0] wr_addr_gray_sync;
wire [ADDR_OVF_WIDTH-1:0] rd_addr_gray_sync;
wire [ADDR_OVF_WIDTH-1:0] wr_addr_bin_sync;
wire [ADDR_OVF_WIDTH-1:0] rd_addr_bin_sync;

wire wr_handshake;
wire rd_handshake;

// Memory array
reg [DATA_WIDTH-1:0] buffer [0:FIFO_DEPTH-1];

// Function to calculate log2
function integer clog2;
    input integer value;
    integer temp;
    begin
        temp = value - 1;
        for (clog2 = 0; temp > 0; clog2 = clog2 + 1)
            temp = temp >> 1;
    end
endfunction

// Binary to Gray conversion function
function [ADDR_OVF_WIDTH-1:0] bin2gray;
    input [ADDR_OVF_WIDTH-1:0] bin;
    begin
        bin2gray = bin ^ (bin >> 1);
    end
endfunction

// Gray to Binary conversion function
function [ADDR_OVF_WIDTH-1:0] gray2bin;
    input [ADDR_OVF_WIDTH-1:0] gray;
    reg [ADDR_OVF_WIDTH-1:0] result;
    integer i;
    begin
        result[ADDR_OVF_WIDTH-1] = gray[ADDR_OVF_WIDTH-1];
        for (i = ADDR_OVF_WIDTH-2; i >= 0; i = i - 1) begin
            result[i] = result[i+1] ^ gray[i];
        end
        gray2bin = result;
    end
endfunction

// Generate FIFO based on type
generate
    if (ASFIFO_TYPE == 0) begin : NORMAL_FIFO
        // Write domain signals
        reg [ADDR_OVF_WIDTH-1:0] wr_ptr_bin;
        reg [ADDR_OVF_WIDTH-1:0] wr_ptr_gray;  
        // Read domain signals  
        reg [ADDR_OVF_WIDTH-1:0] rd_ptr_bin;
        reg [ADDR_OVF_WIDTH-1:0] rd_ptr_gray;   
        // Synchronizers
        sync_cell #(
            .WIDTH(ADDR_OVF_WIDTH),
            .NUM_STAGES(NUM_SYNC_FF)
        ) rd_ptr_sync (
            .clk(clk_wr_domain),
            .rst_n(rst_n),
            .async_i(rd_ptr_gray),
            .sync_o(rd_addr_gray_sync)
        );    
        sync_cell #(
            .WIDTH(ADDR_OVF_WIDTH), 
            .NUM_STAGES(NUM_SYNC_FF)
        ) wr_ptr_sync (
            .clk(clk_rd_domain),
            .rst_n(rst_n),
            .async_i(wr_ptr_gray),
            .sync_o(wr_addr_gray_sync)
        );    
        // Convert synchronized Gray to Binary
        assign rd_addr_bin_sync = gray2bin(rd_addr_gray_sync);
        assign wr_addr_bin_sync = gray2bin(wr_addr_gray_sync);    
        // Handshake signals
        assign wr_handshake = wr_valid_i && wr_ready_o;
        assign rd_handshake = rd_valid_i && rd_ready_o;
        // Status flags
        assign full_o  = (wr_ptr_bin[ADDR_WIDTH-1:0] == rd_addr_bin_sync[ADDR_WIDTH-1:0]) && 
                        (wr_ptr_bin[ADDR_WIDTH] != rd_addr_bin_sync[ADDR_WIDTH]);
        assign empty_o = (wr_addr_bin_sync == rd_ptr_bin);
        
        assign wr_ready_o = !full_o;
        assign rd_ready_o = !empty_o;
        
        // Almost full/empty flags
        wire [ADDR_WIDTH:0] fifo_count_wr;
        wire [ADDR_WIDTH:0] fifo_count_rd;
        
        assign fifo_count_wr = wr_ptr_bin - rd_addr_bin_sync;
        assign fifo_count_rd = wr_addr_bin_sync - rd_ptr_bin;
        
        assign almost_full_o  = (fifo_count_wr >= ALMOST_FULL_TH);
        assign almost_empty_o = (fifo_count_rd <= ALMOST_EMPTY_TH);
        
        // Data output (direct from memory)
        assign data_o = buffer[rd_ptr_bin[ADDR_WIDTH-1:0]];
        
        // Write domain logic
        always @(posedge clk_wr_domain or negedge rst_n) begin
            if (!rst_n) begin
                wr_ptr_bin  <= {ADDR_OVF_WIDTH{1'b0}};
                wr_ptr_gray <= {ADDR_OVF_WIDTH{1'b0}};
            end else if (wr_handshake) begin
                // Update memory
                buffer[wr_ptr_bin[ADDR_WIDTH-1:0]] <= data_i;
                // Update pointers
                wr_ptr_bin  <= wr_ptr_bin + 1'b1;
                wr_ptr_gray <= bin2gray(wr_ptr_bin + 1'b1);
            end
        end
        
        // Read domain logic
        always @(posedge clk_rd_domain or negedge rst_n) begin
            if (!rst_n) begin
                rd_ptr_bin  <= {ADDR_OVF_WIDTH{1'b0}};
                rd_ptr_gray <= {ADDR_OVF_WIDTH{1'b0}};
            end else if (rd_handshake) begin
                rd_ptr_bin  <= rd_ptr_bin + 1'b1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
            end
        end
        
    end else begin : REGISTERED_FIFO    
        // Write domain signals
        reg [ADDR_OVF_WIDTH-1:0] wr_ptr_bin;
        reg [ADDR_OVF_WIDTH-1:0] wr_ptr_gray;
        reg full_reg;
        reg almost_full_reg;
        reg wr_ready_reg;

        // Read domain signals  
        reg [ADDR_OVF_WIDTH-1:0] rd_ptr_bin;
        reg [ADDR_OVF_WIDTH-1:0] rd_ptr_gray;
        reg [DATA_WIDTH-1:0] data_out_reg;
        reg empty_reg;
        reg almost_empty_reg;
        reg rd_ready_reg;

        // Next pointer calculations
        reg [ADDR_OVF_WIDTH-1:0] next_wr_ptr_bin;
        reg [ADDR_OVF_WIDTH-1:0] next_rd_ptr_bin;

        // FIFO count registers
        reg [ADDR_OVF_WIDTH-1:0] fifo_count_wr_reg;
        reg [ADDR_OVF_WIDTH-1:0] fifo_count_rd_reg;

        // Synchronizers
        sync_cell #(
            .WIDTH(ADDR_OVF_WIDTH),
            .NUM_STAGES(NUM_SYNC_FF)
        ) rd_ptr_sync (
            .clk(clk_wr_domain),
            .rst_n(rst_n),
            .async_i(rd_ptr_gray),
            .sync_o(rd_addr_gray_sync)
        );

        sync_cell #(
            .WIDTH(ADDR_OVF_WIDTH),
            .NUM_STAGES(NUM_SYNC_FF)
        ) wr_ptr_sync (
            .clk(clk_rd_domain),
            .rst_n(rst_n),
            .async_i(wr_ptr_gray),
            .sync_o(wr_addr_gray_sync)
        );

        // Convert synchronized Gray to Binary
        assign rd_addr_bin_sync = gray2bin(rd_addr_gray_sync);
        assign wr_addr_bin_sync = gray2bin(wr_addr_gray_sync);

        // Handshake signals
        assign wr_handshake = wr_valid_i && wr_ready_o;
        assign rd_handshake = rd_valid_i && rd_ready_o;

        // Combinational status flags
        wire full_comb;
        wire empty_comb;
        wire almost_full_comb;
        wire almost_empty_comb;

        // Full when pointers are same except MSB (wrap-around detection)
        assign full_comb = (wr_ptr_bin[ADDR_WIDTH-1:0] == rd_addr_bin_sync[ADDR_WIDTH-1:0]) && 
                        (wr_ptr_bin[ADDR_WIDTH] != rd_addr_bin_sync[ADDR_WIDTH]);

        // Empty when pointers are exactly equal
        assign empty_comb = (wr_addr_bin_sync == rd_ptr_bin);

        // Almost full/empty based on registered counts
        assign almost_full_comb  = (fifo_count_wr_reg >= ALMOST_FULL_TH);
        assign almost_empty_comb = (fifo_count_rd_reg <= ALMOST_EMPTY_TH);

        // Registered outputs
        assign full_o  = full_reg;
        assign empty_o = empty_reg;
        assign wr_ready_o = wr_ready_reg;
        assign rd_ready_o = rd_ready_reg;
        assign almost_full_o = almost_full_reg;
        assign almost_empty_o = almost_empty_reg;
        assign data_o = data_out_reg;

        //WRITE DOMAIN LOGIC
        always @(posedge clk_wr_domain or negedge rst_n) begin
            if (!rst_n) begin
                wr_ptr_bin        <= {ADDR_OVF_WIDTH{1'b0}};
                wr_ptr_gray       <= {ADDR_OVF_WIDTH{1'b0}};
                next_wr_ptr_bin   <= {ADDR_OVF_WIDTH{1'b1}}; // wr_ptr_bin + 1
                full_reg          <= 1'b0;
                almost_full_reg   <= 1'b0;
                wr_ready_reg      <= 1'b1;
                fifo_count_wr_reg <= {ADDR_OVF_WIDTH{1'b0}};
            end else begin
                // Calculate next pointer
                next_wr_ptr_bin <= wr_ptr_bin + 1'b1;
                
                // Update memory and pointer on write handshake
                if (wr_handshake && !full_reg) begin
                    buffer[wr_ptr_bin[ADDR_WIDTH-1:0]] <= data_i;
                    wr_ptr_bin  <= next_wr_ptr_bin;
                    wr_ptr_gray <= bin2gray(next_wr_ptr_bin);
                end
                
                // Calculate FIFO count in write domain
                if (wr_ptr_bin >= rd_addr_bin_sync) begin
                    fifo_count_wr_reg <= wr_ptr_bin - rd_addr_bin_sync;
                end else begin
                    fifo_count_wr_reg <= (2**(ADDR_OVF_WIDTH) - rd_addr_bin_sync + wr_ptr_bin);
                end
                
                // Update status flags with protection
                full_reg <= full_comb;
                almost_full_reg <= almost_full_comb;
                // Allow writes only when not full and not almost full under backpressure
                wr_ready_reg <= !full_comb;
            end
        end

        //READ DOMAIN LOGIC
        always @(posedge clk_rd_domain or negedge rst_n) begin
            if (!rst_n) begin
                rd_ptr_bin        <= {ADDR_OVF_WIDTH{1'b0}};
                rd_ptr_gray       <= {ADDR_OVF_WIDTH{1'b0}};
                next_rd_ptr_bin   <= {ADDR_OVF_WIDTH{1'b1}}; // rd_ptr_bin + 1
                data_out_reg      <= {DATA_WIDTH{1'b0}};
                empty_reg         <= 1'b1;
                almost_empty_reg  <= 1'b1;
                rd_ready_reg      <= 1'b0;
                fifo_count_rd_reg <= {ADDR_OVF_WIDTH{1'b0}};
            end else begin
                // Calculate next pointer
                next_rd_ptr_bin <= rd_ptr_bin + 1'b1;
                if (rd_handshake && !empty_reg) begin
                    data_out_reg <= buffer[rd_ptr_bin[ADDR_WIDTH-1:0]];
                    rd_ptr_bin  <= next_rd_ptr_bin;
                    rd_ptr_gray <= bin2gray(next_rd_ptr_bin);
                end else if (!empty_comb && empty_reg) begin
                    // FIFO transition from empty to non-empty: capture first data
                    data_out_reg <= buffer[rd_ptr_bin[ADDR_WIDTH-1:0]];
                    // Don't advance pointer - this is just initial data capture
                end
                if (wr_addr_bin_sync >= rd_ptr_bin) begin
                    fifo_count_rd_reg <= wr_addr_bin_sync - rd_ptr_bin;
                end else begin
                    fifo_count_rd_reg <= (2**(ADDR_OVF_WIDTH) - rd_ptr_bin + wr_addr_bin_sync);
                end
                
                // Update status flags
                empty_reg <= empty_comb;
                almost_empty_reg <= almost_empty_comb;
                rd_ready_reg <= !empty_comb;
            end
        end
    end
endgenerate

endmodule