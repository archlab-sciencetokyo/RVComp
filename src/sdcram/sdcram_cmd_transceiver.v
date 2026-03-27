/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* CMD transceiver */
/******************************************************************************************/
module sdcram_cmd_transceiver(
    input  wire        i_clk,
    input  wire        i_rst,
    output wire        o_ready,
    input  wire        i_cmd_en,
    input  wire [ 5:0] i_cmd_no,
    input  wire [31:0] i_cmd_arg,
    output wire        o_rsp_en,
    output wire [47:0] o_rsp_dat,
    output wire        o_rsp_bsy,
    input  wire        sd_clk,
    inout  wire        sd_cmd,
    output wire [ 2:0] o_state
);

//==============================================================================
// State definitions
//------------------------------------------------------------------------------
    localparam [2:0] IDLE     = 3'b011;
    localparam [2:0] TX_CMD = 3'b001;
    localparam [2:0] TX_CRC = 3'b010;
    localparam [2:0] EXEC_FIN = 3'b000;
    localparam [2:0] WAIT_RSP = 3'b100;
    localparam [2:0] RX_RSP = 3'b101;

//==============================================================================
// Registers
//------------------------------------------------------------------------------
    reg [ 2:0] state_q, state_d;
    reg [ 7:0] cmd_cnt_q, cmd_cnt_d;
    reg [ 7:0] rsp_cnt_q, rsp_cnt_d;
    reg [47:0] cmd_out_q, cmd_out_d;

    reg        rsp_en_q, rsp_en_d;
    reg [47:0] rsp_dat_q, rsp_dat_d;
    reg        rsp_bsy_q, rsp_bsy_d;

//==============================================================================
// ROM and CRC
//------------------------------------------------------------------------------
    wire [47:0] w_cmd_dat;
    wire [ 7:0] w_rsp_bit;
    wire        w_rsp_bsy;

    cmd_rom cmd_rom0(
        .cmd_no (i_cmd_no ),
        .arg    (i_cmd_arg),
        .cmd_dat(w_cmd_dat),
        .rsp_bit(w_rsp_bit),
        .rsp_bsy(w_rsp_bsy)
    );

    wire w_crc7_en  = (state_q == TX_CMD) && (cmd_cnt_q >= 8) && sd_clk;
    wire w_crc7_rst = i_rst || (state_q == TX_CRC);
    wire w_crc7_dat = cmd_out_q[39];

    wire [6:0] crc7;
    sdcram_crc_7 cmd_crc(
       .DAT(w_crc7_dat),
       .EN (w_crc7_en ),
       .CLK(i_clk     ),
       .RST(w_crc7_rst),
       .CRC(crc7      )
    );

//==============================================================================
// Outputs and tri-state
//------------------------------------------------------------------------------
    assign o_ready   = (state_q == IDLE);
    assign o_state   = state_q;
    assign o_rsp_en  = rsp_en_q;
    assign o_rsp_dat = rsp_dat_q;
    assign o_rsp_bsy = rsp_bsy_q;

    assign sd_cmd = state_q[2] ? 1'bz : cmd_out_q[47];

//==============================================================================
// Combinational next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        state_d   = state_q;
        cmd_cnt_d = cmd_cnt_q;
        rsp_cnt_d = rsp_cnt_q;
        cmd_out_d = cmd_out_q;

        rsp_en_d  = rsp_en_q;
        rsp_dat_d = rsp_dat_q;
        rsp_bsy_d = rsp_bsy_q;

        case (state_q)
            IDLE: begin
                rsp_en_d = 1'b0;
                if (i_cmd_en) begin
                    state_d   = TX_CMD;
                    cmd_out_d = w_cmd_dat;
                    cmd_cnt_d = 8'd47;
                    rsp_cnt_d = w_rsp_bit;
                    rsp_bsy_d = w_rsp_bsy;
                    rsp_en_d  = 1'b0;
                end
            end

            TX_CMD: begin
                if (sd_clk) begin
                    if (cmd_cnt_q == 8'd0) begin
                        state_d   = TX_CRC;
                        cmd_cnt_d = 8'd7;
                        cmd_out_d = {crc7, {41{1'b1}}};
                    end else begin
                        cmd_cnt_d = cmd_cnt_q - 1'b1;
                        cmd_out_d = {cmd_out_q[46:0], 1'b1};
                    end
                end
            end

            TX_CRC: begin
                if (sd_clk) begin
                    if (cmd_cnt_q == 8'd0) begin
                        state_d  = (rsp_cnt_q == 8'd0) ? EXEC_FIN : WAIT_RSP;
                        rsp_en_d = (rsp_cnt_q == 8'd0);
                    end else begin
                        cmd_cnt_d = cmd_cnt_q - 1'b1;
                        cmd_out_d = {cmd_out_q[46:0], 1'b1};
                    end
                end
            end

            WAIT_RSP: begin
                if (sd_clk && (sd_cmd == 1'b0)) begin
                    rsp_dat_d = 48'd0;
                    state_d   = RX_RSP;
                end
            end

            RX_RSP: begin
                if (sd_clk) begin
                    rsp_dat_d = {rsp_dat_q[46:0], sd_cmd};
                    if (rsp_cnt_q == 8'd1) begin
                        state_d  = EXEC_FIN;
                        rsp_en_d = 1'b1;
                    end else begin
                        rsp_cnt_d = rsp_cnt_q - 1'b1;
                    end
                end
            end

            EXEC_FIN: begin
                rsp_en_d  = 1'b0;
                rsp_bsy_d = 1'b0;
                state_d   = IDLE;
            end

            default: begin
                state_d = IDLE;
            end
        endcase
    end

//==============================================================================
// Sequential state update
//------------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            state_q   <= IDLE;
            cmd_cnt_q <= 8'd0;
            rsp_cnt_q <= 8'd0;
            cmd_out_q <= {48{1'b1}};
            rsp_en_q  <= 1'b0;
            rsp_dat_q <= 48'd0;
            rsp_bsy_q <= 1'b0;
        end else begin
            state_q   <= state_d;
            cmd_cnt_q <= cmd_cnt_d;
            rsp_cnt_q <= rsp_cnt_d;
            cmd_out_q <= cmd_out_d;
            rsp_en_q  <= rsp_en_d;
            rsp_dat_q <= rsp_dat_d;
            rsp_bsy_q <= rsp_bsy_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
