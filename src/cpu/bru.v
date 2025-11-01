/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* branch unit */
/******************************************************************************************/
module bru (
    input  wire [`BRU_CTRL_WIDTH-1:0] bru_ctrl_i        , // branch control
    input  wire           [`XLEN-1:0] src1_i            , // rs1 value
    input  wire           [`XLEN-1:0] src2_i            , // rs2 value
    input  wire           [`XLEN-1:0] pc_i              , // program counter
    input  wire           [`XLEN-1:0] imm_i             , // immediate value
    input  wire           [`XLEN-1:0] npc_i             , // next program counter
    input  wire                       br_pred_tkn_i     , // is branch (prediction)
    output wire                       is_ctrl_tsfr_o    , // is control transfer
    output wire                       br_tkn_o          , // is branch (true)
    output wire                       br_misp_rslt1_o   , // prediciton of jump is wrong
    output wire                       br_misp_rslt2_o   , // prediction of unjump is wrong
    output wire           [`XLEN-1:0] br_tkn_pc_o       , // taken program counter
    output wire           [`XLEN-1:0] rslt_o              // result of jal or jalr
);

    wire signed [`XLEN:0] sext_src1 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i};
    wire signed [`XLEN:0] sext_src2 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src2_i[`XLEN-1], src2_i};

    wire beq_bne_tkn        = (     src1_i==     src2_i) ? bru_ctrl_i[`BRU_CTRL_IS_BEQ] : bru_ctrl_i[`BRU_CTRL_IS_BNE];
    wire blt_bge_tkn        = (sext_src1  < sext_src2  ) ? bru_ctrl_i[`BRU_CTRL_IS_BLT] : bru_ctrl_i[`BRU_CTRL_IS_BGE];
    assign br_tkn_o         = beq_bne_tkn | blt_bge_tkn | bru_ctrl_i[`BRU_CTRL_IS_JAL_JALR];

    wire [`XLEN-1:0] br_tkn_pc_t;
    assign br_tkn_pc_t      = ((bru_ctrl_i[`BRU_CTRL_IS_JALR]) ? src1_i : pc_i) + imm_i;
    assign br_tkn_pc_o      = {br_tkn_pc_t[`XLEN-1:1], 1'b0};

    assign is_ctrl_tsfr_o   = (bru_ctrl_i[`BRU_CTRL_IS_CTRL_TSFR] || br_pred_tkn_i);

    assign br_misp_rslt1_o  = (npc_i!=br_tkn_pc_o   );
    assign br_misp_rslt2_o  = (npc_i!=(pc_i+'h4)    );

    assign rslt_o           = (bru_ctrl_i[`BRU_CTRL_IS_JAL_JALR]) ? pc_i+4 : 0;

endmodule
/******************************************************************************************/

`resetall
