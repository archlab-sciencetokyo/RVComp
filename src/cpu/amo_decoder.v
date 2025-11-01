/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* atomic memory operation decoder */
/******************************************************************************************/
module amo_decoder (
    input  wire                 [5:0] awatop_i      , // amo operation
    output reg  [`AMO_CTRL_WIDTH-1:0] amo_ctrl_o      // amo control
);

    always @(*) begin
        amo_ctrl_o  = 'h0   ;
        case (awatop_i)
            `AWATOP_ADD : begin amo_ctrl_o[`AMO_CTRL_IS_ADD]     = 1'b1;                                                                                   end
            `AWATOP_CLR : begin amo_ctrl_o[`AMO_CTRL_IS_CLR_SET] = 1'b1;                                                                                   end
            `AWATOP_EOR : begin amo_ctrl_o[`AMO_CTRL_IS_EOR]     = 1'b1;                                                                                   end
            `AWATOP_SET : begin amo_ctrl_o[`AMO_CTRL_IS_CLR_SET] = 1'b1; amo_ctrl_o[`AMO_CTRL_IS_SET_SWAP] = 1'b1;                                         end
            `AWATOP_SMAX: begin amo_ctrl_o[`AMO_CTRL_IS_SIGNED]  = 1'b1; amo_ctrl_o[`AMO_CTRL_IS_MAX]      = 1'b1; amo_ctrl_o[`AMO_CTRL_IS_MINMAX] = 1'b1; end
            `AWATOP_SMIN: begin amo_ctrl_o[`AMO_CTRL_IS_SIGNED]  = 1'b1;                                           amo_ctrl_o[`AMO_CTRL_IS_MINMAX] = 1'b1; end
            `AWATOP_UMAX: begin                                          amo_ctrl_o[`AMO_CTRL_IS_MAX]      = 1'b1; amo_ctrl_o[`AMO_CTRL_IS_MINMAX] = 1'b1; end
            `AWATOP_UMIN: begin                                                                                    amo_ctrl_o[`AMO_CTRL_IS_MINMAX] = 1'b1; end
            `AWATOP_SWAP: begin                                          amo_ctrl_o[`AMO_CTRL_IS_SET_SWAP] = 1'b1;                                         end
            default     : ;
        endcase
    end

endmodule
/******************************************************************************************/

`resetall
