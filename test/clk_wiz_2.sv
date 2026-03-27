/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* clocking wizard for simulation */
/******************************************************************************************/
module clk_wiz_2 (
    output logic clk_out1   , // clk_o 
    output logic clk_out2   , // clk_o
    input  logic reset      , // reset
    output logic locked     , // locked
    input  logic clk_in1      // clk_in : 100.00000 MHz
);

    assign locked   = !reset;
    bit clk_50_mhz; always #200 clk_50_mhz <= !clk_50_mhz;
    assign clk_out1 = clk_50_mhz;
`ifdef ETH_IF_RMII
    assign #25 clk_out2 = clk_50_mhz; // 45 degree phase shift
`else
    bit clk_25_mhz; always #400 clk_25_mhz <= !clk_25_mhz;
    assign #50 clk_out2 = clk_25_mhz; // 45 degree phase shift
`endif

endmodule
/******************************************************************************************/

`resetall
