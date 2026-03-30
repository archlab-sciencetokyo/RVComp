/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* clocking wizard for simulation */
/******************************************************************************************/
module clk_wiz_3 (
    output logic clk_out1   , // clk_o
    output logic clk_out2   , // clk_o
    input  logic reset      , // reset
    output logic locked     , // locked
    input  logic clk_in1      // clk_in : 100.00000 MHz
);

    assign locked = !reset;

    bit clk_24_mhz; always #417 clk_24_mhz <= !clk_24_mhz;
    assign clk_out1 = clk_24_mhz;
    assign clk_out2 = clk_24_mhz;

endmodule
/******************************************************************************************/

`resetall
