/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* arithmetic logic unit */
/******************************************************************************************/
module alu (
    input  wire [`ALU_CTRL_WIDTH-1:0] alu_ctrl_i    , // alu control
    input  wire           [`XLEN-1:0] src1_i        , // rs1 value
    input  wire           [`XLEN-1:0] src2_i        , // rs2 value
    output wire           [`XLEN-1:0] rslt_o          // result of alu
);

    wire         [`XLEN+1:0] adder_src1         = {alu_ctrl_i[`ALU_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i, 1'b1};
    wire         [`XLEN+1:0] adder_src2         = {alu_ctrl_i[`ALU_CTRL_IS_SIGNED] && src2_i[`XLEN-1], src2_i, 1'b0} ^ {(`XLEN+2){alu_ctrl_i[`ALU_CTRL_IS_NEG]}};
    wire         [`XLEN+1:0] adder_rslt_t       = adder_src1+adder_src2;
    wire                     less_rslt          = alu_ctrl_i[`ALU_CTRL_IS_LESS] && adder_rslt_t[`XLEN+1];
    wire         [`XLEN-1:0] adder_rslt         = (alu_ctrl_i[`ALU_CTRL_IS_ADD]) ? adder_rslt_t[`XLEN:1] : 0;

    wire signed    [`XLEN:0] right_shifter_src1 = {alu_ctrl_i[`ALU_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i};
    wire [$clog2(`XLEN)-1:0] shamt              = src2_i[$clog2(`XLEN)-1:0];
    wire         [`XLEN-1:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?             src1_i <<  shamt : 0;
    wire         [`XLEN-1:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ? right_shifter_src1 >>> shamt : 0;

    wire         [`XLEN-1:0] bitwise_rslt       = ((alu_ctrl_i[`ALU_CTRL_IS_XOR_OR]) ? (src1_i ^ src2_i) : 0) | ((alu_ctrl_i[`ALU_CTRL_IS_OR_AND]) ? (src1_i & src2_i) : 0);
    wire         [`XLEN-1:0] lui_auipc_rslt     = (alu_ctrl_i[`ALU_CTRL_IS_SRC2]) ? src2_i : 0;

    assign rslt_o = less_rslt | adder_rslt | left_shifter_rslt | right_shifter_rslt | bitwise_rslt | lui_auipc_rslt;

endmodule
/******************************************************************************************/

`resetall
