/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* immediate generator */
/******************************************************************************************/
module imm_gen (
    input  wire                  [31:0] ir_i            , // instruction
    input  wire [`INSTR_TYPE_WIDTH-1:0] instr_type_i    , // instruction type
    output wire             [`XLEN-1:0] imm_o             // immediate value
);

    wire                  [31:0] ir         = ir_i          ;
    wire [`INSTR_TYPE_WIDTH-1:0] instr_type = instr_type_i  ;

    reg [`XLEN-1:0] imm;
    always @(*) begin
        // generate immediate value
        case (instr_type)
            `I_TYPE                             : imm[    0] =    ir[   20]     ;
            `S_TYPE                             : imm[    0] =    ir[    7]     ;
            default                             : imm[    0] =     1'b0         ;
        endcase
        case (instr_type)
            `I_TYPE, `J_TYPE                    : imm[ 4: 1] =    ir[24:21]     ;
            `S_TYPE, `B_TYPE                    : imm[ 4: 1] =    ir[11: 8]     ;
            default                             : imm[ 4: 1] = { 4{1'b0}}       ;
        endcase
        case (instr_type)
            `I_TYPE, `S_TYPE, `B_TYPE, `J_TYPE  : imm[10: 5] =    ir[30:25]     ;
            default                             : imm[10: 5] = { 6{1'b0}}       ;
        endcase
        case (instr_type)
            `I_TYPE, `S_TYPE                    : imm[   11] =    ir[   31]     ;
            `B_TYPE                             : imm[   11] =    ir[    7]     ;
            `J_TYPE                             : imm[   11] =    ir[   20]     ;
            default                             : imm[   11] =     1'b0         ;
        endcase
        case (instr_type)
            `I_TYPE, `S_TYPE, `B_TYPE           : imm[19:12] = { 8{ir[   31]}}  ;
            `U_TYPE, `J_TYPE                    : imm[19:12] =     ir[19:12]    ;
            default                             : imm[19:12] = { 8{1'b0}};
        endcase
        case (instr_type)
            `I_TYPE, `S_TYPE, `B_TYPE, `J_TYPE  : imm[30:20] = {11{ir[   31]}}  ;
            `U_TYPE                             : imm[30:20] =     ir[30:20]    ;
            default                             : imm[30:20] = {11{1'b0}}       ;
        endcase
        imm[31] = (instr_type==`R_TYPE) ? 1'b0 : ir[31];
    end

    assign imm_o    = imm   ;

endmodule
/******************************************************************************************/

`resetall
