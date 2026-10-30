// =============================================================================
// uart_send.v
// 115200 8N1 UART TX with request/ack handshake (no rising-edge race)
//
// Protocol:
//   Host holds send_en=1 with stable send_data -> start one byte
//   When byte finishes, tx_done stays 1 and state waits until send_en=0
//   Then return IDLE (ready for next send_en=1)
//   busy=1 while not IDLE
// =============================================================================
module uart_send (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       send_en,
    input  wire [7:0] send_data,
    output reg        tx,
    output reg        tx_done,
    output wire       busy
);

    localparam IDLE     = 3'd0;
    localparam START    = 3'd1;
    localparam DATA     = 3'd2;
    localparam STOP     = 3'd3;
    localparam WAIT_ACK = 3'd4;

    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115_200;
    localparam BPS_CNT   = CLK_FREQ / BAUD_RATE; // 434

    (* fsm_encoding = "none" *) reg [2:0] curr_state;
    reg [15:0] clk_cnt;
    reg [3:0]  bit_cnt;
    reg [7:0]  tx_data;

    assign busy = (curr_state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
            tx         <= 1'b1;
            tx_done    <= 1'b0;
            clk_cnt    <= 16'd0;
            bit_cnt    <= 4'd0;
            tx_data    <= 8'd0;
        end else begin
            case (curr_state)
                IDLE: begin
                    tx      <= 1'b1;
                    tx_done <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_cnt <= 4'd0;
                    if (send_en) begin
                        tx_data    <= send_data;
                        curr_state <= START;
                    end
                end

                START: begin
                    tx      <= 1'b0;
                    tx_done <= 1'b0;
                    if (clk_cnt == BPS_CNT - 1) begin
                        curr_state <= DATA;
                        clk_cnt    <= 16'd0;
                        bit_cnt    <= 4'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DATA: begin
                    tx      <= tx_data[bit_cnt];
                    tx_done <= 1'b0;
                    if (clk_cnt == BPS_CNT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_cnt == 4'd7) begin
                            curr_state <= STOP;
                            bit_cnt    <= 4'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt == BPS_CNT - 1) begin
                        curr_state <= WAIT_ACK;
                        tx_done    <= 1'b1; // level: held through WAIT_ACK
                        clk_cnt    <= 16'd0;
                    end else begin
                        tx_done <= 1'b0;
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Hold done until master drops send_en (prevents double-fire)
                WAIT_ACK: begin
                    tx      <= 1'b1;
                    tx_done <= 1'b1;
                    if (!send_en) begin
                        curr_state <= IDLE;
                        tx_done    <= 1'b0;
                    end
                end

                default: begin
                    curr_state <= IDLE;
                    tx         <= 1'b1;
                    tx_done    <= 1'b0;
                end
            endcase
        end
    end

endmodule
