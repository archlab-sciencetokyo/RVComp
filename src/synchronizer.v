/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`resetall
`default_nettype none

/* synchronizer */
/******************************************************************************************/
module synchronizer (
    input  wire clk_i   , // clock
    input  wire d_i     , // data input
    output wire q_o       // data output
);

    // Mark as CDC synchronizer flops for implementation tools.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ff1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg ff2;
    always @(posedge clk_i) begin
        ff1 <= d_i  ;
        ff2 <= ff1  ;
    end
    assign q_o = ff2;

endmodule
/******************************************************************************************/

`resetall
