/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* clocking wizard for simulation */
/******************************************************************************************/
module clk_wiz_0 (
    output logic clk_out1   , // sys_clk: 166.66667 MHz
    output logic clk_out2   , // clk_ref: 200.00000 MHz
    input  logic reset      , // reset
    output logic locked     , // locked
    input  logic clk_in1      // clk_in: 100.00000 MHz
);

    assign locked   = !reset        ;
    bit clk_166_66667_mhz; always #24 clk_166_66667_mhz <= !clk_166_66667_mhz;
    bit clk_200_mhz      ; always #20 clk_200_mhz       <= !clk_200_mhz      ;
    assign clk_out1 = clk_166_66667_mhz ;
    assign clk_out2 = clk_200_mhz       ;

endmodule
/******************************************************************************************/

`resetall
