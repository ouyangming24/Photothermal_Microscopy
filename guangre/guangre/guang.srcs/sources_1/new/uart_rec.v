// =============================================================================
// uart_rec.v
// 功能：115200 8N1 UART 接收
// 特点：RX 双触发器同步；起始位半周期采样确认
// 输出：rec_data + rec_done（单周期脉冲）
// =============================================================================
module uart_rec (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rec_data,
    output reg        rec_done
);

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam REC   = 2'b10;
    localparam STOP  = 2'b11;

    localparam CLK_FREQ     = 50_000_000;
    localparam BAUD_RATE    = 115_200;
    localparam BPS_CNT      = CLK_FREQ / BAUD_RATE;
    localparam HALF_BPS_CNT = (BPS_CNT + 1) / 2;

    reg [1:0]  curr_state;
    reg [15:0] clk_cnt;
    reg [3:0]  bit_cnt;
    reg        rx_sync1, rx_sync2;

    // 双触发器同步，降低亚稳态风险
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
            clk_cnt    <= 16'd0;
            bit_cnt    <= 4'd0;
            rec_data   <= 8'd0;
            rec_done   <= 1'b0;
        end else begin
            case (curr_state)
                IDLE: begin
                    rec_done <= 1'b0;
                    if (rx_sync2 == 1'b0) begin
                        curr_state <= START;
                        clk_cnt    <= 16'd0;
                    end
                end

                START: begin
                    if (clk_cnt == HALF_BPS_CNT - 1) begin
                        if (rx_sync2 == 1'b0) begin
                            curr_state <= REC;
                            clk_cnt    <= 16'd0;
                            bit_cnt    <= 4'd0;
                        end else begin
                            curr_state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                REC: begin
                    if (clk_cnt == BPS_CNT - 1) begin
                        clk_cnt <= 16'd0;
                        rec_data[bit_cnt] <= rx_sync2;
                        if (bit_cnt == 4'd7)
                            curr_state <= STOP;
                        else
                            bit_cnt <= bit_cnt + 1'b1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_cnt == BPS_CNT - 1) begin
                        if (rx_sync2 == 1'b1)
                            rec_done <= 1'b1;
                        curr_state <= IDLE;
                        clk_cnt    <= 16'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: curr_state <= IDLE;
            endcase
        end
    end

endmodule
