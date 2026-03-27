/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* Cache Tags */
/* Manages cache line tags, valid and dirty bits */
/******************************************************************************************/
module cache_tags #(
    parameter DEPTH     = 8, // number of cache lines
    parameter BLOCK_NUM = 1  // number of blocks per cache line
) (
    input  wire        clk_i   , // clock
    input  wire        rst_i   , // reset
    input  wire [40:0] addr_i  , // address to lookup/update
    input  wire        dirty_i , // dirty bit to write
    input  wire        wen_i   , // write enable
    output wire        valid_o , // valid bit of current entry
    output wire        hit_o   , // cache hit
    output wire        dirty_o , // dirty bit of current entry
    output wire [40:0] addr_o  , // stored address of current entry
    output wire        ready_o   // ready (reset complete)
);

//==============================================================================
// Parameters
//------------------------------------------------------------------------------
    localparam TAG_WIDTH = 41 - 9 - $clog2(DEPTH) - $clog2(BLOCK_NUM);

//==============================================================================
// Tag storage arrays
//------------------------------------------------------------------------------
    reg             valids [DEPTH-1:0];
    reg             dirtys [DEPTH-1:0];
    reg [TAG_WIDTH-1:0] tags   [DEPTH-1:0];

//==============================================================================
// Address decomposition
//------------------------------------------------------------------------------
    wire [$clog2(DEPTH)-1:0]     tag_idx    = addr_i[9+$clog2(DEPTH)+$clog2(BLOCK_NUM)-1:9+$clog2(BLOCK_NUM)];
    wire [TAG_WIDTH-1:0]         tag        = addr_i[40:9+$clog2(DEPTH)+$clog2(BLOCK_NUM)];
    wire [8+$clog2(BLOCK_NUM):0] offset     = addr_i[8+$clog2(BLOCK_NUM):0];

//==============================================================================
// Tag lookup
//------------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0] stored_tag   = tags[tag_idx]  ;
    wire                 stored_valid = valids[tag_idx];
    wire                 stored_dirty = dirtys[tag_idx];

//==============================================================================
// Output logic
//------------------------------------------------------------------------------
    assign valid_o = wen_i ? 1'b1 : stored_valid;
    assign hit_o   = wen_i ? 1'b1 : (tag == stored_tag);
    assign dirty_o = wen_i ? dirty_i : stored_dirty;
    assign addr_o  = {stored_tag, tag_idx, offset};

//==============================================================================
// Reset detection and counter
//------------------------------------------------------------------------------
    reg [$clog2(DEPTH):0] rst_cnt_q;
    reg [$clog2(DEPTH):0] rst_cnt_d;
    reg                   rst_det_q;
    reg                   rst_det_d;

    wire rst_fin = rst_cnt_q[$clog2(DEPTH)];
    wire wen     = wen_i || rst_det_q       ;

    wire [$clog2(DEPTH)-1:0] write_idx = rst_det_q ? rst_cnt_q[$clog2(DEPTH)-1:0] : tag_idx;

    assign ready_o = !rst_det_q;

//==============================================================================
// Reset detection logic
//------------------------------------------------------------------------------
    always @(*) begin
        if (rst_i) begin
            rst_det_d = 1'b1;
        end else if (rst_fin) begin
            rst_det_d = 1'b0;
        end else begin
            rst_det_d = rst_det_q;
        end
    end

//==============================================================================
// Reset counter logic
//------------------------------------------------------------------------------
    always @(*) begin
        if (rst_i) begin
            rst_cnt_d = {($clog2(DEPTH)+1){1'b0}};
        end else if (rst_det_q) begin
            rst_cnt_d = rst_cnt_q + 1'b1;
        end else begin
            rst_cnt_d = {($clog2(DEPTH)+1){1'b0}};
        end
    end

//==============================================================================
// Sequential logic
//------------------------------------------------------------------------------
    always @(posedge clk_i) begin
        rst_det_q <= rst_det_d;
        rst_cnt_q <= rst_cnt_d;

        if (wen) begin
            valids[write_idx] <= rst_det_q ? 1'b0 : 1'b1;
            dirtys[write_idx] <= rst_det_q ? 1'b0 : dirty_i;
            tags[write_idx]   <= rst_det_q ? {TAG_WIDTH{1'b0}} : tag;
        end
    end

endmodule
/******************************************************************************************/

`resetall
