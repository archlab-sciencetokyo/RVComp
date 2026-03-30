/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`resetall
`default_nettype none

`include "axi.vh"

/* rom to load boot code */
/******************************************************************************************/
module bootrom #(
    parameter  ROM_SIZE     = 0             , // size of bootrom
    parameter  ADDR_WIDTH   = 0             , // address width
    parameter  DATA_WIDTH   = 0             , // data width
    localparam STRB_WIDTH   = DATA_WIDTH/8    // strobe width
) (
    input  wire                    clk_i        , // clock
    input  wire                    rst_i        , // reset
    input  wire                    arvalid_i    , // read request valid
    output wire                    arready_o    , // read request ready
    input  wire   [ADDR_WIDTH-1:0] araddr_i     , // read request address
    output reg                     rvalid_o     , // read response valid
    input  wire                    rready_i     , // read response ready
    output reg    [DATA_WIDTH-1:0] rdata_o      , // read response data
    output wire [`RRESP_WIDTH-1:0] rresp_o        // read response status
);

    // DRC: design rule check
    initial begin
        if (ROM_SIZE  ==0) $fatal(1, "specify a bootrom ROM_SIZE");
        if (ADDR_WIDTH==0) $fatal(1, "specify a bootrom ADDR_WIDTH");
        if (DATA_WIDTH==0) $fatal(1, "specify a bootrom DATA_WIDTH");
    end

    localparam OFFSET_WIDTH     = $clog2(STRB_WIDTH)            ;
    localparam VALID_ADDR_WIDTH = $clog2(ROM_SIZE)-OFFSET_WIDTH ;
    (* rom_style = "block" *) reg  [DATA_WIDTH-1:0] rom [0:2**VALID_ADDR_WIDTH-1]   ;

    wire [VALID_ADDR_WIDTH-1:0] valid_araddr = araddr_i[VALID_ADDR_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];

    initial begin
`ifdef SYNTHESIS
        $readmemh("bootrom.mem", rom);
`else
        $readmemh("bootrom/bootrom.mem", rom);
`endif
    end

    assign arready_o    = (!rvalid_o || rready_i)   ;
    assign rresp_o      = `RRESP_OKAY               ;

    always @(posedge clk_i) begin
        if (rst_i) begin
            rvalid_o    <= 1'b0             ;
            rdata_o     <= 'h0              ;
        end else if (arready_o) begin
            rvalid_o    <= arvalid_i        ;
            if (arvalid_i) begin
                rdata_o <= rom[valid_araddr];
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall
