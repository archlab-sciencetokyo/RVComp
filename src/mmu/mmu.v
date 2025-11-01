/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* memory management unit */
/******************************************************************************************/
module mmu (
    input  wire                         clk_i               , // clock
    input  wire                         rst_i               , // reset
    // cpu - mmu
    input  wire                   [1:0] priv_lvl_i          , // privilege level
    input  wire             [`XLEN-1:0] satp_i              , // satp register value
    input  wire                         mxr_i               , // Make eXecutable Readable
    input  wire                         sum_i               , // permit Supervisor User Memory access
    input  wire                         mprv_i              , // Modify PRiVilege
    input  wire                   [1:0] mpp_i               , // Machine Previous Privilege
    input  wire                         flush_tlb_i         , // flush tlb
    input  wire                         ibus_arvalid_i      , // fetch request valid
    output wire                         ibus_arready_o      , // fetch request ready
    input  wire  [`IBUS_ADDR_WIDTH-1:0] ibus_araddr_i       , // fetch request address
    output wire                         ibus_rvalid_o       , // fetch response valid
    input  wire                         ibus_rready_i       , // fetch response ready
    output wire  [`IBUS_DATA_WIDTH-1:0] ibus_rdata_o        , // fetch response data
    output wire      [`RRESP_WIDTH-1:0] ibus_rresp_o        , // fetch response status
    input  wire  [`DBUS_ADDR_WIDTH-1:0] dbus_axaddr_i       , // load/store request address
    input  wire                         dbus_wvalid_i       , // store request valid
    output wire                         dbus_wready_o       , // store request ready
    input  wire                         dbus_awlock_i       , // is store conditional
    input  wire  [`DBUS_DATA_WIDTH-1:0] dbus_wdata_i        , // store request data
    input  wire  [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_i        , // store request strb
    output wire                         dbus_bvalid_o       , // store response valid
    input  wire                         dbus_bready_i       , // store response ready
    output wire      [`BRESP_WIDTH-1:0] dbus_bresp_o        , // store response status
    input  wire                         dbus_arvalid_i      , // load request valid
    output wire                         dbus_arready_o      , // load request ready
    input  wire                         dbus_arlock_i       , // is load reserved
    input  wire                         dbus_aramo_i        , // is amo
    output wire                         dbus_rvalid_o       , // load response valid
    input  wire                         dbus_rready_i       , // load response ready
    output wire  [`DBUS_DATA_WIDTH-1:0] dbus_rdata_o        , // load response data
    output wire      [`RRESP_WIDTH-1:0] dbus_rresp_o        , // load response status
    // mmu - L2$
    output wire                         bus_wvalid_o        , // store request valid
    input  wire                         bus_wready_i        , // store request ready
    output wire   [`BUS_ADDR_WIDTH-1:0] bus_awaddr_o        , // store request address
    output wire   [`BUS_DATA_WIDTH-1:0] bus_wdata_o         , // store request data
    output wire   [`BUS_STRB_WIDTH-1:0] bus_wstrb_o         , // store request strobe
    input  wire                         bus_bvalid_i        , // store response valid
    output wire                         bus_bready_o        , // store response ready
    input  wire      [`BRESP_WIDTH-1:0] bus_bresp_i         , // store response status
    output wire                         bus_arvalid_o       , // read request valid
    input  wire                         bus_arready_i       , // read request ready
    output wire   [`BUS_ADDR_WIDTH-1:0] bus_araddr_o        , // read request address
    input  wire                         bus_rvalid_i        , // read response valid
    output wire                         bus_rready_o        , // read response ready
    input  wire   [`BUS_DATA_WIDTH-1:0] bus_rdata_i         , // read response data
    input  wire      [`RRESP_WIDTH-1:0] bus_rresp_i           // read response status
);

    wire                 [0:0] ptw_lvl                                      ;

    // instruction cache/tlb
    reg            [`VLEN-1:0] instr_vaddr_q        , instr_vaddr_d         ;
    reg            [`PLEN-1:0] instr_paddr_q        , instr_paddr_d         ;
    reg                        fetch_ptw_pending_q  , fetch_ptw_pending_d   ;
    reg                        fetch_pending_q      , fetch_pending_d       ;

    wire                       itlb_valid                                   ;
    wire                       itlb_page_fault                              ;
    wire           [`PLEN-1:0] itlb_paddr                                   ;
    wire      [`PPN_WIDTH-1:0] itlb_ppn                                     ;
    wire                       itlb_we                                      ;
    wire  itlb_vvalid = ((priv_lvl_i<=`PRIV_LVL_S) && satp_i[31]);
    itlb #(
        .TLB_ENTRIES        (`ITLB_ENTRIES)       // itlb-entry
    ) itlb (
        .clk_i              (clk_i              ), // input  wire
        .rst_i              (rst_i              ), // input  wire
        .priv_lvl_i         (priv_lvl_i         ), // input  wire      [1:0]
        .flush_i            (flush_tlb_i        ), // input  wire
        .vaddr_i            (ibus_araddr_i      ), // input  wire [VLEN-1:0] // NOTE: use instr_vaddr_d
        .valid_o            (itlb_valid         ), // output wire
        .page_fault_o       (itlb_page_fault    ), // output wire
        .paddr_o            (itlb_paddr         ), // output wire [PLEN-1:0]
        .ppn_o              (itlb_ppn           ), // output wire [PPN_WIDTH-1:0]
        .we_i               (itlb_we            ), // input  wire
        .virtual_valid_i    (itlb_vvalid        ), // input  wire
        .lvl_i              (ptw_lvl            ), // input  wire      [0:0]
        .pte_i              (pte_rdata_q        )  // input  wire [XLEN-1:0]
    );

    wire                       icache_hit                                   ;
    wire [`BUS_DATA_WIDTH-1:0] icache_rdata                                 ;
    reg                        icache_we_q          , icache_we_d           ;
    reg                        icache_invalidate_q  , icache_invalidate_d  ;
    reg  [`BUS_DATA_WIDTH-1:0] icache_wdata_q       , icache_wdata_d        ;   
    wire [`PPN_WIDTH-1:0] icache_ppn   = (istate_q==I_PTW ) ? ptw_ppn : itlb_ppn ;
    l1_icache #(
        .CACHE_SIZE         (`L1_ICACHE_SIZE)     // cache-size 
    ) l1_icache (
        .clk_i              (clk_i              ), // input  wire
        .invalid_paddr_i    (data_paddr_d       ), // input  wire       [PLEN-1:0]
        .invalid_valid_i    (icache_invalidate_q), // input  wire
        .ppn_i              (icache_ppn         ), // input  wire  [PPN_WIDTH-1:0]
        .vaddr_i            (instr_vaddr_d      ), // input  wire       [VLEN-1:0] // NOTE: use instr_vaddr_d
        .paddr_i            (instr_paddr_d      ), // input  wire       [PLEN-1:0]
        .hit_o              (icache_hit         ), // output wire
        .rdata_o            (icache_rdata       ), // output wire [DATA_WIDTH-1:0]
        .we_i               (icache_we_q        ), // input  wire
        .wdata_i            (icache_wdata_q     )  // input  wire [DATA_WIDTH-1:0]
    );

    // data cache/tlb
    reg                        is_store_q           , is_store_d            ;
    reg                        is_amo_q             , is_amo_d              ;
    reg            [`VLEN-1:0] data_vaddr_q         , data_vaddr_d          ;
    reg            [`PLEN-1:0] data_paddr_q         , data_paddr_d          ;
    reg                        store_ptw_pending_q  , store_ptw_pending_d   ;
    reg                        store_pending_q      , store_pending_d       ;
    reg                        load_ptw_pending_q   , load_ptw_pending_d    ;
    reg                        load_pending_q       , load_pending_d        ;

    wire data_periph_access = ((data_paddr_q[`PLEN-1:24]>'h0) && (data_paddr_q[`PLEN-1:28]<'h8));

    reg                        dtlb_ptw_req_q       , dtlb_ptw_req_d        ;
    wire           [`VLEN-1:0] dtlb_vaddr                                   ;
    wire                       dtlb_valid                                   ;
    wire                       dtlb_page_fault                              ;
    wire           [`PLEN-1:0] dtlb_paddr                                   ;
    wire                       dtlb_we                                      ;
    wire      [`PPN_WIDTH-1:0] dtlb_ppn                                     ;
    wire                       dtlb_vvalid = ((((mprv_i) ? mpp_i : priv_lvl_i)<=`PRIV_LVL_S)&& satp_i[31]);
    dtlb #(
        .TLB_ENTRIES        (`DTLB_ENTRIES)       // dtlb-entry
    ) dtlb (
        .clk_i              (clk_i                  ), // input  wire
        .rst_i              (rst_i                  ), // input  wire
        .priv_lvl_i         (priv_lvl_i             ), // input  wire      [1:0]
        .sum_i              (sum_i                  ), // input  wire
        .mprv_i             (mprv_i                 ), // input  wire
        .mpp_i              (mpp_i                  ), // input  wire      [1:0]
        .flush_i            (flush_tlb_i            ), // input  wire
        .is_store_i         (is_store_d || is_amo_d ), // input  wire            // NOTE: use is_store_d
        .vaddr_i            (dbus_axaddr_i          ), // input  wire [VLEN-1:0] // NOTE: use dbus_axaddr_i
        .valid_o            (dtlb_valid             ), // output wire
        .page_fault_o       (dtlb_page_fault        ), // output wire
        .paddr_o            (dtlb_paddr             ), // output wire [PLEN-1:0]
        .ppn_o              (dtlb_ppn               ), // output wire [PPN_WIDTH-1:0]
        .virtual_valid_i    (dtlb_vvalid            ), // input  wire
        .we_i               (dtlb_we                ), // input  wire
        .lvl_i              (ptw_lvl                ), // input  wire      [0:0]
        .pte_i              (pte_rdata_q            ) // input  wire [XLEN-1:0]
    );

    wire                       dcache_hit , dcache_rvalid, dcache_rdirty    ;
    wire                       dcache_wback_rvalid, dcache_wback_rdirty     ;
    wire [`XLEN-1:0]           dcache_rdata                                 ;
    wire [`PLEN-1:0]           dcache_wback_addr                            ;
    wire [`BUS_DATA_WIDTH-1:0] dcache_wback_data                            ;
    wire [`PPN_WIDTH-1:0]      dcache_ppn = (dstate_q==D_PTW) ? ptw_ppn : dtlb_ppn;
    reg  [`PLEN-1:0]           load_addr_q          , load_addr_d           ;
    reg                        dcache_we_q          , dcache_we_d           ;
    reg  [`BUS_DATA_WIDTH-1:0] dcache_wdata_q       , dcache_wdata_d        ;
    reg  [`BUS_STRB_WIDTH-1:0] dcache_wstrb_q       , dcache_wstrb_d        ;
    reg                        dcache_wdirty_q      , dcache_wdirty_d       ;
    reg                        dcache_wbstored_q    , dcache_wbstored_d     ; // check stored while writeback
    reg                                               dcache_wbclean_d      ;
    localparam  DCACHE_INDEX_LSB = $clog2(`BUS_DATA_WIDTH/8)                     ;
    localparam  DCACHE_INDEX_MSB = DCACHE_INDEX_LSB + $clog2(`L1_DCACHE_SIZE) - $clog2(`BUS_DATA_WIDTH/8) - 1;
    wire dcache_store_inwb = (dcache_we_q && load_addr_d[DCACHE_INDEX_MSB:DCACHE_INDEX_LSB]==data_paddr_q[DCACHE_INDEX_MSB:DCACHE_INDEX_LSB]) ? 1'b1 : 1'b0;
    l1_dcache #(
        .CACHE_SIZE              (`L1_DCACHE_SIZE    )     // cache-size
    ) l1_dcache (
        .clk_i                   (clk_i              ), // input 
        .data_vaddr_i            (data_vaddr_d       ), // input  wire       [VLEN-1:0] // NOTE: use data_vaddr_d
        .data_paddr_i            (data_paddr_d       ), // input  wire       [PLEN-1:0] // NOTE: use data_paddr_d
        .data_ppn_i              (dcache_ppn         ), // input  wire [PPN_WIDTH-1:0]
        .data_hit_o              (dcache_hit         ), // output wire
        .data_rdata_o            (dcache_rdata       ), // output wire [DATA_WIDTH-1:0]
        .data_rvalid_o           (dcache_rvalid      ), // output wire 
        .data_rdirty_o           (dcache_rdirty      ), // output wire
        .load_addr_i             (load_addr_d        ), // input  wire       [PLEN-1:0]
        .wback_clean_i           (dcache_wbclean_d   ), // input  wire
        .wback_dirty_o           (dcache_wback_rdirty), // output wire
        .wback_valid_o           (dcache_wback_rvalid), // output wire
        .wback_addr_o            (dcache_wback_addr  ), // output wire [PLEN-1:0]
        .wback_data_o            (dcache_wback_data  ), // output wire [BUS_DATA_WIDTH-1:0]
        .we_i                    (dcache_we_q        ), // input  wire
        .wdata_i                 (dcache_wdata_q     ), // input  wire [DATA_WIDTH-1:0]
        .wstrb_i                 (dcache_wstrb_q     ), // input  wire [STRB_WIDTH-1:0]
        .wdirty_i                (dcache_wdirty_q    )  // input  wire 
    );

    // page-table walker
    reg                        ptw_req_q            , ptw_req_d             ;
    reg                        fetch_req_q          , fetch_req_d           ;
    reg                        store_req_q          , store_req_d           ;
    reg                        load_req_q           , load_req_d            ;
    reg            [`VLEN-1:0] vaddr_q              , vaddr_d               ;
    wire                       pte_arvalid                                  ;
    wire           [`PLEN-1:0] pte_araddr                                   ;
    reg                        pte_rvalid_q         , pte_rvalid_d          ;
    reg            [`XLEN-1:0] pte_rdata_q          , pte_rdata_d           ;
    wire                       ptw_resp_v                                   ;
    wire                       page_fault                                   ;
    wire           [`PLEN-1:0] paddr                                        ;
    wire      [`PPN_WIDTH-1:0] ptw_ppn                                      ;
    ptw ptw (
        .clk_i              (clk_i              ), // input  wire
        .rst_i              (rst_i              ), // input  wire
        .priv_lvl_i         (priv_lvl_i         ), // input  wire       [1:0]
        .satp_i             (satp_i             ), // input  wire [`XLEN-1:0]
        .mxr_i              (mxr_i              ), // input  wire
        .sum_i              (sum_i              ), // input  wire
        .mprv_i             (mprv_i             ), // input  wire
        .mpp_i              (mpp_i              ), // input  wire       [1:0]
        .valid_i            (ptw_req_q          ), // input  wire
        .is_fetch_i         (fetch_req_q        ), // input  wire
        .is_load_i          (load_req_q         ), // input  wire
        .is_store_i         (store_req_q        ), // input  wire
        .vaddr_i            (vaddr_q            ), // input  wire [`VLEN-1:0]
        .pte_arvalid_o      (pte_arvalid        ), // output wire
        .pte_araddr_o       (pte_araddr         ), // output wire [`PLEN-1:0]
        .pte_rvalid_i       (pte_rvalid_q       ), // input  wire
        .pte_i              (pte_rdata_q        ), // input  wire [`XLEN-1:0]
        .valid_o            (ptw_resp_v         ), // output wire
        .page_fault_o       (page_fault         ), // output wire
        .paddr_o            (paddr              ), // output wire
        .ppn_o              (ptw_ppn            ), // output wire [`PPN_WIDTH-1:0]
        .ptw_lvl_o          (ptw_lvl            )  // output wire       [0:0]
    );

    assign itlb_we  = ptw_resp_v && !page_fault && fetch_req_q                  ;
    assign dtlb_we  = ptw_resp_v && !page_fault && (load_req_q || store_req_q)  ;

    // instruction cache/tlb state
    localparam I_IDLE = 'd0, I_TLB = 'd1, I_CACHE = 'd2, I_PTW = 'd3, I_FETCH = 'd4, I_RET = 'd5;
    reg  [2:0] istate_q , istate_d  ;
    // data cache/tlb state
    localparam  D_IDLE     = 'd0, D_TLB = 'd1, D_CACHE = 'd2, D_PTW    = 'd3,
                D_STORE    = 'd4, D_RET = 'd5, D_CHECK = 'd6, D_PERIPH = 'd7,
                D_ALLOCATE = 'd8; 
    reg  [3:0] dstate_q , dstate_d  ;

    // mmu state
    localparam M_IDLE = 'd0, M_PTW = 'd1, M_WRITE = 'd2, M_READ = 'd3, M_DCHECK = 'd4 ;
    reg  [2:0] mstate_q , mstate_d  ;

    // iptw, fetch, load, store
    reg        ptw_process_q, ptw_process_d;
    localparam ENONE = 'd0, EFETCH = 'd1, ELOAD = 'd2, ESTORE = 'd3;
    reg  [1:0] exc_type_q  , exc_type_d             ;

    assign ibus_arready_o   = (istate_q==I_IDLE)                                                                ;
    assign dbus_wready_o    = (dstate_q==D_IDLE)                                                                ;
    assign dbus_arready_o   = (dstate_q==D_IDLE)                                                                ;
    assign bus_bready_o     = (mstate_q==M_WRITE)                                                               ;
    assign bus_rready_o     = (mstate_q==M_PTW) || (mstate_q==M_READ)                                           ;

    reg                         ibus_rvalid_q   , ibus_rvalid_d     ;
    reg  [`IBUS_DATA_WIDTH-1:0] ibus_rdata_q    , ibus_rdata_d      ;
    reg      [`RRESP_WIDTH-1:0] ibus_rresp_q    , ibus_rresp_d      ;
    reg                         dbus_awlock_q   , dbus_awlock_d     ;
    reg  [`DBUS_DATA_WIDTH-1:0] dbus_wdata_q    , dbus_wdata_d      ;
    reg  [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_q    , dbus_wstrb_d      ;
    reg                         dbus_bvalid_q   , dbus_bvalid_d     ;
    reg      [`BRESP_WIDTH-1:0] dbus_bresp_q    , dbus_bresp_d      ;
    reg                         dbus_arlock_q   , dbus_arlock_d     ;
    reg                         dbus_rvalid_q   , dbus_rvalid_d     ;
    reg  [`DBUS_DATA_WIDTH-1:0] dbus_rdata_q    , dbus_rdata_d      ;
    reg      [`RRESP_WIDTH-1:0] dbus_rresp_q    , dbus_rresp_d      ;

    reg                         bus_wvalid_q    , bus_wvalid_d      ;
    reg   [`BUS_ADDR_WIDTH-1:0] bus_awaddr_q    , bus_awaddr_d      ;
    reg   [`BUS_DATA_WIDTH-1:0] bus_wdata_q     , bus_wdata_d       ;
    reg   [`BUS_STRB_WIDTH-1:0] bus_wstrb_q     , bus_wstrb_d       ;
    reg                         bus_arvalid_q   , bus_arvalid_d     ;
    reg   [`BUS_ADDR_WIDTH-1:0] bus_araddr_q    , bus_araddr_d      ;

    
    assign ibus_rvalid_o    = (icache_hit && istate_q==I_CACHE) ? 1'b1 : ibus_rvalid_q              ;
    assign ibus_rresp_o     = (icache_hit && istate_q==I_CACHE) ? `RRESP_OKAY : ibus_rresp_q        ;
    assign ibus_rdata_o     = ibus_rdata_q      ;
    assign dbus_bvalid_o    = ((dcache_hit || dallocate_q) && dstate_q==D_STORE) ? 1'b1 : dbus_bvalid_q;
    assign dbus_bresp_o     = ((dcache_hit || dallocate_q) && dstate_q==D_STORE) ? ((dbus_awlock_q) ? `BRESP_EXOKAY : `BRESP_OKAY)
                                                                : dbus_bresp_q                    ;
    assign dbus_rvalid_o    = (dcache_hit && dstate_q==D_CACHE) ?  1'b1 : dbus_rvalid_q           ;
    assign dbus_rresp_o     = (dcache_hit && dstate_q==D_CACHE) ? `RRESP_OKAY : dbus_rresp_q      ;
    assign dbus_rdata_o     = dbus_rdata_q      ;

    assign bus_wvalid_o     = bus_wvalid_q      ;
    assign bus_awaddr_o     = bus_awaddr_q      ;
    assign bus_wdata_o      = bus_wdata_q       ;
    assign bus_wstrb_o      = bus_wstrb_q       ;
    assign bus_arvalid_o    = bus_arvalid_q     ;
    assign bus_araddr_o     = bus_araddr_q      ;

    ///// select bus read
    wire [`XLEN-1:0] bus_rdata_selected ;
    assign bus_rdata_selected = (bus_araddr_q[3:2]=='b11) ? bus_rdata_i[127:96] :
                                 (bus_araddr_q[3:2]=='b10) ? bus_rdata_i[ 95:64] :
                                 (bus_araddr_q[3:2]=='b01) ? bus_rdata_i[ 63:32] :
                                                             bus_rdata_i[ 31: 0] ;
    ///// lrsc
    localparam RSVD_MSB = `PLEN-1, RSVD_LSB = 2, RSVD_WIDTH = RSVD_MSB-RSVD_LSB+1;
    reg  [RSVD_WIDTH-1:0] rsvd_addr_q , rsvd_addr_d  ;
    reg                   rsvd_q      , rsvd_d       ;
    
    ///// write strb width
    reg             dallocate_q  , dallocate_d  ;
    wire [`BUS_STRB_WIDTH-1:0] data_wstrb       ;
    assign data_wstrb = (data_vaddr_q[3:2]=='b11) ? {dbus_wstrb_q, 12'h0}      :
                        (data_vaddr_q[3:2]=='b10) ? {4'h0, dbus_wstrb_q, 8'h0} :
                        (data_vaddr_q[3:2]=='b01) ? {8'h0, dbus_wstrb_q, 4'h0} :
                                                    {12'h0, dbus_wstrb_q}      ;
                                                                        
    always @(*) begin
        instr_vaddr_d           = instr_vaddr_q         ;
        instr_paddr_d           = instr_paddr_q         ;
        fetch_ptw_pending_d     = fetch_ptw_pending_q   ;
        fetch_pending_d         = fetch_pending_q       ;
        icache_we_d             = 1'b0                  ;
        icache_wdata_d          = icache_wdata_q        ;
        icache_invalidate_d     = 1'b0                  ;
        is_store_d              = is_store_q            ;
        is_amo_d                = is_amo_q              ;
        data_vaddr_d            = data_vaddr_q          ;
        data_paddr_d            = data_paddr_q          ;
        store_ptw_pending_d     = store_ptw_pending_q   ;
        store_pending_d         = store_pending_q       ;
        load_ptw_pending_d      = load_ptw_pending_q    ;
        load_pending_d          = load_pending_q        ;
        dcache_we_d             = 1'b0                  ;
        dcache_wdata_d          = dcache_wdata_q        ;
        dcache_wstrb_d          = dcache_wstrb_q        ;
        dcache_wdirty_d         = dcache_wdirty_q       ;
        dcache_wbclean_d        = 1'b0                  ;
        dallocate_d             = 1'b0                  ;
        load_addr_d             = load_addr_q           ;
        ptw_process_d           = ptw_process_q         ;
        exc_type_d              = exc_type_q            ;
        ptw_req_d               = 1'b0                  ;
        fetch_req_d             = fetch_req_q           ;
        store_req_d             = store_req_q           ;
        load_req_d              = load_req_q            ;
        vaddr_d                 = vaddr_q               ;
        pte_rvalid_d            = 1'b0                  ;
        pte_rdata_d             = pte_rdata_q           ;
        ibus_rvalid_d           = ibus_rvalid_q         ;
        ibus_rdata_d            = ibus_rdata_q          ;
        ibus_rresp_d            = ibus_rresp_q          ;
        dbus_awlock_d           = dbus_awlock_q         ;
        dbus_wdata_d            = dbus_wdata_q          ;
        dbus_wstrb_d            = dbus_wstrb_q          ;
        dbus_bvalid_d           = dbus_bvalid_q         ;
        dbus_bresp_d            = dbus_bresp_q          ;
        dbus_arlock_d           = dbus_arlock_q         ;
        dbus_rvalid_d           = dbus_rvalid_q         ;
        dbus_rdata_d            = dbus_rdata_q          ;
        dbus_rresp_d            = dbus_rresp_q          ;
        bus_wvalid_d            = bus_wvalid_q          ;
        bus_awaddr_d            = bus_awaddr_q          ;
        bus_wdata_d             = bus_wdata_q           ;
        bus_wstrb_d             = bus_wstrb_q           ;
        bus_arvalid_d           = bus_arvalid_q         ;
        bus_araddr_d            = bus_araddr_q          ;
        rsvd_addr_d             = rsvd_addr_q           ;
        rsvd_d                  = rsvd_q                ;
        istate_d                = istate_q              ;
        dstate_d                = dstate_q              ;
        mstate_d                = mstate_q              ;

        dcache_wbstored_d       = dcache_wbstored_q  || dcache_store_inwb;
        // instruction cache/tlb
        case (istate_q)
            I_IDLE      : begin
                if (ibus_arvalid_i) begin
                    instr_vaddr_d       = ibus_araddr_i     ;
                    istate_d            = I_TLB             ;
                end
            end
            I_TLB       : begin
                if (itlb_valid) begin
                    if (itlb_page_fault) begin // itlb miss, this is a page fault
                        ibus_rvalid_d       = 1'b1              ;
                        ibus_rresp_d        = `RRESP_TRANSFAULT ;
                        istate_d            = I_RET             ;
                    end else begin // itlb hit
                        instr_paddr_d       = itlb_paddr        ;
                        ibus_rdata_d        = icache_rdata      ;
                        istate_d            = I_CACHE           ; // compare tag
                    end
                end else begin // itlb miss, do a page-table walk
                    fetch_ptw_pending_d = 1'b1              ;
                    istate_d            = I_PTW             ;
                end
            end
            I_CACHE     : begin
                if (icache_hit) begin
                    if (ibus_rready_i) begin
                        istate_d               = I_IDLE                             ;
                    end else begin
                        ibus_rvalid_d           = 1'b1                              ;
                        ibus_rresp_d            = `RRESP_OKAY                       ;
                        istate_d                = I_RET                             ;
                    end
                end else begin // cache miss
                    fetch_pending_d         = 1'b1                              ;
                    istate_d                = I_FETCH                           ;
                end
            end
            I_PTW       : begin
                if (ptw_resp_v && !fetch_ptw_pending_q) begin
                    if (page_fault) begin
                        ibus_rvalid_d   = 1'b1              ;
                        ibus_rresp_d    = `RRESP_TRANSFAULT ;
                        istate_d        = I_RET             ;
                    end else begin
                        instr_paddr_d   = paddr             ;
                        ibus_rdata_d    = icache_rdata      ;
                        istate_d        = I_CACHE           ; // compare tag
                    end
                end
            end
            I_FETCH     : begin
                if (bus_rvalid_i && bus_rready_o && !fetch_pending_q) begin
                    // RRSPOKAY ONLYi
                    if (bus_rresp_i==`BRESP_OKAY) begin
                        icache_we_d     = 1'b1                          ;
                        icache_wdata_d  = bus_rdata_i                   ;
                    end
                    ibus_rvalid_d   = 1'b1                              ;
                    ibus_rdata_d    = bus_rdata_i                       ;
                    ibus_rresp_d    = bus_rresp_i                       ;
                    istate_d        = I_RET                             ;
                end
            end
            I_RET       : begin
                if (ibus_rready_i) begin
                    ibus_rvalid_d   = 1'b0              ;
                    istate_d        = I_IDLE            ;
                end
            end
            default     : ;
        endcase

        // data cache/tlb
        case (dstate_q)
            D_IDLE      : begin
                if (dbus_wvalid_i) begin // store
                    is_store_d          = 1'b1                  ;
                    data_vaddr_d        = dbus_axaddr_i         ;
                    dbus_awlock_d       = dbus_awlock_i         ;
                    dbus_wdata_d        = dbus_wdata_i          ;
                    dbus_wstrb_d        = dbus_wstrb_i          ;
                    dstate_d            = D_TLB                 ;
                end else if (dbus_arvalid_i) begin // load
                    is_amo_d            = dbus_aramo_i          ;
                    data_vaddr_d        = dbus_axaddr_i         ;
                    dbus_arlock_d       = dbus_arlock_i         ;
                    dstate_d            = D_TLB                 ;
                end
            end
            D_TLB       : begin
                if (is_store_q) begin
                    if (dtlb_valid) begin
                        if (dtlb_page_fault) begin // dtlb miss, this is a page fault
                            dbus_bvalid_d       = 1'b1              ;
                            dbus_bresp_d        = `BRESP_TRANSFAULT ;
                            dstate_d            = D_RET             ;
                        end else begin // dtlb hit
                            data_paddr_d        = dtlb_paddr        ;
                            dstate_d            = (dbus_awlock_q) ? D_CHECK : D_STORE;
                            icache_invalidate_d = (dbus_awlock_q) ? 1'b0    : 1'b1   ;
                        end
                    end else begin // dtlb miss, do a page-table walk
                        store_ptw_pending_d = 1'b1              ;
                        dstate_d            = D_PTW             ;
                    end
                end else begin
                    if (dtlb_valid) begin
                        if (dtlb_page_fault) begin // dtlb miss, this is a page fault
                            dbus_rvalid_d       = 1'b1              ;
                            dbus_rresp_d        = `RRESP_TRANSFAULT ;
                            dstate_d            = D_RET             ;
                        end else begin // dtlb hit
                            data_paddr_d        = dtlb_paddr        ;
                            dbus_rdata_d        = dcache_rdata      ;
                            dstate_d            = D_CACHE           ;
                        end
                    end else begin // dtlb miss, do a page-table walk
                        if (is_amo_q) begin
                            store_ptw_pending_d = 1'b1              ; // amo load
                        end else begin
                            load_ptw_pending_d  = 1'b1              ; // load
                        end
                        dstate_d            = D_PTW             ;
                    end
                end
            end
            D_CACHE     : begin // load
                if (dbus_arlock_q) begin
                    rsvd_addr_d         = data_paddr_q[RSVD_MSB:RSVD_LSB] ;
                    rsvd_d              = 1'b1                            ;
                end
                if (dcache_hit) begin // NOTE: lock is not implemented in L1 cache
                    if(dbus_rready_i) begin
                        dstate_d                = D_IDLE                         ;
                    end else begin
                        dbus_rvalid_d           = 1'b1                          ;
                        dbus_rresp_d            = `RRESP_OKAY                   ;
                        dstate_d                = D_RET                         ;
                    end
                end else begin // cache miss
                    load_pending_d          = 1'b1                          ;
                    dstate_d                = D_ALLOCATE                    ;
                end
            end
            D_PTW       : begin
                if (ptw_resp_v) begin
                    if (is_store_q) begin
                        if (!store_ptw_pending_q) begin
                            if (page_fault) begin
                                dbus_bvalid_d       = 1'b1              ;
                                dbus_bresp_d        = `BRESP_TRANSFAULT ;
                                dstate_d            = D_RET             ;
                            end else begin
                                data_paddr_d        = paddr             ;
                                dstate_d            = (dbus_awlock_q) ? D_CHECK : D_STORE;
                                icache_invalidate_d = (dbus_awlock_q) ? 1'b0    : 1'b1   ;
                            end
                        end
                    end else begin // load
                        if (!load_ptw_pending_q && !store_ptw_pending_q) begin
                            if (page_fault) begin
                                dbus_rvalid_d       = 1'b1              ;
                                dbus_rresp_d        = `RRESP_TRANSFAULT ;
                                dstate_d            = D_RET             ;
                            end else begin
                                data_paddr_d        = paddr             ;
                                dbus_rdata_d        = dcache_rdata      ;
                                dstate_d            = D_CACHE           ; // compare tag
                            end
                        end
                    end
                end
            end
            D_CHECK    : begin ///// lrsc
                if ((rsvd_q)&&(data_paddr_q[RSVD_MSB:RSVD_LSB]==rsvd_addr_q)) begin
                    dstate_d            = D_STORE                     ;
                    icache_invalidate_d = 1'b1                        ;
                end else begin
                    dbus_bresp_d    = `BRESP_OKAY                     ;
                    dbus_bvalid_d   = 1'b1                            ;
                    dstate_d        = D_RET                           ;
                end
                rsvd_d         = 1'b0                            ;
            end
            D_STORE     : begin
                // if hit or write cachce
                if (dcache_hit || dallocate_q) begin
                    if (rsvd_addr_q==data_paddr_q[RSVD_MSB:RSVD_LSB]) begin // lrsc
                        rsvd_addr_d     = 1'b0                  ;
                    end
                    dcache_we_d         = 1'b1          ; 
                    dcache_wdirty_d     = 1'b1          ;
                    dcache_wstrb_d      = data_wstrb    ;
                    dcache_wdata_d      = {(`BUS_DATA_WIDTH/`DBUS_DATA_WIDTH){dbus_wdata_q}};
                    if(dbus_bready_i) begin
                        is_store_d          = 1'b0                           ;
                        dstate_d            = D_IDLE                         ;
                    end else begin
                        dbus_bvalid_d       = 1'b1          ;
                        dbus_bresp_d        = (dbus_awlock_q) ? `BRESP_EXOKAY : `BRESP_OKAY ;
                        dstate_d            = D_RET                         ;
                    end
                end else if (data_periph_access) begin // periph write
                    store_pending_d     = 1'b1         ;
                    dstate_d            = D_PERIPH     ;
                end else begin // miss
                    load_pending_d      = 1'b1         ;
                    dstate_d            = D_ALLOCATE   ;
                end
            end
            D_PERIPH : begin
                if (bus_bvalid_i && bus_bready_o && !store_pending_q) begin
                    dbus_bvalid_d    = 1'b1       ;
                    dbus_bresp_d     = bus_bresp_i;
                    dstate_d         = D_RET      ; 
                end
            end
            D_ALLOCATE: begin
                if (bus_rvalid_i && bus_rready_o && !load_pending_q) begin
                    if (!data_periph_access && bus_rresp_i==`BRESP_OKAY) begin // peripheral access is not bufferable
                        dcache_we_d     = 1'b1                              ;
                        dcache_wdirty_d = 1'b0                              ;
                        dcache_wdata_d  = bus_rdata_i                       ;
                        dcache_wstrb_d  = {`BUS_STRB_WIDTH{1'b1}}           ;
                        dbus_rdata_d    = bus_rdata_selected                ;
                        if (is_store_q) begin
                            dstate_d = D_STORE;
                            dallocate_d = 1'b1;
                        end else begin
                            dbus_rvalid_d   = 1'b1                           ;
                            dstate_d        = D_RET                          ;
                            dbus_rresp_d    = bus_rresp_i                    ;
                        end
                    end else begin // peripheral access
                        dbus_rdata_d    = bus_rdata_i[`DBUS_DATA_WIDTH-1:0] ;
                        dbus_rvalid_d   = 1'b1             ;
                        dbus_rresp_d    = bus_rresp_i      ;
                        dstate_d        = D_RET            ;
                    end
                end
            end
            D_RET       : begin
                if (is_store_q) begin // store
                    if (dbus_bready_i) begin
                        is_store_d          = 1'b0              ;
                        dbus_bvalid_d       = 1'b0              ;
                        dstate_d            = D_IDLE            ;
                    end
                end else begin // load
                    if (dbus_rready_i) begin
                        dbus_rvalid_d       = 1'b0              ;
                        dstate_d            = D_IDLE            ;
                    end
                end
            end
            default     : ;
        endcase

        // mmu
        case (mstate_q)
            M_IDLE  : begin
                exc_type_d          = ENONE             ;
                if (store_ptw_pending_q || load_ptw_pending_q || fetch_ptw_pending_q) begin // tlb miss, do a page-table walk
                    fetch_req_d         = 1'b0              ;
                    store_req_d         = 1'b0              ;
                    load_req_d          = 1'b0              ;
                    ptw_req_d           = 1'b1              ;
                    ptw_process_d       = 1'b1              ;
                    if (store_ptw_pending_q) begin
                        store_ptw_pending_d = 1'b0              ;
                        store_req_d         = 1'b1              ;
                        vaddr_d             = data_vaddr_q      ;
                        exc_type_d          = ESTORE            ;
                    end else if (load_ptw_pending_q) begin
                        load_ptw_pending_d  = 1'b0              ;
                        load_req_d          = 1'b1              ;
                        vaddr_d             = data_vaddr_q      ;
                        exc_type_d          = ELOAD             ;
                    end else begin
                        fetch_ptw_pending_d = 1'b0              ;
                        fetch_req_d         = 1'b1              ;
                        vaddr_d             = instr_vaddr_q     ;
                        exc_type_d          = EFETCH            ;
                    end
                    mstate_d            = M_PTW                 ;
                end else if (store_pending_q || load_pending_q || fetch_pending_q) begin
                    if (store_pending_q) begin
                        store_pending_d      = 1'b0              ;
                        bus_wvalid_d         = 1'b1              ;
                        bus_awaddr_d         = data_paddr_q      ;
                        bus_wdata_d          = {(`BUS_DATA_WIDTH/`DBUS_DATA_WIDTH){dbus_wdata_q}};
                        bus_wstrb_d          = {{(`BUS_STRB_WIDTH-`DBUS_STRB_WIDTH){1'b0}}, dbus_wstrb_q};
                        exc_type_d           = ESTORE            ; 
                        mstate_d             = M_WRITE           ;
                    end else begin // if (load_pending_q || fetch_pending_q)
                        if (load_pending_q) begin
                            load_pending_d      = 1'b0              ;
                            load_addr_d         = data_paddr_q      ;
                            dcache_wbstored_d   = dcache_store_inwb ;
                            bus_araddr_d        = data_paddr_q      ;
                            exc_type_d          = ELOAD             ;
                            bus_arvalid_d       = (data_periph_access) ? 1'b1 : 0         ; 
                            mstate_d            = (data_periph_access) ? M_READ : M_DCHECK;
                        end else begin
                            fetch_pending_d     = 1'b0              ;
                            load_addr_d         = instr_paddr_q     ;
                            dcache_wbstored_d   = dcache_store_inwb ;
                            bus_araddr_d        = instr_paddr_q     ;
                            exc_type_d          = EFETCH            ;
                            mstate_d            = M_DCHECK          ;
                        end
                    end
                end
            end
            M_DCHECK : begin
                if (dcache_wback_rvalid && dcache_wback_rdirty) begin
                    bus_wvalid_d  = 1'b1             ;
                    bus_awaddr_d  = dcache_wback_addr;
                    bus_wdata_d   = dcache_wback_data;
                    bus_wstrb_d   = {(`BUS_STRB_WIDTH){1'b1}};
                    mstate_d      = M_WRITE          ;
                end else begin
                    bus_arvalid_d = 1'b1;
                    mstate_d     = (ptw_process_q) ? M_PTW : M_READ;
                end
            end
            M_PTW   : begin
                // pte ready
                if (pte_arvalid) begin
                    load_addr_d       = pte_araddr        ;
                    dcache_wbstored_d = dcache_store_inwb ;
                    bus_araddr_d      = pte_araddr        ;
                    mstate_d          = M_DCHECK          ;
                end
                if (bus_arvalid_o && bus_arready_i) begin
                    bus_arvalid_d = 1'b0;
                end
                if (bus_rvalid_i && bus_rready_o) begin
                    pte_rvalid_d    = 1'b1               ;
                    pte_rdata_d     = bus_rdata_selected ;
                end
                // ptw response
                if (ptw_resp_v) begin
                    ptw_process_d   = 1'b0          ;
                    mstate_d        = M_IDLE        ;
                end
            end
            M_WRITE : begin
                if (bus_wready_i) begin
                    bus_wvalid_d    = 1'b0          ;
                end
                if (bus_bvalid_i) begin
                    if (data_periph_access && exc_type_q==ESTORE && !ptw_process_q) begin
                        mstate_d        = M_IDLE        ;
                    end else if (bus_bresp_i==`BRESP_OKAY) begin
                        bus_arvalid_d         = 1'b1                               ;
                        mstate_d              = (ptw_process_q) ? M_PTW : M_READ   ;
                        dcache_wbclean_d      = !dcache_wbstored_q && !dcache_store_inwb ; // clean dirty bit 
                    end else begin
                        case (exc_type_q)
                            EFETCH : begin
                                istate_d = I_RET;
                                ibus_rresp_d = bus_bresp_i;
                                ibus_rvalid_d = 1'b1;
                            end
                            ELOAD : begin
                                dstate_d = D_RET;
                                dbus_rresp_d = bus_bresp_i;
                                dbus_rvalid_d = 1'b1;
                            end
                            default: begin
                                dstate_d = D_RET;
                                dbus_bresp_d = bus_bresp_i;
                                dbus_bvalid_d = 1'b1;
                            end   
                        endcase
                        mstate_d        = M_IDLE     ;
                    end
                end
            end
            M_READ  : begin
                if (bus_arready_i) begin
                    bus_arvalid_d   = 1'b0          ;
                end
                if (bus_rvalid_i) begin
                    if (data_periph_access || bus_rresp_i==`RRESP_OKAY) begin
                        mstate_d        = M_IDLE        ;
                    end else begin
                        case (exc_type_q)
                            EFETCH: begin
                                istate_d = I_RET;
                                ibus_rresp_d = bus_rresp_i;
                                ibus_rvalid_d = 1'b1;
                            end
                            ELOAD : begin
                                dstate_d = D_RET;
                                dbus_rresp_d = bus_rresp_i;
                                dbus_rvalid_d = 1'b1;
                            end
                            default: begin
                                dstate_d = D_RET;
                                dbus_bresp_d = bus_rresp_i;
                                dbus_bvalid_d = 1'b1;
                            end
                        endcase
                        mstate_d  = M_IDLE;
                    end
                end
            end
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            fetch_ptw_pending_q     <= 1'b0                 ;
            fetch_pending_q         <= 1'b0                 ;
            icache_we_q             <= 1'b0                 ;
            is_store_q              <= 1'b0                 ;
            is_amo_q                <= 1'b0                 ;
            store_ptw_pending_q     <= 1'b0                 ;
            store_pending_q         <= 1'b0                 ;
            load_ptw_pending_q      <= 1'b0                 ;
            load_pending_q          <= 1'b0                 ;
            dcache_we_q             <= 1'b0                 ;
            ptw_req_q               <= 1'b0                 ;
            pte_rvalid_q            <= 1'b0                 ;
            ibus_rvalid_q           <= 1'b0                 ;
            dbus_bvalid_q           <= 1'b0                 ;
            dbus_rvalid_q           <= 1'b0                 ;
            bus_wvalid_q            <= 1'b0                 ;
            bus_arvalid_q           <= 1'b0                 ;
            rsvd_q                  <= 1'b0                 ;
            ptw_process_q           <= 1'b0                 ;
            istate_q                <= I_IDLE               ;
            dstate_q                <= D_IDLE               ;
            mstate_q                <= M_IDLE               ;
        end else begin
            instr_vaddr_q           <= instr_vaddr_d        ;
            instr_paddr_q           <= instr_paddr_d        ;
            fetch_ptw_pending_q     <= fetch_ptw_pending_d  ;
            fetch_pending_q         <= fetch_pending_d      ;
            icache_we_q             <= icache_we_d          ;
            icache_wdata_q          <= icache_wdata_d       ;
            icache_invalidate_q     <= icache_invalidate_d  ;
            is_store_q              <= is_store_d           ;
            is_amo_q                <= is_amo_d             ;
            data_vaddr_q            <= data_vaddr_d         ;
            data_paddr_q            <= data_paddr_d         ;
            store_ptw_pending_q     <= store_ptw_pending_d  ;
            store_pending_q         <= store_pending_d      ;
            load_ptw_pending_q      <= load_ptw_pending_d   ;
            load_pending_q          <= load_pending_d       ;
            dcache_we_q             <= dcache_we_d          ;
            dcache_wdata_q          <= dcache_wdata_d       ;
            dcache_wstrb_q          <= dcache_wstrb_d       ;
            dcache_wdirty_q         <= dcache_wdirty_d      ;
            dcache_wbstored_q       <= dcache_wbstored_d    ;
            ptw_req_q               <= ptw_req_d            ;
            ptw_process_q           <= ptw_process_d        ;
            exc_type_q              <= exc_type_d           ;
            load_addr_q             <= load_addr_d          ;
            fetch_req_q             <= fetch_req_d          ;
            store_req_q             <= store_req_d          ;
            load_req_q              <= load_req_d           ;
            vaddr_q                 <= vaddr_d              ;
            pte_rvalid_q            <= pte_rvalid_d         ;
            pte_rdata_q             <= pte_rdata_d          ;
            ibus_rvalid_q           <= ibus_rvalid_d        ;
            ibus_rdata_q            <= ibus_rdata_d         ;
            ibus_rresp_q            <= ibus_rresp_d         ;
            dbus_awlock_q           <= dbus_awlock_d        ;
            dbus_wdata_q            <= dbus_wdata_d         ;
            dbus_wstrb_q            <= dbus_wstrb_d         ;
            dbus_bvalid_q           <= dbus_bvalid_d        ;
            dbus_bresp_q            <= dbus_bresp_d         ;
            dbus_arlock_q           <= dbus_arlock_d        ;
            dbus_rvalid_q           <= dbus_rvalid_d        ;
            dbus_rdata_q            <= dbus_rdata_d         ;
            dbus_rresp_q            <= dbus_rresp_d         ;
            bus_wvalid_q            <= bus_wvalid_d         ;
            bus_awaddr_q            <= bus_awaddr_d         ;
            bus_wdata_q             <= bus_wdata_d          ;
            bus_wstrb_q             <= bus_wstrb_d          ;
            bus_arvalid_q           <= bus_arvalid_d        ;
            bus_araddr_q            <= bus_araddr_d         ;
            rsvd_addr_q             <= rsvd_addr_d          ;
            rsvd_q                  <= rsvd_d               ;
            istate_q                <= istate_d             ;
            dstate_q                <= dstate_d             ;
            mstate_q                <= mstate_d             ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
