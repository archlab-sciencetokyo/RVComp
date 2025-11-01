/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* L1 data cache, DirectMap, PIPT */
/******************************************************************************************/
module l1_dcache #(
    parameter  CACHE_SIZE   = 4096                                  , // cache size (bytes)
    localparam XLEN         = 32                                    , // data width of register
    localparam VLEN         = (XLEN==32) ? 32 : 64                  , // virtual address length
    localparam PLEN         = (XLEN==32) ? 34 : 56                  , // physical address length
    localparam DATA_WIDTH   = 128                                   , // data width of cache
    localparam STRB_WIDTH   = DATA_WIDTH/8                          , // strobe width
    localparam OFFSET_WIDTH = $clog2(DATA_WIDTH/8)                  , // offset width
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
    input  wire                  clk_i          , // clock
    input  wire       [VLEN-1:0] data_vaddr_i   , // virtual address
    input  wire       [PLEN-1:0] data_paddr_i   , // physical address
    input  wire  [PPN_WIDTH-1:0] data_ppn_i     , // physical page number
    output reg                   data_hit_o     , // hit or miss
    output wire       [XLEN-1:0] data_rdata_o   , // read data
    output wire                  data_rvalid_o  , // read valid
    output wire                  data_rdirty_o  , // read dirty
    input  wire       [PLEN-1:0] load_addr_i    , // load address
    input  wire                  wback_clean_i  , // clean dirty
    output wire                  wback_dirty_o  , // cache dirty
    output wire                  wback_valid_o  , // cache valid
    output wire       [PLEN-1:0] wback_addr_o   , // write back address
    output wire [DATA_WIDTH-1:0] wback_data_o   , // write back data
    input  wire                  we_i           , // write enable
    input  wire [DATA_WIDTH-1:0] wdata_i        , // write data
    input  wire [STRB_WIDTH-1:0] wstrb_i        , // write strobe
    input  wire                  wdirty_i         // write dirty
);
    ///// DRC: design rule check
    integer i;
    initial begin
        if (CACHE_SIZE <= 4096) $fatal(1, "this L1 data cache only supports greater than 4096 bytes");
    end
    ///// meta_ram: {valid, tag}
    (* ram_style = "block" *) reg   [TAG_WIDTH+1:0] meta_ram [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram [0:2**INDEX_WIDTH-1]  ;
    ///// cache access
    wire    [INDEX_WIDTH-1:0] rwidx_data = {data_ppn_i[INDEX_MSB-PG_OFFSET_WIDTH:0], data_vaddr_i[PG_OFFSET_WIDTH-1:INDEX_LSB]}; // read data
    always @(posedge clk_i) begin
        meta_reg_data <= meta_ram[rwidx_data]   ;
        rdata_reg_data <= data_ram[rwidx_data]  ;
        if (we_i) begin
            meta_ram[rwidx_data] <= {1'b1, wdirty_i, data_paddr_i[TAG_MSB:TAG_LSB]} ;
            for (i=0;i<STRB_WIDTH;i=i+1) begin
                if (wstrb_i[i]) data_ram[rwidx_data][8*i+:8] <= wdata_i[8*i+:8] ;
            end
        end
    end
    wire    [INDEX_WIDTH-1:0] rwidx_wback = load_addr_i[INDEX_MSB:INDEX_LSB] ; // write back add
    reg     [TAG_WIDTH+1:0]  meta_reg_data , meta_reg_wback ;
    reg     [DATA_WIDTH-1:0] rdata_reg_data, rdata_reg_wback ;

    always @(posedge clk_i) begin
        rdata_reg_wback <= data_ram[rwidx_wback] ;
        meta_reg_wback <= meta_ram[rwidx_wback]  ;
        if (!we_i && wback_clean_i) begin
            meta_ram[rwidx_wback] <= {rvalid_wback, 1'b0, rtag_wback}                       ;
        end 
    end
    
    wire                       rvalid_data, rvalid_wback ;
    wire                       rdirty_data, rdirty_wback ;
    wire       [TAG_WIDTH-1:0] rtag_data  , rtag_wback   ;
    wire      [DATA_WIDTH-1:0] rdata_data , rdata_wback  ;
    assign {rvalid_data , rdirty_data , rtag_data } =  meta_reg_data  ;
    assign {rvalid_wback, rdirty_wback, rtag_wback} =  meta_reg_wback ;
    assign rdata_data                  =  rdata_reg_data ;
    assign rdata_wback                 =  rdata_reg_wback ;
    always @(posedge clk_i) begin
        data_hit_o  <= (rvalid_data && (data_paddr_i[TAG_MSB:TAG_LSB]==rtag_data)) ;
    end
    assign data_rdata_o = (data_vaddr_i[3:2]==3) ? rdata_data[127:96] :
                          (data_vaddr_i[3:2]==2) ? rdata_data[95:64] :
                          (data_vaddr_i[3:2]==1) ? rdata_data[63:32] :rdata_data[31:0];
    assign data_rvalid_o = rvalid_data;
    assign data_rdirty_o = rdirty_data;
    
    assign wback_data_o  = rdata_wback                   ;
    assign wback_valid_o = rvalid_wback                  ;
    assign wback_dirty_o = rdirty_wback                  ;
    assign wback_addr_o  = {rtag_wback, load_addr_i[INDEX_MSB:0]} ;

endmodule

/******************************************************************************************/
`resetall
