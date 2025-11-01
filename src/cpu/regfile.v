/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* register file */
/******************************************************************************************/
module regfile (
    input  wire             clk_i       , // clock
    input  wire             stall_i     , // stall while executing
    input  wire       [4:0] rs1_i       , // rs1 index
    input  wire       [4:0] rs2_i       , // rs2 index
    output wire [`XLEN-1:0] xrs1_o      , // rs1 data
    output wire [`XLEN-1:0] xrs2_o      , // rs2 data
    input  wire             we_i        , // write enable
    input  wire       [4:0] rd_i        , // write index
    input  wire [`XLEN-1:0] wdata_i       // write data
);

    (* ram_style = "distibuted" *) reg  [`XLEN-1:0] xreg [0:31] ;

    assign xrs1_o   = (rs1_i==5'd0) ? 'h0 : xreg[rs1_i];
    assign xrs2_o   = (rs2_i==5'd0) ? 'h0 : xreg[rs2_i];
    always @(posedge clk_i) begin
        if (!stall_i) begin
            if (we_i) begin
                xreg[rd_i] <= wdata_i;
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall
