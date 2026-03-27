/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* DAT transceiver (4-bit DAT[3:0]) */
/******************************************************************************************/
module sdcram_dat_transceiver(
    input  wire        i_clk,
    input  wire        i_rst,
    output wire        o_ready,
    input  wire [ 1:0] i_funct,    // 00:idle 01:read 10:write 11:busy-wait
    input  wire [31:0] i_blk_num,  // >= 1
    output wire [ 7:0] o_data,
    output wire        o_data_en,
    input  wire [ 7:0] i_data,
    output wire        o_data_ready,
    input  wire        sd_clk,
    inout  wire [ 3:0] sd_dat,
    output wire [ 3:0] o_state
);

//==============================================================================
// State definitions
//------------------------------------------------------------------------------
    localparam [3:0] IDLE     = 4'b0111;
    localparam [3:0] TX_DAT = 4'b0001;
    localparam [3:0] TX_CRC = 4'b0010;
    localparam [3:0] TX_INI = 4'b0011;
    localparam [3:0] WAIT_DAT = 4'b1000;
    localparam [3:0] RX_DAT = 4'b1001;
    localparam [3:0] WAIT_RSP = 4'b1010;
    localparam [3:0] RX_RSP = 4'b1011;
    localparam [3:0] WAIT_BSY = 4'b1100;

    localparam [15:0] WRITE_DATA_SIZE = 16'd1025; // 513*2-1

//==============================================================================
// Registers
//------------------------------------------------------------------------------
    reg [ 3:0] state_q, state_d;

    reg [47:0] rsp_out_q, rsp_out_d;
    reg [ 7:0] rsp_cnt_q, rsp_cnt_d;
    reg [15:0] dat_cnt_q, dat_cnt_d;
    reg [31:0] blk_cnt_q, blk_cnt_d;

    reg [15:0] dat_out_0_q, dat_out_0_d;
    reg [15:0] dat_out_1_q, dat_out_1_d;
    reg [15:0] dat_out_2_q, dat_out_2_d;
    reg [15:0] dat_out_3_q, dat_out_3_d;

    reg [ 7:0] o_data_q, o_data_d;
    reg        o_data_en_q, o_data_en_d;
    reg        o_data_ready_q, o_data_ready_d;

//==============================================================================
// Outputs and tri-state
//------------------------------------------------------------------------------
    assign o_ready      = (state_q == IDLE);
    assign o_state      = state_q;
    assign o_data       = o_data_q;
    assign o_data_en    = o_data_en_q;
    assign o_data_ready = o_data_ready_q;

    // state_q[3]==1: read side, release DAT lines
    assign sd_dat[0] = state_q[3] ? 1'bz : dat_out_0_q[15];
    assign sd_dat[1] = state_q[3] ? 1'bz : dat_out_1_q[15];
    assign sd_dat[2] = state_q[3] ? 1'bz : dat_out_2_q[15];
    assign sd_dat[3] = state_q[3] ? 1'bz : dat_out_3_q[15];

