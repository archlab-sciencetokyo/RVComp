/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* global clock buffer (BUFG) for simulation */
/******************************************************************************************/
module BUFG (
    input  logic I, // input clock
    output logic O  // output clock
);
    assign O = I;
endmodule
/******************************************************************************************/

`resetall