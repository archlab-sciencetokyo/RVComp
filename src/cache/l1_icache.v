/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* L1 instruction cache, DirectMap, PIPT */
/******************************************************************************************/
module l1_icache #(
    parameter  CACHE_SIZE   = 4096                                  , // cache size (byte)
    localparam XLEN         = 32                                    , // data width of register
    localparam VLEN         = (XLEN==32) ? 32 : 64                  , // virtual address length
    localparam PLEN         = (XLEN==32) ? 34 : 56                  , // physical address length
    localparam DATA_WIDTH   = 128                                   , // data width
    localparam STRB_WIDTH   = DATA_WIDTH/8                          , // strobe width (bytes)
    localparam OFFSET_WIDTH = $clog2(DATA_WIDTH/XLEN) + 2           , // offset width (2 bit + block offset)
    localparam INDEX_WIDTH  = $clog2(CACHE_SIZE) - OFFSET_WIDTH     , // index width
    localparam TAG_WIDTH    = PLEN-(INDEX_WIDTH+OFFSET_WIDTH)       , // tag width
    localparam OFFSET_LSB   = 0                                     , // offset least significant bit
    localparam OFFSET_MSB   = OFFSET_LSB+OFFSET_WIDTH-1             , // offset most significant bit
    localparam INDEX_LSB    = OFFSET_MSB+1                          , // index least significant bit
    localparam INDEX_MSB    = INDEX_LSB+INDEX_WIDTH-1               , // index most significant bit
    localparam TAG_LSB      = INDEX_MSB+1                           , // tag least significant bit
    localparam TAG_MSB      = TAG_LSB+TAG_WIDTH-1                   , // tag most significant bit
    localparam PG_OFFSET_WIDTH = 12                                 , // page offset width
    localparam PPN_WIDTH    = PLEN-PG_OFFSET_WIDTH                    // physical page number width
) (
    input  wire                  clk_i           , // clock
    input  wire       [PLEN-1:0] invalid_paddr_i , // invalidate physical address
    input  wire                  invalid_valid_i , // invalidate valid
    input  wire       [VLEN-1:0] vaddr_i         , // virtual address
    input  wire       [PLEN-1:0] paddr_i         , // physical address
    input  wire  [PPN_WIDTH-1:0] ppn_i           , // physical page number
    output reg                   hit_o           , // hit or miss
    output wire [DATA_WIDTH-1:0] rdata_o         , // read data
    input  wire                  we_i            , // write enable
    input  wire [DATA_WIDTH-1:0] wdata_i           // write data
);
    ///// DRC: design rule check
    initial begin
        if (CACHE_SIZE < 8192) $fatal(1, "this L1 instruction cache only supports 8192 ");
    end
    integer i;
    ///// meta_ram: {valid, tag}
    (* ram_style = "block" *) reg     [TAG_WIDTH:0] meta_ram [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram [0:2**INDEX_WIDTH-1]  ;

    ///// cache access
    wire [INDEX_WIDTH-1:0] rwidx_instr   = {ppn_i[INDEX_MSB-PG_OFFSET_WIDTH:0], vaddr_i[PG_OFFSET_WIDTH-1:INDEX_LSB]} ; // read data
    wire [INDEX_WIDTH-1:0] rwidx_check   = invalid_paddr_i[INDEX_MSB:INDEX_LSB]                                       ; // read data

    reg [TAG_WIDTH:0]     meta_reg_instr;
    reg [DATA_WIDTH-1:0]  data_reg_instr;
    always @(posedge clk_i) begin
        meta_reg_instr <= meta_ram[rwidx_instr]  ;
        data_reg_instr <= data_ram[rwidx_instr]  ;
        if (we_i && !invalidate_we_q) begin
            meta_ram[rwidx_instr] <= {1'b1, paddr_i[TAG_MSB:TAG_LSB]} ;
            data_ram[rwidx_instr] <= wdata_i ;
        end
    end

    ///// cache invalidate
    reg   invalidate_we_q ;      
    wire  invalidate_we = (invalid_valid_i) && (rtag_check==invalid_paddr_i[TAG_MSB:TAG_LSB]) ;
    always @(posedge clk_i) begin
        invalidate_we_q    <= invalidate_we   ;
    end

    reg [TAG_WIDTH:0]     meta_reg_check;
    always @(posedge clk_i) begin
        meta_reg_check <= meta_ram[rwidx_check]   ;
        if (invalidate_we_q) begin
            meta_ram[rwidx_check] <= {1'b0, rtag_check} ;
        end
    end

    wire                     rvalid_instr, rvalid_check ;
    wire     [TAG_WIDTH-1:0] rtag_instr  , rtag_check  ;
    wire    [DATA_WIDTH-1:0] rdata_instr  ;
    assign {rvalid_instr, rtag_instr} =  meta_reg_instr ;
    assign {rvalid_check, rtag_check} =  meta_reg_check ;
    assign rdata_instr                =  data_reg_instr ;
    assign rdata_o = rdata_instr ;

    always @(posedge clk_i) begin
        hit_o <= rvalid_instr && (paddr_i[TAG_MSB:TAG_LSB]==rtag_instr) ;
    end

endmodule
/******************************************************************************************/

`resetall
