/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* page-table walker */
/******************************************************************************************/
module ptw (
    input  wire                  clk_i           , // clock
    input  wire                  rst_i           , // reset
    input  wire            [1:0] priv_lvl_i      , // privilege level
    input  wire      [`XLEN-1:0] satp_i          , // supervisor address translation and protection
    input  wire                  mxr_i           , // make executable readable
    input  wire                  sum_i           , // permit supervisor user memory access
    input  wire                  mprv_i          , // modify privilege
    input  wire            [1:0] mpp_i           , // machine previous privilege
    input  wire                  valid_i         , // page table walk request valid
    input  wire                  is_fetch_i      , // is fetch
    input  wire                  is_load_i       , // is load
    input  wire                  is_store_i      , // is store
    input  wire      [`VLEN-1:0] vaddr_i         , // virtual address
    output wire                  pte_arvalid_o   , // read pte request valid
    output wire      [`PLEN-1:0] pte_araddr_o    , // read pte request address
    input  wire                  pte_rvalid_i    , // read pte response valid
    input  wire      [`XLEN-1:0] pte_i           , // read pte response data
    output wire                  valid_o         , // page table walk response valid
    output wire                  page_fault_o    , // page fault
    output wire [`PPN_WIDTH-1:0] ppn_o           , // physical page number
    output wire      [`PLEN-1:0] paddr_o         , // physical address
    output wire            [0:0] ptw_lvl_o         // page table walk level
);

    localparam IDLE = 1'd0, PTE_LOOKUP = 1'd1;
    reg  [0:0] state_q  , state_d   ;

    reg        [0:0] ptw_lvl_q      , ptw_lvl_d     ;
    reg              is_fetch_q     , is_fetch_d    ;
    reg              is_load_q      , is_load_d     ;
    reg              is_store_q     , is_store_d    ;
    reg  [`VLEN-1:0] vaddr_q        , vaddr_d       ;
    reg              pte_arvalid_q  , pte_arvalid_d ;
    reg  [`PLEN-1:0] pte_araddr_q   , pte_araddr_d  ;
    reg              valid_q        , valid_d       ;
    reg              page_fault_q   , page_fault_d  ;
    reg  [`PLEN-1:0] paddr_q        , paddr_d       ;

    assign pte_arvalid_o    = pte_arvalid_q         ;
    assign pte_araddr_o     = pte_araddr_q          ;
    assign valid_o          = valid_q               ;
    assign paddr_o          = paddr_q               ;
    assign page_fault_o     = page_fault_q          ;
    assign ptw_lvl_o        = ptw_lvl_q             ;
    assign ppn_o            = paddr_d[`PLEN-1:`PG_OFFSET_WIDTH] ;
    always @(*) begin
        ptw_lvl_d       = ptw_lvl_q     ;
        is_fetch_d      = is_fetch_q    ;
        is_load_d       = is_load_q     ;
        is_store_d      = is_store_q    ;
        vaddr_d         = vaddr_q       ;
        pte_arvalid_d   = 1'b0          ;
        pte_araddr_d    = pte_araddr_q  ;
        valid_d         = 1'b0          ;
        page_fault_d    = 1'b0          ;
        paddr_d         = 'h0           ;
        state_d         = state_q       ;
        case (state_q)
            IDLE        : begin
                if (valid_i) begin // L1 PTE access
                    ptw_lvl_d       = 'h1                                   ;
                    is_fetch_d      = is_fetch_i                            ;
                    is_load_d       = is_load_i                             ;
                    is_store_d      = is_store_i                            ;
                    vaddr_d         = vaddr_i                               ;
                    pte_arvalid_d   = 1'b1                                  ;
                    pte_araddr_d    = {satp_i[21:0], vaddr_i[31:22], 2'b00} ;
                    state_d         = PTE_LOOKUP                            ;
                end
            end
            PTE_LOOKUP  : begin
                if (pte_rvalid_i) begin
                    if (!pte_i[`PTE_V] || (!pte_i[`PTE_R] && pte_i[`PTE_W])) begin // invalid PTE
                        valid_d         = 1'b1          ;
                        page_fault_d    = 1'b1          ;
                        state_d         = IDLE          ;
                    end else begin // valid PTE
                        if (pte_i[`PTE_R] || pte_i[`PTE_X]) begin // leaf PTE
                            valid_d         = 1'b1      ;
                            paddr_d         = {pte_i[31:20], ((ptw_lvl_q=='h1) ? vaddr_q[21:12] : pte_i[19:10]), vaddr_q[11:0]}; // if ptw_lvl_q=='h1, then this is a superpage translation
                            if (!pte_i[`PTE_A]) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if (is_fetch_q && !pte_i[`PTE_X]) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if (is_load_q && !pte_i[`PTE_R] && !(pte_i[`PTE_X] && mxr_i)) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if (is_store_q && (!pte_i[`PTE_W] || !pte_i[`PTE_D])) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if (((((is_load_q || is_store_q) && mprv_i) ? mpp_i : priv_lvl_i)==`PRIV_LVL_U) && !pte_i[`PTE_U]) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if (((((is_load_q || is_store_q) && mprv_i) ? mpp_i : priv_lvl_i)==`PRIV_LVL_S) &&  pte_i[`PTE_U] && !((is_load_q || is_store_q) && sum_i)) begin
                                page_fault_d    = 1'b1  ;
                            end
                            if ((ptw_lvl_q=='h1) && (pte_i[19:10]!=0)) begin // this is a misaligned superpage
                                page_fault_d    = 1'b1  ;
                            end
                            state_d         = IDLE  ;
                        end else begin // pointer to next level of page table
                            if (ptw_lvl_q=='h0) begin // invalid pointer
                                valid_d         = 1'b1                                  ;
                                page_fault_d    = 1'b1                                  ;
                                state_d         = IDLE                                  ;
                            end else begin // L0 PTE access
                                ptw_lvl_d       = 'h0                                   ;
                                pte_arvalid_d   = 1'b1                                  ;
                                pte_araddr_d    = {pte_i[31:10], vaddr_q[21:12], 2'b00} ;
                            end
                        end
                    end
                end
            end
            default     : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            pte_arvalid_q   <= 1'b0             ;
            valid_q         <= 1'b0             ;
            state_q         <= IDLE             ;
        end else begin
            ptw_lvl_q       <= ptw_lvl_d        ;
            is_fetch_q      <= is_fetch_d       ;
            is_load_q       <= is_load_d        ;
            is_store_q      <= is_store_d       ;
            vaddr_q         <= vaddr_d          ;
            pte_arvalid_q   <= pte_arvalid_d    ;
            pte_araddr_q    <= pte_araddr_d     ;
            valid_q         <= valid_d          ;
            page_fault_q    <= page_fault_d     ;
            paddr_q         <= paddr_d          ;
            state_q         <= state_d          ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
