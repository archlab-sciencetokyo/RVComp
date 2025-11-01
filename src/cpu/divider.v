/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* division */
/******************************************************************************************/
module divider (
    input  wire                       clk_i         , // clock
    input  wire                       rst_i         , // reset
    input  wire                       valid_i       , // instruction valid
    output wire                       stall_o       , // stall while executing
    input  wire                       ready_i       , // ready to accept new instruction
    output wire                       ready_o       , // ready of this module
    input  wire [`DIV_CTRL_WIDTH-1:0] div_ctrl_i    , // division control
    input  wire           [`XLEN-1:0] src1_i        , // rs1 value
    input  wire           [`XLEN-1:0] src2_i        , // rs2 value
    output wire           [`XLEN-1:0] rslt_o          // result of div
);

    localparam IDLE = 2'd0, CHECK = 2'd1, EXEC = 2'd2, RET = 2'd3;
    wire       stall                ;
    reg        stall_q              ;
    reg  [1:0] state_q  , state_d   ;

    assign stall    = (state_d!=IDLE)  ;
    assign stall_o  = stall_q          ;
    assign ready_o  = (state_q==IDLE) || (state_q==RET) ;

    reg                       is_dividend_neg_q , is_dividend_neg_d ;
    reg                       is_divisor_neg_q  , is_divisor_neg_d  ;
    reg           [`XLEN-1:0] remainder_q       , remainder_d       ;
    reg           [`XLEN-1:0] divisor_q         , divisor_d         ;
    reg           [`XLEN-1:0] quotient_q        , quotient_d        ;
    reg                       is_div_rslt_neg_q , is_div_rslt_neg_d ;
    reg                       is_rem_rslt_neg_q , is_rem_rslt_neg_d ;
    reg                       is_rem_q          , is_rem_d          ;
    reg           [`XLEN-1:0]                     rslt_d            ;
    reg [$clog2(`XLEN+1)-1:0] cntr_q            , cntr_d            ;

    wire [`XLEN-1:0] uintx_remainder    = (is_dividend_neg_q) ? ~remainder_q+1 : remainder_q        ;
    wire [`XLEN-1:0] uintx_divisor      = (is_divisor_neg_q ) ? ~divisor_q+1   : divisor_q          ;
    wire   [`XLEN:0] difference         = {remainder_q[`XLEN-2:0], quotient_q[`XLEN-1]} - divisor_q ;
    wire             q                  = !difference[`XLEN]                                        ;

    wire             is_div             = div_ctrl_i[`DIV_CTRL_IS_DIV]        ;
    wire             is_rem             = div_ctrl_i[`DIV_CTRL_IS_REM]        ;
    wire             is_sign            = div_ctrl_i[`DIV_CTRL_IS_SIGNED]     ;

//    assign rslt_o = rslt_q;
    assign rslt_o = rslt_d;

    always @(*) begin
        is_dividend_neg_d   = is_dividend_neg_q ;
        is_divisor_neg_d    = is_divisor_neg_q  ;
        remainder_d         = remainder_q       ;
        divisor_d           = divisor_q         ;
        quotient_d          = quotient_q        ;
        is_div_rslt_neg_d   = is_div_rslt_neg_q ;
        is_rem_rslt_neg_d   = is_rem_rslt_neg_q ;
        is_rem_d            = is_rem_q          ;
        rslt_d              = 'h0               ;
        cntr_d              = cntr_q            ;
        state_d             = state_q           ;
        case (state_q)
            IDLE    : begin
                if (valid_i && is_div) begin
                    is_dividend_neg_d   = is_sign && src1_i[`XLEN-1]                     ;
                    is_divisor_neg_d    = is_sign && src2_i[`XLEN-1]                     ;
                    remainder_d         = src1_i                                         ;
                    divisor_d           = src2_i                                         ;
                    is_div_rslt_neg_d   = is_sign && (src1_i[`XLEN-1] ^ src2_i[`XLEN-1]) ;
                    is_rem_rslt_neg_d   = is_sign &&  src1_i[`XLEN-1]                    ;
                    is_rem_d            = is_rem                                         ;
                    state_d             = CHECK                                          ;
                end
            end
            CHECK   : begin
                if (divisor_q=='h00000000) begin
                    quotient_d                  = {`XLEN{1'b1}}                     ;
                    is_div_rslt_neg_d           = 1'b0                              ;
                    is_rem_rslt_neg_d           = 1'b0                              ;
                    state_d                     = RET                               ;
                end else begin
                    {remainder_d, quotient_d}   = {{`XLEN{1'b0}}, uintx_remainder}  ;
                    divisor_d                   = uintx_divisor                     ;
                    cntr_d                      = `XLEN-1                           ;
                    state_d                     = EXEC                              ;
                end
            end
            EXEC    : begin
                {remainder_d, quotient_d}       = (q) ? { difference[`XLEN-1:0], quotient_q[`XLEN-2:0], 1'b1} :
                                                        {remainder_q[`XLEN-2:0], quotient_q           , 1'b0} ;
                cntr_d      = cntr_q-'h1                                            ;
                if (cntr_q==0) begin // (cntr_q==0)
                    state_d = RET                                                   ;
                end
            end
            RET     : begin
                rslt_d      = (is_rem_q) ? ((is_rem_rslt_neg_q) ? ~remainder_q+1 : remainder_q) :
                                           ((is_div_rslt_neg_q) ? ~quotient_q+1  : quotient_q ) ;
                if (ready_i) begin
                    state_d     = IDLE                                                  ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q             <= IDLE             ;
            stall_q             <= 1'b0             ;
        end else begin
            is_dividend_neg_q   <= is_dividend_neg_d;
            is_divisor_neg_q    <= is_divisor_neg_d ;
            remainder_q         <= remainder_d      ;
            divisor_q           <= divisor_d        ;
            quotient_q          <= quotient_d       ;
            is_div_rslt_neg_q   <= is_div_rslt_neg_d;
            is_rem_rslt_neg_q   <= is_rem_rslt_neg_d;
            is_rem_q            <= is_rem_d         ;
            cntr_q              <= cntr_d           ;
            state_q             <= state_d          ;
            stall_q             <= stall            ;
        end
    end
endmodule
/******************************************************************************************/

`resetall
