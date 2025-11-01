/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* instruction translation-lookaside buffer */
/******************************************************************************************/
module itlb #(
    parameter  TLB_ENTRIES      = 64                                , // the number of entries in the TLB
    localparam XLEN             = 32                                , // data width of register
    localparam VLEN             = (XLEN==32) ? 32 : 39              , // virtual address length
    localparam PLEN             = (XLEN==32) ? 34 : 56              , // physical address length
    localparam INDEX_WIDTH      = $clog2(TLB_ENTRIES)               , // index width
    localparam PG_OFFSET_WIDTH  = 12                                , // page offset width
    localparam VPN_WIDTH        = VLEN-PG_OFFSET_WIDTH-INDEX_WIDTH  , // virtual page number width
    localparam PPN_WIDTH        = PLEN-PG_OFFSET_WIDTH              , // physical page number width
    localparam PG_OFFSET_LSB    = 0                                 , // page offset least significant bit
    localparam PG_OFFSET_MSB    = PG_OFFSET_LSB+PG_OFFSET_WIDTH-1   , // page offset most significant bit
    localparam INDEX_LSB        = PG_OFFSET_MSB+1                   , // index least significant bit
    localparam INDEX_MSB        = INDEX_LSB+INDEX_WIDTH-1           , // index most significant bit
    localparam VPN_LSB          = INDEX_MSB+1                       , // virtual page number least significant bit
    localparam VPN_MSB          = VPN_LSB+VPN_WIDTH-1                 // virtual page number most significant bit
) (
    input  wire                 clk_i           , // clock
    input  wire                 rst_i           , // reset
    input  wire           [1:0] priv_lvl_i      , // privilege level
    input  wire                 flush_i         , // tlb flush
    input  wire      [VLEN-1:0] vaddr_i         , // virtual address
    output wire                 valid_o         , // tlb valid
    output wire                 page_fault_o    , // page fault
    output wire      [PLEN-1:0] paddr_o         , // physical address
    output wire [PPN_WIDTH-1:0] ppn_o           , // physical page number
    input  wire                 we_i            , // write enable
    input  wire           [0:0] lvl_i           , // page table entry level (write)
    input  wire      [XLEN-1:0] pte_i           , // page table entry (write)
    input  wire                 virtual_valid_i   // not baremetal
);

    // DRC: design rule check
    initial begin
        if ((TLB_ENTRIES > 512) || (TLB_ENTRIES < 1)) $fatal(1, "this itlb only supports 1-512-entry");
        if (XLEN!=32) $fatal(1, "this itlb only supports 32-bit XLEN");
    end
    integer i;

    (* ram_style = "block" *) reg    [VPN_WIDTH+XLEN:0] data_ram     [0:TLB_ENTRIES-1]   ; // {lvl, vpn, pte}

    reg  [TLB_ENTRIES:0]   valid_ram    ;
    wire                   valid, hit   ;
    wire [INDEX_WIDTH-1:0] ridx , widx  ;
    wire             [0:0] lvl          ;
    wire   [VPN_WIDTH-1:0] vpn          ;
    wire        [XLEN-1:0] pte          ;
    wire        [PLEN-1:0] paddr        ;
    wire                   page_fault   ;

    ///// itlb access
    ///// read
    assign ridx              = vaddr_i[INDEX_MSB:INDEX_LSB] ;
    assign widx              = vaddr_i[INDEX_MSB:INDEX_LSB] ;
    assign valid             = valid_ram[ridx]              ;
    assign {lvl, vpn, pte}   = data_ram[ridx]               ;

    reg  hit_q               ;
    reg  page_fault_q        ;
    reg  [PLEN-1:0] paddr_q  ;

    assign hit =  (!virtual_valid_i) || ((valid && (vaddr_i[31:22]==vpn[19-INDEX_WIDTH:10-INDEX_WIDTH]) && ((lvl=='h1) || (vaddr_i[21:12+INDEX_WIDTH]==vpn[9-INDEX_WIDTH:0]))));
    assign page_fault = virtual_valid_i && ((priv_lvl_i==`PRIV_LVL_U) && !pte[`PTE_U]) || ((priv_lvl_i==`PRIV_LVL_S) && pte[`PTE_U]) ;
    assign paddr = (virtual_valid_i) ? {pte[31:20], ((lvl=='h1) ? vaddr_i[21:12] : pte[19:10]), vaddr_i[11:0]}
                                    : vaddr_i ;
    assign ppn_o = (virtual_valid_i) ? {pte[31:20], ((lvl=='h1) ? vaddr_i[21:12] : pte[19:10])}
                                    : vaddr_i[`VLEN-1:PG_OFFSET_WIDTH] ;   

    always @(posedge clk_i) begin
        hit_q           <= hit            ;
        page_fault_q    <= page_fault     ;
        paddr_q         <= paddr          ;
    end

    assign valid_o      = hit_q             ;
    assign page_fault_o = page_fault_q      ;
    assign paddr_o      = paddr_q           ;

    always @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            valid_ram <= 'h0;
        end else begin
            if (we_i) begin
                data_ram[widx] <= {lvl_i, vaddr_i[VPN_MSB:VPN_LSB], pte_i} ;
                valid_ram[widx] <= 1'b1                                    ;
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall

