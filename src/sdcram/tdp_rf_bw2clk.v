/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* True Dual Port RAM (Read First, Byte Write, 2 Clock) */
/******************************************************************************************/
module tdp_rf_bw2clk #(
    parameter  NB_COL           = 4                 , // number of columns (bytes)
    parameter  COL_WIDTH        = 8                 , // column width (bits per byte)
    parameter  RAM_DEPTH        = 1024              , // ram depth (number of entries)
    parameter  RAM_PERFORMANCE  = "LOW_LATENCY"     , // "HIGH_PERFORMANCE" or "LOW_LATENCY"
    parameter  INIT_FILE        = ""                , // initialization file path
    localparam DATA_WIDTH       = NB_COL * COL_WIDTH, // total data width
    localparam ADDR_WIDTH       = $clog2(RAM_DEPTH)   // address width
) (
    input  wire                     clka_i          , // port A clock
    input  wire                     clkb_i          , // port B clock
    input  wire                     rsta_i          , // port A reset (used only for output register)
    input  wire                     rstb_i          , // port B reset (used only for output register)
    input  wire                     ena_i           , // port A enable
    input  wire                     enb_i           , // port B enable
    input  wire       [NB_COL-1:0]  wea_i           , // port A write enable (per byte)
    input  wire       [NB_COL-1:0]  web_i           , // port B write enable (per byte)
    input  wire   [ADDR_WIDTH-1:0]  addra_i         , // port A address
    input  wire   [ADDR_WIDTH-1:0]  addrb_i         , // port B address
    input  wire   [DATA_WIDTH-1:0]  dina_i          , // port A write data
    input  wire   [DATA_WIDTH-1:0]  dinb_i          , // port B write data
    output wire   [DATA_WIDTH-1:0]  douta_o         , // port A read data
    output wire   [DATA_WIDTH-1:0]  doutb_o           // port B read data
);

    ///// DRC: design rule check
    initial begin
        if (NB_COL==0)      $fatal(1, "NB_COL must be greater than 0");
        if (COL_WIDTH==0)   $fatal(1, "COL_WIDTH must be greater than 0");
        if (RAM_DEPTH==0)   $fatal(1, "RAM_DEPTH must be greater than 0");
        if (RAM_PERFORMANCE != "LOW_LATENCY" && RAM_PERFORMANCE != "HIGH_PERFORMANCE")
            $fatal(1, "RAM_PERFORMANCE must be either LOW_LATENCY or HIGH_PERFORMANCE");
    end

//==============================================================================
// RAM storage and intermediate registers
//------------------------------------------------------------------------------
/* verilator lint_off MULTIDRIVEN */
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:RAM_DEPTH-1]         ;
/* verilator lint_on MULTIDRIVEN */
    reg [DATA_WIDTH-1:0] ram_data_a_q   = {DATA_WIDTH{1'b0}}                   ;
    reg [DATA_WIDTH-1:0] ram_data_b_q   = {DATA_WIDTH{1'b0}}                   ;

//==============================================================================
// Initialization
//------------------------------------------------------------------------------
    generate
        if (INIT_FILE != "") begin: use_init_file
            initial $readmemh(INIT_FILE, ram, 0, RAM_DEPTH-1);
        end else begin: init_bram_to_zero
            integer i;
            initial begin
                for (i = 0; i < RAM_DEPTH; i = i + 1) begin
                    ram[i] = {DATA_WIDTH{1'b0}};
                end
            end
        end
    endgenerate

//==============================================================================
// Port A: Read and Write logic
//------------------------------------------------------------------------------
    ///// port A read
    always @(posedge clka_i) begin
        if (ena_i) begin
            ram_data_a_q <= ram[addra_i];
        end
    end

    ///// port A byte-wise write
    generate
        genvar i;
        for (i = 0; i < NB_COL; i = i + 1) begin: byte_write_a
            always @(posedge clka_i) begin
                if (ena_i && wea_i[i]) begin
                    ram[addra_i][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= dina_i[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
                end
            end
        end
    endgenerate

//==============================================================================
// Port B: Read and Write logic
//------------------------------------------------------------------------------
    ///// port B read
    always @(posedge clkb_i) begin
        if (enb_i) begin
            ram_data_b_q <= ram[addrb_i];
        end
    end

    ///// port B byte-wise write
    generate
        genvar j;
        for (j = 0; j < NB_COL; j = j + 1) begin: byte_write_b
            always @(posedge clkb_i) begin
                if (enb_i && web_i[j]) begin
                    ram[addrb_i][(j+1)*COL_WIDTH-1:j*COL_WIDTH] <= dinb_i[(j+1)*COL_WIDTH-1:j*COL_WIDTH];
                end
            end
        end
    endgenerate

//==============================================================================
// Output register (optional)
//------------------------------------------------------------------------------
    generate
        if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register
            ///// direct output (1 cycle latency)
            assign douta_o = ram_data_a_q;
            assign doutb_o = ram_data_b_q;
        end else begin: output_register
            ///// additional output register (2 cycle latency, better timing)
            reg [DATA_WIDTH-1:0] douta_q = {DATA_WIDTH{1'b0}}  ;
            reg [DATA_WIDTH-1:0] doutb_q = {DATA_WIDTH{1'b0}}  ;

            always @(posedge clka_i) begin
                if (rsta_i) begin
                    douta_q <= {DATA_WIDTH{1'b0}}  ;
                end else begin
                    douta_q <= ram_data_a_q        ;
                end
            end

            always @(posedge clkb_i) begin
                if (rstb_i) begin
                    doutb_q <= {DATA_WIDTH{1'b0}}  ;
                end else begin
                    doutb_q <= ram_data_b_q        ;
                end
            end

            assign douta_o = douta_q;
            assign doutb_o = doutb_q;
        end
    endgenerate

endmodule
/******************************************************************************************/

`resetall
