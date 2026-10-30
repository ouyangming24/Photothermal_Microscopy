// =============================================================================
// clk_fenpin.v
// 功能：偶数分频器（占空比约 50%）
// 参数 DIVIDE_RATIO：必须为偶数；输出频率 = clk_in / DIVIDE_RATIO
// 例：clk_in=50MHz, DIVIDE_RATIO=2 → clk_out=25MHz
// =============================================================================
module clk_fenpin #(
    parameter DIVIDE_RATIO = 2
)(
    input  wire clk_in,
    input  wire rst_n,
    output reg  clk_out
);

    localparam COUNTER_WIDTH = (DIVIDE_RATIO <= 2) ? 1 : $clog2(DIVIDE_RATIO);

    reg [COUNTER_WIDTH-1:0] counter;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            counter <= {COUNTER_WIDTH{1'b0}};
            clk_out <= 1'b0;
        end else begin
            if (counter == DIVIDE_RATIO - 1) begin
                counter <= {COUNTER_WIDTH{1'b0}};
                clk_out <= ~clk_out;
            end else if (counter == (DIVIDE_RATIO / 2) - 1) begin
                counter <= counter + 1'b1;
                clk_out <= ~clk_out;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule
