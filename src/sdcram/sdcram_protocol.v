/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* protocol controller */
/******************************************************************************************/
module sdcram_protocol(
    input  wire        i_clk,      // clock
    input  wire        i_rst,      // reset
    output wire        o_ready,    // protocol ready
    input  wire        i_ren,      // read request
    output wire [ 7:0] o_data,     // read data byte
    output wire        o_data_en,  // read data valid
    input  wire        i_wen,      // write request
    input  wire [ 7:0] i_data,     // write data byte
    output wire        o_data_ready, // write data accepted
    input  wire [31:0] i_blk_num,  // transfer block count
    input  wire [31:0] i_adr,      // start block address
    output wire [ 4:0] o_state,    // debug state
    input  wire        sd_cd,      
    output wire        sd_rst,     
    output wire        sd_clk,     
    inout  wire        sd_cmd,     
    inout  wire [ 3:0] sd_dat
);

//==============================================================================
// Data transceiver
//------------------------------------------------------------------------------
    wire        dat_trans_o_ready;
    wire [ 1:0] dat_trans_i_funct;
    wire [31:0] dat_trans_i_blk_num;

    sdcram_dat_transceiver sd_dat_trans(
        .i_clk       (i_clk             ),
        .i_rst       (i_rst             ),
        .o_ready     (dat_trans_o_ready ),
        .i_funct     (dat_trans_i_funct ), // 00:idle 01:read 10:write 11:busy-wait
        .i_blk_num   (dat_trans_i_blk_num),
        .o_data      (o_data            ),
        .o_data_en   (o_data_en         ),
        .i_data      (i_data            ),
        .o_data_ready(o_data_ready      ),
        .sd_clk      (sd_clk_q          ),
        .sd_dat      (sd_dat            ),
        .o_state     (                  )
    );

//==============================================================================
// Command transceiver
//------------------------------------------------------------------------------
    wire        cmd_trans_o_ready;
    wire        cmd_trans_i_cmd_en;
    wire [ 5:0] cmd_trans_i_cmd_no;
    wire [31:0] cmd_trans_i_cmd_arg;
    wire        cmd_trans_o_rsp_en;
    wire [47:0] cmd_trans_o_rsp_dat;
    wire        cmd_trans_o_rsp_bsy;

    sdcram_cmd_transceiver sd_cmd_trans(
        .i_clk    (i_clk              ),
        .i_rst    (i_rst              ),
        .o_ready  (cmd_trans_o_ready  ),
        .i_cmd_en (cmd_trans_i_cmd_en ),
        .i_cmd_no (cmd_trans_i_cmd_no ),
        .i_cmd_arg(cmd_trans_i_cmd_arg),
        .o_rsp_en (cmd_trans_o_rsp_en ),
        .o_rsp_dat(cmd_trans_o_rsp_dat),
        .o_rsp_bsy(cmd_trans_o_rsp_bsy),
        .sd_clk   (sd_clk_q           ),
        .sd_cmd   (sd_cmd             ),
        .o_state  (                   )
    );

//==============================================================================
// State definitions
//------------------------------------------------------------------------------
    localparam [1:0] TRANS_IDLE  = 2'b00;
    localparam [1:0] TRANS_READ  = 2'b01;
    localparam [1:0] TRANS_WRITE = 2'b10;
    localparam [1:0] TRANS_BWAIT = 2'b11;

    localparam [4:0] INIT     = 5'd0;
    localparam [4:0] IDLE     = 5'd1;
    localparam [4:0] EXEC_CMD = 5'd2;
    localparam [4:0] WAIT_BSY = 5'd3;
    localparam [4:0] WAIT_TRS = 5'd4;
    localparam [4:0] EXEC_WRT = 5'd5;
    localparam [4:0] WAIT_WRT = 5'd6;
    localparam [4:0] WAIT_INI = 5'd7;
    localparam [4:0] WAIT_STP = 5'd8;

    localparam [4:0] CMD00 = 5'd16;
    localparam [4:0] CMD08 = 5'd17;
    localparam [4:0] CMD55 = 5'd18;
    localparam [4:0] CMD41 = 5'd19;
    localparam [4:0] CHK41 = 5'd20;
    localparam [4:0] CMD02 = 5'd21;
    localparam [4:0] CMD03 = 5'd22;
    localparam [4:0] CMD07 = 5'd23;
    localparam [4:0] CMD17 = 5'd24;
    localparam [4:0] CMD18 = 5'd25;
    localparam [4:0] CMD24 = 5'd26;
    localparam [4:0] CMD25 = 5'd27;
    localparam [4:0] CMD12 = 5'd28;
    localparam [4:0] SETBW = 5'd29;
    localparam [4:0] CMD06 = 5'd30;

