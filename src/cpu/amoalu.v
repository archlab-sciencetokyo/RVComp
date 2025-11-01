/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* atomic memory operation arithmetic logic unit */
/******************************************************************************************/
module amoalu (
    input  wire [`AMO_CTRL_WIDTH-1:0] amo_ctrl_i    , // amo control
    input  wire           [`XLEN-1:0] src1_i        , // rs1 value
    input  wire           [`XLEN-1:0] src2_i        , // rs2 value
    output wire           [`XLEN-1:0] rslt_o          // result of amoalu
);

    wire signed [`XLEN:0] sext_src1 = {amo_ctrl_i[`AMO_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i};
    wire signed [`XLEN:0] sext_src2 = {amo_ctrl_i[`AMO_CTRL_IS_SIGNED] && src2_i[`XLEN-1], src2_i};

    wire [`XLEN-1:0] adder_rslt     = (amo_ctrl_i[`AMO_CTRL_IS_ADD]     ) ? src1_i +  src2_i : 0;
    wire [`XLEN-1:0] clr_set_rslt   = (amo_ctrl_i[`AMO_CTRL_IS_CLR_SET] ) ? src1_i & ~src2_i : 0;
    wire [`XLEN-1:0] eor_rslt       = (amo_ctrl_i[`AMO_CTRL_IS_EOR]     ) ? src1_i ^  src2_i : 0;
    wire [`XLEN-1:0] minmax_rslt    = (amo_ctrl_i[`AMO_CTRL_IS_MINMAX]  ) ? ((amo_ctrl_i[`AMO_CTRL_IS_MAX] ^ (sext_src1 < sext_src2)) ? src1_i : src2_i) : 0;
    wire [`XLEN-1:0] set_swap_rslt  = (amo_ctrl_i[`AMO_CTRL_IS_SET_SWAP]) ?           src2_i : 0;

    assign rslt_o   = adder_rslt | clr_set_rslt | eor_rslt | minmax_rslt | set_swap_rslt;

endmodule
/******************************************************************************************/

`resetall
