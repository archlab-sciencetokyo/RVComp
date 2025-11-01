/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* clocking wizard for simulation */
/******************************************************************************************/
module clk_wiz_1 (
    output logic clk_out1   , // clk_o  : `CLK_FREQ_MHZ MHz (160.00000 MHz)
    input  logic reset      , // reset
    output logic locked     , // locked
    input  logic clk_in1      // clk_in : 100.00000 MHz
);

    assign locked   = !reset        ;
    bit clk_160_mhz; always #25 clk_160_mhz <= !clk_160_mhz;
    assign clk_out1 = clk_160_mhz   ;

endmodule
/******************************************************************************************/

`resetall
