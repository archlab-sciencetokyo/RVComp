/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* Card interface */
/* Wrapper for protocol core with block-level read/write operations */
/******************************************************************************************/
module sdcram_interface #(
    parameter BLOCK_NUM = 1 // number of 512-byte blocks per transfer
) (
    input  wire        clk_i        , // clock
    input  wire        rst_i        , // reset
    // request interface
    input  wire        req_en_i     , // request enable
    input  wire        req_rw_i     , // request read/write (0=read, 1=write)
    input  wire [40:0] req_adr_i    , // request address (byte-aligned)
    output wire        req_ack_o    , // request acknowledged
    // reply interface
    input  wire        rep_ready_i  , // reply ready (backpressure)
    output wire        rep_en_o     , // reply enable
    output wire        rep_rw_o     , // reply read/write
    output wire [40:0] rep_adr_o    , // reply address
    // debug
    output wire [ 2:0] sdi_state_o  , // interface state
    output wire [ 4:0] sdc_state_o  , // protocol state
    // cache interface
    output wire [40:0] cache_adr_o  , // cache address
    output wire [31:0] cache_din_o  , // cache data input
    output wire [ 3:0] cache_wen_o  , // cache write enable (byte-wise)
    output wire        cache_en_o   , // cache enable
    input  wire [31:0] cache_dout_i , // cache data output
    // SD card interface
    input  wire        sd_cd        , // card detect
    output wire        sd_rst       , // card reset
    output wire        sd_sclk      , // SD clock
    inout  wire        sd_cmd       , // command line
    inout  wire [ 3:0] sd_dat         // data lines
);

//==============================================================================
// State machine encoding
//------------------------------------------------------------------------------
    localparam SDC_INIT  = 3'd0;
    localparam SDC_IDLE  = 3'd1;
    localparam SDC_READ  = 3'd2;
    localparam SDC_WRITE = 3'd3;
    localparam SDC_REPLY = 3'd4;

//==============================================================================
// Protocol interface signals
//------------------------------------------------------------------------------
    wire        sdc_rd              ;
    wire [ 7:0] sdc_dout            ;
    wire        sdc_byte_available  ;
    wire        sdc_wr              ;
    wire [ 7:0] sdc_din             ;
    wire        sdc_ready_for_byte  ;
    wire        sdc_ready           ;
    wire [40:0] sdc_address         ;

//==============================================================================
// State machine registers
//------------------------------------------------------------------------------
    reg [ 2:0] state_q;
    reg [ 2:0] state_d;

//==============================================================================
// Data path registers
//------------------------------------------------------------------------------
    reg         sdc_rd_q     ;
    reg         sdc_rd_d     ;
    reg         sdc_wr_q     ;
    reg         sdc_wr_d     ;
    reg         rep_en_q     ;
    reg         rep_en_d     ;
    reg         rep_rw_q     ;
    reg         rep_rw_d     ;
    reg  [40:0] rep_adr_q    ;
    reg  [40:0] rep_adr_d    ;
    reg  [40:0] cache_adr_q  ;
    reg  [40:0] cache_adr_d  ;
    reg  [ 3:0] cache_wen_q  ;
    reg  [ 3:0] cache_wen_d  ;

//==============================================================================
// Protocol instance
//------------------------------------------------------------------------------
    sdcram_protocol sdc (
        .i_clk         (clk_i               ), // input  wire
        .i_rst         (rst_i               ), // input  wire
        .o_ready       (sdc_ready           ), // output wire
        // read interface
        .i_ren         (sdc_rd              ), // input  wire
        .o_data        (sdc_dout            ), // output wire                   [7:0]
        .o_data_en     (sdc_byte_available  ), // output wire
        // write interface
        .i_wen         (sdc_wr              ), // input  wire
        .i_data        (sdc_din             ), // input  wire                   [7:0]
        .o_data_ready  (sdc_ready_for_byte  ), // output wire
        // control
        .i_blk_num     (BLOCK_NUM           ), // input  wire                  [31:0]
        .i_adr         (sdc_address[40:9]   ), // input  wire                  [31:0]
        .o_state       (sdc_state_o         ), // output wire                   [4:0]
        // SD card interface
        .sd_cd         (sd_cd               ), // input  wire
        .sd_rst        (sd_rst              ), // output wire
        .sd_clk        (sd_sclk             ), // output reg
        .sd_cmd        (sd_cmd              ), // inout  wire
        .sd_dat        (sd_dat              )  // inout  wire                   [3:0]
    );

//==============================================================================
// Output assignments
//------------------------------------------------------------------------------
    assign sdc_rd      = sdc_rd_q         ;
    assign sdc_din     = cache_dout_shifted[7:0];
    assign sdc_wr      = sdc_wr_q         ;
    assign sdc_address = rep_adr_q        ;

    assign req_ack_o   = (state_q == SDC_IDLE) && req_en_i;

    assign rep_en_o    = rep_en_q         ;
    assign rep_rw_o    = rep_rw_q         ;
    assign rep_adr_o   = rep_adr_q        ;

    assign cache_adr_o = cache_adr_q      ;
    assign cache_wen_o = sdc_byte_available ? cache_wen_q : 4'h0;
    assign cache_din_o = {4{sdc_dout}}    ;
    assign cache_en_o  = (state_q == SDC_READ) || (state_q == SDC_WRITE);

    assign sdi_state_o = state_q          ;

//==============================================================================
// Cache data shifter for byte writes
//------------------------------------------------------------------------------
    wire [31:0] cache_dout_shifted = cache_dout_i >> {cache_adr_q[1:0], 3'b000};

//==============================================================================
// Combinational next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        // Default assignments
        state_d     = state_q    ;
        sdc_rd_d    = sdc_rd_q   ;
        sdc_wr_d    = sdc_wr_q   ;
        rep_en_d    = rep_en_q   ;
        rep_rw_d    = rep_rw_q   ;
        rep_adr_d   = rep_adr_q  ;
        cache_adr_d = cache_adr_q;
        cache_wen_d = cache_wen_q;

        case (state_q)
            SDC_INIT: begin
                if (sdc_ready) begin
                    state_d = SDC_IDLE;
                end
                sdc_rd_d    = 1'b0  ;
                sdc_wr_d    = 1'b0  ;
                rep_en_d    = 1'b0  ;
                rep_rw_d    = 1'b0  ;
                rep_adr_d   = 41'h0 ;
                cache_adr_d = 41'h0 ;
                cache_wen_d = 4'h0  ;
            end

            SDC_IDLE: begin
                if (req_en_i) begin
                    state_d     = req_rw_i ? SDC_WRITE : SDC_READ;
                    sdc_rd_d    = !req_rw_i;
                    sdc_wr_d    = req_rw_i ;
                    rep_adr_d   = req_adr_i;
                    rep_rw_d    = req_rw_i ;
                    cache_adr_d = req_adr_i;
                    cache_wen_d = req_rw_i ? 4'h0 : 4'h1;
                end
                rep_en_d = 1'b0;
            end

            SDC_READ: begin
                if (sdc_byte_available) begin
                    cache_adr_d = cache_adr_q + 1'b1;
                    cache_wen_d = {cache_wen_q[2:0], cache_wen_q[3]};
                    sdc_rd_d    = 1'b0;
                end else if (sdc_ready && !sdc_rd_q) begin
                    state_d = SDC_REPLY;
                end
            end

            SDC_WRITE: begin
                if (sdc_ready_for_byte) begin
                    cache_adr_d = cache_adr_q + 1'b1;
                    sdc_wr_d    = 1'b0;
                end else if (sdc_ready && !sdc_wr_q) begin
                    state_d = SDC_REPLY;
                end
            end

            SDC_REPLY: begin
                if (rep_ready_i) begin
                    rep_en_d = 1'b1     ;
                    state_d  = SDC_IDLE ;
                end else begin
                    rep_en_d = 1'b0;
                end
                cache_wen_d = 4'h0;
            end

            default: begin
                state_d = SDC_INIT;
            end
        endcase
    end

//==============================================================================
// Sequential state update
//------------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q     <= SDC_INIT;
            sdc_rd_q    <= 1'b0    ;
            sdc_wr_q    <= 1'b0    ;
            rep_en_q    <= 1'b0    ;
            rep_rw_q    <= 1'b0    ;
            rep_adr_q   <= 41'h0   ;
            cache_adr_q <= 41'h0   ;
            cache_wen_q <= 4'h0    ;
        end else begin
            state_q     <= state_d    ;
            sdc_rd_q    <= sdc_rd_d   ;
            sdc_wr_q    <= sdc_wr_d   ;
            rep_en_q    <= rep_en_d   ;
            rep_rw_q    <= rep_rw_d   ;
            rep_adr_q   <= rep_adr_d  ;
            cache_adr_q <= cache_adr_d;
            cache_wen_q <= cache_wen_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
