/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"
 /* bimodal branch predictor */
 /******************************************************************************************/
module bimodal (
    input  wire             clk_i               , // clock
    input  wire             rst_i               , // reset
    input  wire             stall_i             , // stall
    input  wire [`XLEN-1:0] raddr_i             , // prediction address
    output reg        [1:0] pat_hist_o          , // pattern history
    output wire             br_pred_tkn_o       , // branch prediction
    output reg  [`XLEN-1:0] br_pred_pc_o        , // branch prediction program counter
    input  wire             br_tkn_i            , // is taken
    input  wire             br_vtsfr_i          , // is valid branch instruction
    input  wire [`XLEN-1:0] waddr_i             , // write address
    input  wire       [1:0] pat_hist_i          , // pattern history (waddr_i)
    input  wire [`XLEN-1:0] br_tkn_pc_i           // taken program counter (waddr_i)
);

    integer i;
    localparam OFFSET_WIDTH = $clog2(`XBYTES)   ;

    // pattern history table
    (* ram_style = "block" *) reg  [1:0] pht [0:`PHT_ENTRIES-1]; initial for (i=0; i<`PHT_ENTRIES; i=i+1) pht[i] = 2'b01;

    localparam VALID_PHT_INDEX_WIDTH            = $clog2(`PHT_ENTRIES);
    wire [VALID_PHT_INDEX_WIDTH-1:0] pht_ridx   = raddr_i[VALID_PHT_INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];
    wire [VALID_PHT_INDEX_WIDTH-1:0] pht_widx   = waddr_i[VALID_PHT_INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];

    wire [1:0] wr_pat_hist = (br_tkn_i) ? pat_hist_i+(pat_hist_i<2'd3) : pat_hist_i-(pat_hist_i>2'd0);

    always @(posedge clk_i) begin
        if (!stall_i) begin
            pat_hist_o  <= pht[pht_ridx]    ;
            if (br_vtsfr_i) begin
                pht[pht_widx]   <= wr_pat_hist  ;
            end
        end
    end

    // branch target buffer
    (* ram_style = "block" *) reg  [`XLEN:0] btb [0:`BTB_ENTRIES-1]; initial for (i=0; i<`BTB_ENTRIES; i=i+1) btb[i]='h0; // TODO: Need to compare tags.

    localparam VALID_BTB_INDEX_WIDTH    = $clog2(`BTB_ENTRIES);
    wire [VALID_BTB_INDEX_WIDTH-1:0] btb_ridx   = raddr_i[VALID_BTB_INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];
    wire [VALID_BTB_INDEX_WIDTH-1:0] btb_widx   = waddr_i[VALID_BTB_INDEX_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];

    reg br_tgt_v;
    always @(posedge clk_i) begin
        if (!stall_i) begin
            {br_tgt_v, br_pred_pc_o}    <= btb[btb_ridx];
            if (br_tkn_i) begin
                btb[btb_widx]   <= {1'b1, br_tkn_pc_i}  ;
            end
        end
    end

    // branch prediction
    assign br_pred_tkn_o = (br_tgt_v && pat_hist_o[1]);

endmodule
/******************************************************************************************/

`resetall