//==============================================================================
// Registers
//------------------------------------------------------------------------------
    reg [4:0]  state_q, state_d;
    reg [4:0]  return_state_q, return_state_d;
    reg [31:0] boot_cnt_q, boot_cnt_d;
    reg [31:0] blk_cnt_q, blk_cnt_d;
    reg [31:0] blk_adr_q, blk_adr_d;
    reg [15:0] rca_q, rca_d;

    reg [ 5:0] cmd_no_q, cmd_no_d;
    reg        cmd_en_q, cmd_en_d;
    reg [31:0] cmd_arg_q, cmd_arg_d;

    reg [ 1:0] trans_funct_q, trans_funct_d;
    reg [31:0] trans_blk_num_q, trans_blk_num_d;

    reg        sd_clk_q, sd_clk_d;

//==============================================================================
// Wiring
//------------------------------------------------------------------------------
    assign cmd_trans_i_cmd_en  = cmd_en_q;
    assign cmd_trans_i_cmd_no  = cmd_no_q;
    assign cmd_trans_i_cmd_arg = cmd_arg_q;

    assign dat_trans_i_funct   = trans_funct_q;
    assign dat_trans_i_blk_num = trans_blk_num_q;

    assign o_ready = (state_q == IDLE);
    assign o_state = state_q;

    assign sd_rst  = 1'b0;
    assign sd_clk  = sd_clk_q;

