/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none
`include "rvcom.vh"

/* multplier */
/******************************************************************************************/
module multiplier (
    input  wire        clk_i     , // clock
    input  wire        rst_i     , // reset
    input  wire        valid_i   , // instruction valid
    output wire        stall_o   , // stall while executing
    input  wire        ready_i   , // ready to accept new instruction
    output wire        ready_o   , // ready of this module
    input  wire  [3:0] mul_ctrl_i, // multiplication control
    input  wire [31:0] src1_i    , // rs1 value
    input  wire [31:0] src2_i    , // rs2 value
    output wire [31:0] rslt_o      // result of mul
);
    localparam IDLE = 2'd0, EXEC = 2'd1, RET = 2'd2;
    reg  [1:0] state_q  , state_d   ;

    wire       stall                ;
    reg        stall_q              ;
    assign stall    = (state_d!=IDLE) ;
    assign stall_o  = stall_q         ;
    assign ready_o  = (state_q!=EXEC) ;

    reg signed [`XLEN:0] multiplicand_q , multiplicand_d;
    reg signed [`XLEN:0] multiplier_q   , multiplier_d  ;
    reg    [`XLEN*2-1:0] product_q      , product_d     ;
    reg                  is_high_q      , is_high_d     ;
    reg      [`XLEN-1:0]                  rslt_d        ;


    wire is_mul         = mul_ctrl_i[`MUL_CTRL_IS_MUL]        ;
    wire is_src1_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC1_SIGNED];
    wire is_src2_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC2_SIGNED];
    wire is_high        = mul_ctrl_i[`MUL_CTRL_IS_HIGH]       ;

    assign rslt_o = rslt_d;

    always @(*) begin
        product_d       = product_q     ;
        is_high_d       = is_high_q     ;
        rslt_d          = 'h0           ;
        state_d         = state_q       ;
        case (state_q)
            IDLE    : begin
                if (valid_i && is_mul) begin
                    multiplicand_d  = {is_src1_signed && src1_i[`XLEN-1], src1_i} ;
                    multiplier_d    = {is_src2_signed && src2_i[`XLEN-1], src2_i} ;
                    is_high_d       = is_high                                     ;
                    state_d         = EXEC                                        ;
                end
            end
            EXEC    : begin
                product_d   = multiplicand_q * multiplier_q ;
                state_d     = RET                           ;
            end
            RET     : begin
                rslt_d      = (is_high_q) ? product_q[`XLEN*2-1:`XLEN] : product_q[`XLEN-1:0]   ;
                if (ready_i) begin
                    state_d     = IDLE                                                          ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q         <= IDLE             ;
            stall_q         <= 1'b0             ;
        end else begin
            multiplicand_q  <= multiplicand_d   ;
            multiplier_q    <= multiplier_d     ;
            product_q       <= product_d        ;
            is_high_q       <= is_high_d        ;
            state_q         <= state_d          ;
            stall_q         <= stall            ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