//==============================================================================
// CRC generators
//------------------------------------------------------------------------------
    wire w_crc16_en  = (state_q == TX_DAT) && (dat_cnt_q < 16'd1024) && !sd_clk;
    wire w_crc16_rst = i_rst || (state_q == TX_CRC);

    wire [15:0] crc16_0;
    wire [15:0] crc16_1;
    wire [15:0] crc16_2;
    wire [15:0] crc16_3;

    sdcram_crc_16 dat_crc_0(
       .DAT(dat_out_0_q[15]),
       .EN (w_crc16_en      ),
       .CLK(i_clk           ),
       .RST(w_crc16_rst     ),
       .CRC(crc16_0         )
    );

    sdcram_crc_16 dat_crc_1(
       .DAT(dat_out_1_q[15]),
       .EN (w_crc16_en      ),
       .CLK(i_clk           ),
       .RST(w_crc16_rst     ),
       .CRC(crc16_1         )
    );

    sdcram_crc_16 dat_crc_2(
       .DAT(dat_out_2_q[15]),
       .EN (w_crc16_en      ),
       .CLK(i_clk           ),
       .RST(w_crc16_rst     ),
       .CRC(crc16_2         )
    );

    sdcram_crc_16 dat_crc_3(
       .DAT(dat_out_3_q[15]),
       .EN (w_crc16_en      ),
       .CLK(i_clk           ),
       .RST(w_crc16_rst     ),
       .CRC(crc16_3         )
    );

//==============================================================================
// Combinational next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        state_d        = state_q;
        rsp_out_d      = rsp_out_q;
        rsp_cnt_d      = rsp_cnt_q;
        dat_cnt_d      = dat_cnt_q;
        blk_cnt_d      = blk_cnt_q;

        dat_out_0_d    = dat_out_0_q;
        dat_out_1_d    = dat_out_1_q;
        dat_out_2_d    = dat_out_2_q;
        dat_out_3_d    = dat_out_3_q;

        o_data_d       = o_data_q;
        o_data_en_d    = o_data_en_q;
        o_data_ready_d = o_data_ready_q;

        case (state_q)
            IDLE: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                case (i_funct)
                    2'b01: begin
                        state_d   = WAIT_DAT;
                        blk_cnt_d = i_blk_num;
                    end
                    2'b10: begin
                        state_d   = TX_INI;
                        blk_cnt_d = i_blk_num;
                    end
                    2'b11: begin
                        state_d   = WAIT_BSY;
                        blk_cnt_d = 32'd0;
                    end
                    default: begin
                        // stay idle
                    end
                endcase
            end

            WAIT_DAT: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk && (sd_dat[0] == 1'b0)) begin
                    dat_cnt_d = 16'd1039; // 512*2 + 16 - 1
                    blk_cnt_d = blk_cnt_q - 1'b1;
                    state_d   = RX_DAT;
                end
            end

            RX_DAT: begin
                o_data_ready_d = 1'b0;
                if (sd_clk) begin
                    o_data_d = {o_data_q[3:0], sd_dat[3:0]};
                    if (dat_cnt_q[0] == 1'b0) begin
                        o_data_en_d = (dat_cnt_q < 16) ? 1'b0 : 1'b1;
                        if (dat_cnt_q == 16'd0) begin
                            state_d = (blk_cnt_q == 32'd0) ? IDLE : WAIT_DAT;
                        end else begin
                            dat_cnt_d = dat_cnt_q - 1'b1;
                        end
                    end else begin
                        o_data_en_d = 1'b0;
                        dat_cnt_d   = dat_cnt_q - 1'b1;
                    end
                end else begin
                    o_data_en_d = 1'b0;
                end
            end

            TX_INI: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk) begin
                    state_d     = TX_DAT;
                    dat_cnt_d   = WRITE_DATA_SIZE;
                    dat_out_0_d = 16'hBFFF;
                    dat_out_1_d = 16'hBFFF;
                    dat_out_2_d = 16'hBFFF;
                    dat_out_3_d = 16'hBFFF;
                end
            end

            TX_DAT: begin
                o_data_en_d = 1'b0;
                if (sd_clk) begin
                    if (dat_cnt_q[0] == 1'b0) begin
                        if (dat_cnt_q != 16'd0) begin
                            dat_out_0_d    = {8{i_data[4], i_data[0]}};
                            dat_out_1_d    = {8{i_data[5], i_data[1]}};
                            dat_out_2_d    = {8{i_data[6], i_data[2]}};
                            dat_out_3_d    = {8{i_data[7], i_data[3]}};
                            o_data_ready_d = 1'b1;
                            dat_cnt_d      = dat_cnt_q - 1'b1;
                        end else begin
                            o_data_ready_d = 1'b0;
                            state_d        = TX_CRC;
                            dat_cnt_d      = 16'd16;
                            dat_out_0_d    = crc16_0;
                            dat_out_1_d    = crc16_1;
                            dat_out_2_d    = crc16_2;
                            dat_out_3_d    = crc16_3;
                        end
                    end else begin
                        dat_out_0_d    = {dat_out_0_q[14:0], 1'b1};
                        dat_out_1_d    = {dat_out_1_q[14:0], 1'b1};
                        dat_out_2_d    = {dat_out_2_q[14:0], 1'b1};
                        dat_out_3_d    = {dat_out_3_q[14:0], 1'b1};
                        o_data_ready_d = 1'b0;
                        dat_cnt_d      = dat_cnt_q - 1'b1;
                    end
                end else begin
                    o_data_ready_d = 1'b0;
                end
            end

            TX_CRC: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk) begin
                    if (dat_cnt_q == 16'd0) begin
                        state_d   = WAIT_RSP;
                        blk_cnt_d = blk_cnt_q - 1'b1;
                    end else begin
                        dat_out_0_d = {dat_out_0_q[14:0], 1'b1};
                        dat_out_1_d = {dat_out_1_q[14:0], 1'b1};
                        dat_out_2_d = {dat_out_2_q[14:0], 1'b1};
                        dat_out_3_d = {dat_out_3_q[14:0], 1'b1};
                        dat_cnt_d   = dat_cnt_q - 1'b1;
                    end
                end
            end

            WAIT_RSP: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk && (sd_dat[0] == 1'b0)) begin
                    rsp_out_d = 48'd0;
                    rsp_cnt_d = 8'd47;
                    state_d   = RX_RSP;
                end
            end

            RX_RSP: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk) begin
                    rsp_out_d = {rsp_out_q[46:0], sd_dat[0]};
                    if (rsp_cnt_q == 8'd1) begin
                        state_d = WAIT_BSY;
                    end else begin
                        rsp_cnt_d = rsp_cnt_q - 1'b1;
                    end
                end
            end

            WAIT_BSY: begin
                o_data_en_d    = 1'b0;
                o_data_ready_d = 1'b0;
                if (sd_clk && (sd_dat[0] == 1'b1)) begin
                    state_d = (blk_cnt_q == 32'd0) ? IDLE : TX_INI;
                end
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
            state_q        <= IDLE;
            rsp_out_q      <= 48'd0;
            rsp_cnt_q      <= 8'd0;
            dat_cnt_q      <= 16'd0;
            blk_cnt_q      <= 32'd0;

            dat_out_0_q    <= 16'hFFFF;
            dat_out_1_q    <= 16'hFFFF;
            dat_out_2_q    <= 16'hFFFF;
            dat_out_3_q    <= 16'hFFFF;

            o_data_q       <= 8'd0;
            o_data_en_q    <= 1'b0;
            o_data_ready_q <= 1'b0;
        end else begin
            state_q        <= state_d;
            rsp_out_q      <= rsp_out_d;
            rsp_cnt_q      <= rsp_cnt_d;
            dat_cnt_q      <= dat_cnt_d;
            blk_cnt_q      <= blk_cnt_d;

            dat_out_0_q    <= dat_out_0_d;
            dat_out_1_q    <= dat_out_1_d;
            dat_out_2_q    <= dat_out_2_d;
            dat_out_3_q    <= dat_out_3_d;

            o_data_q       <= o_data_d;
            o_data_en_q    <= o_data_en_d;
            o_data_ready_q <= o_data_ready_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
