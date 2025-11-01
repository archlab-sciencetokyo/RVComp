/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* input buffer (IBUF) for simulation */
/******************************************************************************************/
module IBUF (
    input  logic I, // input signal
    output logic O  // output signal
);
    assign O = I;
endmodule
/******************************************************************************************/

`resetall