//==============================================================================
// Combinational next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        state_d         = state_q;
        return_state_d  = return_state_q;
        boot_cnt_d      = boot_cnt_q;
        blk_cnt_d       = blk_cnt_q;
        blk_adr_d       = blk_adr_q;
        rca_d           = rca_q;

        cmd_no_d        = cmd_no_q;
        cmd_en_d        = cmd_en_q;
        cmd_arg_d       = cmd_arg_q;

        trans_funct_d   = trans_funct_q;
        trans_blk_num_d = trans_blk_num_q;

        sd_clk_d        = ~sd_clk_q;

        case (state_q)
            INIT: begin
                if (boot_cnt_q == 32'd0) begin
                    state_d    = CMD00;
                    boot_cnt_d = 32'd10_000_000;
                end else begin
                    boot_cnt_d = boot_cnt_q - 1'b1;
                end
            end

            IDLE: begin
                if (i_ren) begin
                    if (i_blk_num == 32'd0) begin
                        state_d   = CMD17;
                        blk_cnt_d = 32'd1;
                        blk_adr_d = i_adr;
                    end else begin
                        state_d   = CMD18;
                        blk_cnt_d = i_blk_num;
                        blk_adr_d = i_adr;
                    end
                end else if (i_wen) begin
                    if (i_blk_num == 32'd0) begin
                        state_d   = CMD24;
                        blk_cnt_d = 32'd1;
                        blk_adr_d = i_adr;
                    end else begin
                        state_d   = CMD25;
                        blk_cnt_d = i_blk_num;
                        blk_adr_d = i_adr;
                    end
                end
            end

            EXEC_CMD: begin
                cmd_en_d      = 1'b0;
                trans_funct_d = TRANS_IDLE;
                if (cmd_trans_o_rsp_en) begin
                    if (cmd_trans_o_rsp_bsy) begin
                        state_d       = WAIT_BSY;
                        trans_funct_d = TRANS_BWAIT;
                    end else begin
                        state_d = return_state_q;
                    end
                end
            end

            WAIT_BSY: begin
                trans_funct_d = TRANS_IDLE;
                if (dat_trans_o_ready && (trans_funct_q == TRANS_IDLE)) begin
                    state_d = return_state_q;
                end
            end

            WAIT_TRS: begin
                trans_funct_d = TRANS_IDLE;
                if (dat_trans_o_ready && (trans_funct_q != TRANS_BWAIT)) begin
                    state_d = IDLE;
                end
            end

            EXEC_WRT: begin
                if (dat_trans_o_ready) begin
                    trans_funct_d   = TRANS_WRITE;
                    trans_blk_num_d = blk_cnt_q;
                    state_d         = WAIT_WRT;
                    return_state_d  = (cmd_no_q == 6'd24) ? IDLE : CMD12;
                end
            end

            WAIT_WRT: begin
                trans_funct_d = TRANS_IDLE;
                if (cmd_trans_o_ready && dat_trans_o_ready && (trans_funct_q != TRANS_WRITE)) begin
                    state_d = return_state_q;
                end
            end

            WAIT_STP: begin
                if (dat_trans_o_ready) begin
                    trans_funct_d = TRANS_BWAIT;
                    state_d       = WAIT_TRS;
                end
            end

            CMD00: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd0;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = CMD08;
                    state_d        = EXEC_CMD;
                end
            end

            CMD08: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd8;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = WAIT_INI;
                    state_d        = EXEC_CMD;
                end
            end

            WAIT_INI: begin
                if (boot_cnt_q == 32'd0) begin
                    boot_cnt_d     = 32'd10_000_000;
                    state_d        = CMD55;
                    return_state_d = CMD41;
                end else begin
                    boot_cnt_d = boot_cnt_q - 1'b1;
                end
            end

            CMD55: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d  = 6'd55;
                    cmd_en_d  = 1'b1;
                    cmd_arg_d = {rca_q, 16'd0};
                    state_d   = EXEC_CMD;
                end
            end

            CMD41: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd41;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = CHK41;
                    state_d        = EXEC_CMD;
                end
            end

            CHK41: begin
                if (cmd_trans_o_rsp_dat[39]) begin
                    state_d = CMD02;
                end else begin
                    state_d = WAIT_INI;
                end
            end

            CMD02: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd2;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = CMD03;
                    state_d        = EXEC_CMD;
                end
            end

            CMD03: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd3;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = CMD07;
                    state_d        = EXEC_CMD;
                end
            end

            CMD07: begin
                if (cmd_trans_o_ready && dat_trans_o_ready) begin
                    cmd_no_d       = 6'd7;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = {cmd_trans_o_rsp_dat[39:24], 16'd0};
                    rca_d          = cmd_trans_o_rsp_dat[39:24];
                    trans_blk_num_d= 32'd0;
                    return_state_d = SETBW;
                    state_d        = EXEC_CMD;
                end
            end

            SETBW: begin
                state_d        = CMD55;
                return_state_d = CMD06;
            end

            CMD06: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd6;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = 32'd0;
                    return_state_d = IDLE;
                    state_d        = EXEC_CMD;
                end
            end

            CMD17: begin
                if (cmd_trans_o_ready && dat_trans_o_ready) begin
                    cmd_no_d       = 6'd17;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = blk_adr_q;
                    trans_funct_d  = TRANS_READ;
                    trans_blk_num_d= blk_cnt_q;
                    state_d        = EXEC_CMD;
                    return_state_d = WAIT_TRS;
                end
            end

            CMD18: begin
                if (cmd_trans_o_ready && dat_trans_o_ready) begin
                    cmd_no_d       = 6'd18;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = blk_adr_q;
                    trans_funct_d  = TRANS_READ;
                    trans_blk_num_d= blk_cnt_q;
                    state_d        = EXEC_CMD;
                    return_state_d = CMD12;
                end
            end

            CMD24: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd24;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = blk_adr_q;
                    state_d        = EXEC_CMD;
                    return_state_d = EXEC_WRT;
                end
            end

            CMD25: begin
                if (cmd_trans_o_ready) begin
                    cmd_no_d       = 6'd25;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = blk_adr_q;
                    state_d        = EXEC_CMD;
                    return_state_d = EXEC_WRT;
                end
            end

            CMD12: begin
                if (cmd_trans_o_ready && dat_trans_o_ready) begin
                    cmd_no_d       = 6'd12;
                    cmd_en_d       = 1'b1;
                    cmd_arg_d      = blk_adr_q;
                    state_d        = EXEC_CMD;
                    return_state_d = WAIT_STP;
                end
            end

            default: begin
                state_d = INIT;
            end
        endcase
    end

//==============================================================================
// Sequential state update
//------------------------------------------------------------------------------
    always @(posedge i_clk) begin
        if (i_rst) begin
            state_q         <= INIT;
            return_state_q  <= INIT;
            boot_cnt_q      <= 32'd10_000_000;
            blk_cnt_q       <= 32'd0;
            blk_adr_q       <= 32'd0;
            rca_q           <= 16'd0;

            cmd_no_q        <= 6'd0;
            cmd_en_q        <= 1'b0;
            cmd_arg_q       <= 32'd0;

            trans_funct_q   <= TRANS_IDLE;
            trans_blk_num_q <= 32'd0;

            sd_clk_q        <= 1'b0;
        end else begin
            state_q         <= state_d;
            return_state_q  <= return_state_d;
            boot_cnt_q      <= boot_cnt_d;
            blk_cnt_q       <= blk_cnt_d;
            blk_adr_q       <= blk_adr_d;
            rca_q           <= rca_d;

            cmd_no_q        <= cmd_no_d;
            cmd_en_q        <= cmd_en_d;
            cmd_arg_q       <= cmd_arg_d;

            trans_funct_q   <= trans_funct_d;
            trans_blk_num_q <= trans_blk_num_d;

            sd_clk_q        <= sd_clk_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
