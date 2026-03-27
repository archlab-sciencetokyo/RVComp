/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* simple dual-port two-clock RAM */
/******************************************************************************************/
module sdp_2clk #(
    parameter  NUM_COL         = 4                    , // number of write-enable columns
    parameter  COL_WIDTH       = 8                    , // column width
    parameter  RAM_WIDTH       = 36                   , // RAM data width
    parameter  RAM_DEPTH       = 512                  , // RAM depth
    parameter  RAM_PERFORMANCE = "HIGH_PERFORMANCE"  , // "HIGH_PERFORMANCE" or "LOW_LATENCY"
    parameter  INIT_FILE       = ""                    // memory initialization file
) (
    input  wire [clogb2(RAM_DEPTH-1)-1:0] addra       , // write address
    input  wire [clogb2(RAM_DEPTH-1)-1:0] addrb       , // read address
    input  wire             [RAM_WIDTH-1:0] dina      , // write data
    input  wire                             clka       , // write clock
    input  wire                             clkb       , // read clock
    input  wire                             ena        , // write enable
    input  wire               [NUM_COL-1:0] wea       , // column write enable
    input  wire                             enb        , // read enable
    input  wire                             rstb       , // output reset (output register only)
    input  wire                             regceb     , // output register enable
    output wire             [RAM_WIDTH-1:0] doutb        // read data
);

    // DRC: design rule check
    initial begin
        if (NUM_COL*COL_WIDTH!=RAM_WIDTH) $fatal(1, "sdp_2clk requires NUM_COL*COL_WIDTH == RAM_WIDTH");
        if (RAM_DEPTH<=0) $fatal(1, "sdp_2clk requires RAM_DEPTH > 0");
    end

    /* verilator lint_off MULTIDRIVEN */
    reg [RAM_WIDTH-1:0] bram [RAM_DEPTH-1:0];
    /* verilator lint_on MULTIDRIVEN */

    reg [RAM_WIDTH-1:0] ram_data;

    generate
        if (INIT_FILE!="") begin: use_init_file
            initial $readmemh(INIT_FILE, bram, 0, RAM_DEPTH-1);
        end else begin: init_bram_to_zero
            integer ram_index;
            initial begin
                for (ram_index=0; ram_index<RAM_DEPTH; ram_index=ram_index+1) begin
                    bram[ram_index] = {RAM_WIDTH{1'b0}};
                end
            end
        end
    endgenerate

    integer i;
    always @(posedge clka) begin
        if (ena) begin
            for (i=0; i<NUM_COL; i=i+1) begin
                if (wea[i]) bram[addra][i*COL_WIDTH +: COL_WIDTH] <= dina[i*COL_WIDTH +: COL_WIDTH];
            end
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            ram_data <= bram[addrb];
        end
    end

    generate
        if (RAM_PERFORMANCE=="LOW_LATENCY") begin: no_output_register
            assign doutb = ram_data;
        end else begin: output_register
            reg [RAM_WIDTH-1:0] doutb_reg;
            always @(posedge clkb) begin
                if (rstb) begin
                    doutb_reg <= {RAM_WIDTH{1'b0}};
                end else if (regceb) begin
                    doutb_reg <= ram_data;
                end
            end
            assign doutb = doutb_reg;
        end
    endgenerate

    // address width calculation from RAM depth
    function integer clogb2;
        input integer depth;
        begin
            for (clogb2=0; depth>0; clogb2=clogb2+1) begin
                depth = depth >> 1;
            end
        end
    endfunction

    initial begin
        ram_data = {RAM_WIDTH{1'b0}};
    end

endmodule
/******************************************************************************************/

`resetall
