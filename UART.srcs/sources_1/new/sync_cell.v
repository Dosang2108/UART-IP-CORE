module sync_cell(
    clk,
    rst_n,
    async_i,
    sync_o
);

parameter WIDTH = 8;
parameter NUM_STAGES = 2;

input clk;
input rst_n;
input [WIDTH-1:0] async_i;
output [WIDTH-1:0] sync_o;

reg [WIDTH-1:0] sync_ff_0;
reg [WIDTH-1:0] sync_ff_1;
reg [WIDTH-1:0] sync_ff_2;

// 2-stage synchronizer (default)
generate
    if (NUM_STAGES == 2) begin
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sync_ff_0 <= {WIDTH{1'b0}};
                sync_ff_1 <= {WIDTH{1'b0}};
            end else begin
                sync_ff_0 <= async_i;
                sync_ff_1 <= sync_ff_0;
            end
        end
        assign sync_o = sync_ff_1;
    end
    else if (NUM_STAGES == 3) begin
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sync_ff_0 <= {WIDTH{1'b0}};
                sync_ff_1 <= {WIDTH{1'b0}};
                sync_ff_2 <= {WIDTH{1'b0}};
            end else begin
                sync_ff_0 <= async_i;
                sync_ff_1 <= sync_ff_0;
                sync_ff_2 <= sync_ff_1;
            end
        end
        assign sync_o = sync_ff_2;
    end
endgenerate

endmodule