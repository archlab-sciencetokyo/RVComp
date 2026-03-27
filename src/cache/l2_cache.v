/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"

/* L2 unified cache, 4-way set associative, PIPT */
/******************************************************************************************/
module l2_cache #(
    parameter  CACHE_SIZE   = 0                                     , // cache size (bytes)
    localparam N_WAYS       = 4                                     , // number of ways
    parameter  ADDR_WIDTH   = 0                                     , // address width
    localparam DATA_WIDTH   = 128                                   , // data width of cache
    localparam STRB_WIDTH   = DATA_WIDTH/8                          , // strobe width
    localparam OFFSET_WIDTH = $clog2(DATA_WIDTH/8)                  , // offset width
    localparam INDEX_WIDTH  = $clog2(CACHE_SIZE/N_WAYS)-OFFSET_WIDTH, // index width
    localparam TAG_WIDTH    = ADDR_WIDTH-(INDEX_WIDTH+OFFSET_WIDTH) , // tag width
    localparam OFFSET_LSB   = 0                                     , // offset least significant bit
    localparam OFFSET_MSB   = OFFSET_LSB+OFFSET_WIDTH-1             , // offset most significant bit
    localparam INDEX_LSB    = OFFSET_MSB+1                          , // index least significant bit
    localparam INDEX_MSB    = INDEX_LSB+INDEX_WIDTH-1               , // index most significant bit
    localparam TAG_LSB      = INDEX_MSB+1                           , // tag least significant bit
    localparam TAG_MSB      = TAG_LSB+TAG_WIDTH-1                     // tag most significant bit
) (
    input  wire                    clk_i            , // clock
    input  wire                    rst_i            , // reset
    ///// mmu - L2$
    input  wire                    cpu_wvalid_i     , // store request valid
    output wire                    cpu_wready_o     , // store request ready
    input  wire   [ADDR_WIDTH-1:0] cpu_awaddr_i     , // store request address
    input  wire   [DATA_WIDTH-1:0] cpu_wdata_i      , // store request data
    input  wire   [STRB_WIDTH-1:0] cpu_wstrb_i      , // store request strobe
    output wire                    cpu_bvalid_o     , // store response valid
    input  wire                    cpu_bready_i     , // store response ready
    output wire [`BRESP_WIDTH-1:0] cpu_bresp_o      , // store response status
    input  wire                    cpu_arvalid_i    , // read request valid
    output wire                    cpu_arready_o    , // read request ready
    input  wire   [ADDR_WIDTH-1:0] cpu_araddr_i     , // read request address
    output wire                    cpu_rvalid_o     , // read response valid
    input  wire                    cpu_rready_i     , // read response ready
    output wire   [DATA_WIDTH-1:0] cpu_rdata_o      , // read response data
    output wire [`RRESP_WIDTH-1:0] cpu_rresp_o      , // read response status
    ///// L2$ - AXI
    output wire                    bus_wvalid_o     , // store request valid 
    input  wire                    bus_wready_i     , // store request ready
    output wire   [ADDR_WIDTH-1:0] bus_awaddr_o     , // store request address
    output wire   [DATA_WIDTH-1:0] bus_wdata_o      , // store request data
    output wire   [STRB_WIDTH-1:0] bus_wstrb_o      , // store request strobe
    input  wire                    bus_bvalid_i     , // store response valid
    output wire                    bus_bready_o     , // store response ready
    input  wire [`BRESP_WIDTH-1:0] bus_bresp_i      , // store response status
    output wire                    bus_arvalid_o    , // read request valid
    input  wire                    bus_arready_i    , // read request ready
    output wire   [ADDR_WIDTH-1:0] bus_araddr_o     , // read request address
    input  wire                    bus_rvalid_i     , // read response valid
    output wire                    bus_rready_o     , // read response ready
    input  wire   [DATA_WIDTH-1:0] bus_rdata_i      , // read response data
    input  wire [`RRESP_WIDTH-1:0] bus_rresp_i        // read response status
);

    // DRC: design rule check
    initial begin
        if (CACHE_SIZE ==0  ) $fatal(1, "specify a l2_cache CACHE_SIZE");
        if (N_WAYS     !=4  ) $fatal(1, "this L2 cache only supports 4-way");
        if (ADDR_WIDTH ==0  ) $fatal(1, "specify a l2_cache ADDR_WIDTH");
        if (DATA_WIDTH ==0  ) $fatal(1, "specify a l2_cache DATA_WIDTH");
        if (DATA_WIDTH !=128) $fatal(1, "this L2 cache only supports 128-bit DATA_WIDTH");
    end

    integer i;
    // cache
    // meta_ram: {valid, dirty, tag}
    (* ram_style = "block" *) reg   [TAG_WIDTH+1:0] meta_ram3 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg   [TAG_WIDTH+1:0] meta_ram2 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg   [TAG_WIDTH+1:0] meta_ram1 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg   [TAG_WIDTH+1:0] meta_ram0 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram3 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram2 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram1 [0:2**INDEX_WIDTH-1]  ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] data_ram0 [0:2**INDEX_WIDTH-1]  ;

    reg      [INDEX_WIDTH-1:0] idx                                              ;

    reg           [N_WAYS-1:0] rvalid                                           ;
    reg           [N_WAYS-1:0] rdirty                                           ;
    reg        [TAG_WIDTH-1:0] rtag  [0:N_WAYS-1]                               ;
    reg       [DATA_WIDTH-1:0] rdata [0:N_WAYS-1]                               ;

    reg           [N_WAYS-1:0] hit_q                , hit_d                     ;

    reg           [N_WAYS-1:0] we_q                 , we_d                      ;
    reg                        wdirty_q             , wdirty_d                  ;
    wire       [TAG_WIDTH-1:0] wtag                                             ;
    reg       [DATA_WIDTH-1:0] wdata_q              , wdata_d                   ;
    reg       [STRB_WIDTH-1:0] wstrb_q              , wstrb_d                   ;

    // PLRU: pseudo least recently used replacement
    (* ram_style = "block" *) reg  [N_WAYS-2:0] plru_tree_ram [0:2**INDEX_WIDTH-1]  ;
    reg           [N_WAYS-2:0] plru_tree_rdata                                  ;
    reg                        plru_tree_we_q       , plru_tree_we_d            ;
    reg           [N_WAYS-2:0] plru_tree_wdata_q    , plru_tree_wdata_d         ;

    reg   [$clog2(N_WAYS)-1:0] replace_q            , replace_d                 ;

    // fsm
    localparam IDLE = 'd0, CHECK_LOCK = 'd1, COMPARE_TAG = 'd2, CHECK_VALID = 'd3, WRITE_BACK = 'd4, ALLOCATE = 'd5, WRITE_CACHE = 'd6, PERIPH_WRITE = 'd7, PERIPH_READ = 'd8, RET = 'd9, LATENCY = 'd10;
    reg  [3:0] state_q  , state_d   ;

    reg                        is_load_q            , is_load_d                 ;
    reg                        is_store_q           , is_store_d                ;

    reg       [ADDR_WIDTH-1:0] cpu_axaddr_q         , cpu_axaddr_d              ;
    reg       [DATA_WIDTH-1:0] cpu_wdata_q          , cpu_wdata_d               ;
    reg       [STRB_WIDTH-1:0] cpu_wstrb_q          , cpu_wstrb_d               ;
    reg                        cpu_bvalid_q         , cpu_bvalid_d              ;
    reg     [`BRESP_WIDTH-1:0] cpu_bresp_q          , cpu_bresp_d               ;
    reg                        cpu_rvalid_q         , cpu_rvalid_d              ;
    reg       [DATA_WIDTH-1:0] cpu_rdata_q          , cpu_rdata_d               ;
    reg     [`RRESP_WIDTH-1:0] cpu_rresp_q          , cpu_rresp_d               ;

    reg                        bus_wvalid_q         , bus_wvalid_d              ;
    reg       [ADDR_WIDTH-1:0] bus_awaddr_q         , bus_awaddr_d              ;
    reg       [DATA_WIDTH-1:0] bus_wdata_q          , bus_wdata_d               ;
    reg       [STRB_WIDTH-1:0] bus_wstrb_q          , bus_wstrb_d               ;
    reg                        bus_arvalid_q        , bus_arvalid_d             ;
    reg       [ADDR_WIDTH-1:0] bus_araddr_q         , bus_araddr_d              ;

    assign cpu_wready_o     = (state_q==IDLE) && !cpu_arvalid_i                 ;
    assign cpu_bvalid_o     = cpu_bvalid_q                                      ;
    assign cpu_bresp_o      = cpu_bresp_q                                       ;
    assign cpu_arready_o    = (state_q==IDLE)                                   ;
    assign cpu_rvalid_o     = cpu_rvalid_q                                      ;
    assign cpu_rdata_o      = cpu_rdata_q                                       ;
    assign cpu_rresp_o      = cpu_rresp_q                                       ;

    assign bus_wvalid_o     = bus_wvalid_q                                      ;
    assign bus_awaddr_o     = bus_awaddr_q                                      ;
    assign bus_wdata_o      = bus_wdata_q                                       ;
    assign bus_wstrb_o      = bus_wstrb_q                                       ;
    assign bus_bready_o     = (state_q==WRITE_BACK) || (state_q==PERIPH_WRITE)  ;
    assign bus_arvalid_o    = bus_arvalid_q                                     ;
    assign bus_araddr_o     = bus_araddr_q                                      ;
    assign bus_rready_o     = (state_q==ALLOCATE) || (state_q==PERIPH_READ)     ;

    assign wtag             = cpu_axaddr_q[TAG_MSB:TAG_LSB]                     ;

    always @(*) begin
        idx                 = cpu_axaddr_q[INDEX_MSB:INDEX_LSB]         ;
        hit_d               = 'h0                                       ;
        we_d                = 'h0                                       ;
        wdirty_d            = 1'b0                                      ;
        wdata_d             = wdata_q                                   ;
        wstrb_d             = wstrb_q                                   ;
        is_load_d           = is_load_q                                 ;
        is_store_d          = is_store_q                                ;
        cpu_axaddr_d        = cpu_axaddr_q                              ;
        cpu_wdata_d         = cpu_wdata_q                               ;
        cpu_wstrb_d         = cpu_wstrb_q                               ;
        cpu_bvalid_d        = cpu_bvalid_q                              ;
        cpu_bresp_d         = cpu_bresp_q                               ;
        cpu_rvalid_d        = cpu_rvalid_q                              ;
        cpu_rdata_d         = cpu_rdata_q                               ;
        cpu_rresp_d         = cpu_rresp_q                               ;
        bus_wvalid_d        = bus_wvalid_q                              ;
        bus_awaddr_d        = bus_awaddr_q                              ;
        bus_wdata_d         = bus_wdata_q                               ;
        bus_wstrb_d         = bus_wstrb_q                               ;
        bus_arvalid_d       = bus_arvalid_q                             ;
        bus_araddr_d        = bus_araddr_q                              ;
        state_d             = state_q                                   ;
        case (state_q)
            IDLE        : begin
                if (cpu_arvalid_i) begin
                    is_load_d       = 1'b1                                          ;
                    if ((|cpu_araddr_i[`PLEN-1:24]==1'b1) && cpu_araddr_i[ADDR_WIDTH-1:28] != 'h8) begin  // peripheral access
                        bus_arvalid_d   = 1'b1                                      ;
                        bus_araddr_d    = cpu_araddr_i                              ;
                        state_d         = PERIPH_READ                               ;
                    end else begin                                                  // dram access
                        idx             = cpu_araddr_i[INDEX_MSB:INDEX_LSB]         ;
                        cpu_axaddr_d    = cpu_araddr_i                              ;
                        state_d         = LATENCY                                   ;
                    end
                end else if (cpu_wvalid_i) begin
                    is_store_d      = 1'b1                                          ;
                    if ((|cpu_awaddr_i[`PLEN-1:24]==1'b1) && cpu_awaddr_i[ADDR_WIDTH-1:28] != 'h8) begin  // peripheral access
                        bus_wvalid_d    = 1'b1                                      ;
                        bus_awaddr_d    = cpu_awaddr_i                              ;
                        bus_wdata_d     = cpu_wdata_i                               ;
                        bus_wstrb_d     = cpu_wstrb_i                               ;
                        state_d         = PERIPH_WRITE                              ;
                    end else begin                                                  // dram access
                        idx             = cpu_awaddr_i[INDEX_MSB:INDEX_LSB]         ;
                        cpu_axaddr_d    = cpu_awaddr_i                              ;
                        cpu_wdata_d     = cpu_wdata_i                               ;
                        cpu_wstrb_d     = cpu_wstrb_i                               ;
                        state_d         = CHECK_LOCK                                ;
                    end
                end
            end
            CHECK_LOCK  : begin
                cpu_bresp_d     = `BRESP_OKAY                                   ;
                state_d         = COMPARE_TAG                                   ;
            end
            COMPARE_TAG : begin
                for (i=0; i<N_WAYS; i=i+1) begin
                    hit_d[i]    = rvalid[i] && (cpu_axaddr_q[TAG_MSB:TAG_LSB]==rtag[i]) ;
                end
                state_d         = CHECK_VALID                                       ;
            end
            CHECK_VALID : begin
                if (|hit_q) begin // hit
                    for (i=0; i<N_WAYS; i=i+1) begin
                        if (hit_q[i]) cpu_rdata_d = rdata[i]                        ; // load
                    end
                    cpu_rresp_d     = `RRESP_OKAY                                   ;
                    if (is_store_q) begin // store
                        we_d            = hit_q                                     ;
                        wdirty_d        = 1'b1                                      ;
                        wdata_d         = cpu_wdata_q                               ;
                        wstrb_d         = cpu_wstrb_q                               ;
                        cpu_bvalid_d    = 1'b1                                      ;
                    end else begin // load
                        cpu_rvalid_d    = 1'b1                                      ;
                    end
                    state_d         = RET                                           ;
                end else begin // miss
                    if (rvalid[replace_q] && rdirty[replace_q]) begin // write back
                        bus_wvalid_d    = 1'b1                                          ;
                        bus_awaddr_d    = {rtag[replace_q], cpu_axaddr_q[INDEX_MSB:0]}  ;
                        bus_wdata_d     = rdata[replace_q]                              ;
                        bus_wstrb_d     = {STRB_WIDTH{1'b1}}                            ;
                        state_d         = WRITE_BACK                                    ;
                    end else begin // allocate
                        bus_arvalid_d   = 1'b1                                          ;
                        bus_araddr_d    = cpu_axaddr_q                                  ;
                        state_d         = ALLOCATE                                      ;
                    end
                end
            end
            WRITE_BACK  : begin
                if (bus_wready_i) begin
                    bus_wvalid_d    = 1'b0                                          ;
                end
                if (bus_bvalid_i) begin
                    if (bus_bresp_i==`BRESP_OKAY) begin
                        bus_arvalid_d   = 1'b1                                      ;
                        bus_araddr_d    = cpu_axaddr_q                              ;
                        state_d         = ALLOCATE                                  ;
                    end else begin
                        cpu_bvalid_d    = 1'b1                                      ;
                        cpu_bresp_d     = bus_bresp_i                               ;
                        state_d         = RET                                       ;
                    end
                end
            end
            ALLOCATE    : begin
                if (bus_arready_i) begin
                    bus_arvalid_d   = 1'b0                                          ;
                end
                if (bus_rvalid_i) begin
                    we_d[replace_q] = (bus_rresp_i==`RRESP_OKAY)                    ;
                    wdata_d         = bus_rdata_i                                   ;
                    wstrb_d         = {STRB_WIDTH{1'b1}}                            ;
                    cpu_rdata_d     = bus_rdata_i                                   ; // load
                    cpu_rresp_d     = bus_rresp_i                                   ; // load
                    if (is_store_q && (bus_rresp_i==`RRESP_OKAY)) begin
                        hit_d[replace_q]    = 1'b1                                  ;
                        state_d         = WRITE_CACHE                               ;
                    end else begin // if (is_load_q || (bus_rresp_i!=`RRESP_OKAY))
                        cpu_rvalid_d    = 1'b1                                      ;
                        state_d         = RET                                       ;
                    end
                end
            end
            WRITE_CACHE : begin
                we_d            = hit_q                                                     ;
                wdirty_d        = 1'b1                                                      ;
                wdata_d         = cpu_wdata_q                                               ;
                wstrb_d         = cpu_wstrb_q                                               ;
                cpu_bvalid_d    = 1'b1                                                      ;
                state_d         = RET                                                       ;
            end
            PERIPH_WRITE: begin
                if (bus_wready_i) begin
                    bus_wvalid_d    = 1'b0                                          ;
                end
                if (bus_bvalid_i) begin
                    cpu_bvalid_d    = 1'b1                                          ;
                    cpu_bresp_d     = bus_bresp_i                                   ;
                    state_d         = RET                                           ;
                end
            end
            PERIPH_READ : begin
                if (bus_arready_i) begin
                    bus_arvalid_d   = 1'b0                                          ;
                end
                if (bus_rvalid_i) begin
                    cpu_rvalid_d    = 1'b1                                          ;
                    cpu_rdata_d     = bus_rdata_i                                   ;
                    cpu_rresp_d     = bus_rresp_i                                   ;
                    state_d         = RET                                           ;
                end
            end
            RET         : begin
                if (is_store_q) begin
                    if (cpu_bready_i) begin
                        is_store_d      = 1'b0                                          ;
                        cpu_bvalid_d    = 1'b0                                          ;
                        state_d         = IDLE                                          ;
                    end
                end
                if (is_load_q && cpu_rready_i) begin
                    is_load_d       = 1'b0                                          ;
                    cpu_rvalid_d    = 1'b0                                          ;
                    state_d         = IDLE                                          ;
                end
            end
            LATENCY     : begin
                state_d         = COMPARE_TAG                                       ;
            end
            default     : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            we_q                <= 'h0                  ;
            is_store_q          <= 1'b0                 ;
            is_load_q           <= 1'b0                 ;
            bus_wvalid_q        <= 1'b0                 ;
            bus_arvalid_q       <= 1'b0                 ;
            state_q             <= IDLE                 ;
        end else begin
            hit_q               <= hit_d                ;
            we_q                <= we_d                 ;
            wdirty_q            <= wdirty_d             ;
            wdata_q             <= wdata_d              ;
            wstrb_q             <= wstrb_d              ;
            is_store_q          <= is_store_d           ;
            is_load_q           <= is_load_d            ;
            cpu_axaddr_q        <= cpu_axaddr_d         ;
            cpu_wdata_q         <= cpu_wdata_d          ;
            cpu_wstrb_q         <= cpu_wstrb_d          ;
            cpu_bvalid_q        <= cpu_bvalid_d         ;
            cpu_bresp_q         <= cpu_bresp_d          ;
            cpu_rvalid_q        <= cpu_rvalid_d         ;
            cpu_rdata_q         <= cpu_rdata_d          ;
            cpu_rresp_q         <= cpu_rresp_d          ;
            bus_wvalid_q        <= bus_wvalid_d         ;
            bus_awaddr_q        <= bus_awaddr_d         ;
            bus_wdata_q         <= bus_wdata_d          ;
            bus_wstrb_q         <= bus_wstrb_d          ;
            bus_arvalid_q       <= bus_arvalid_d        ;
            bus_araddr_q        <= bus_araddr_d         ;
            state_q             <= state_d              ;
        end
    end

    // PLRU: pseudo least recently used replacement
    always @(*) begin
        plru_tree_we_d      = 1'b0              ;
        plru_tree_wdata_d   = plru_tree_wdata_q ;
        if (|hit_q) begin
            plru_tree_we_d      = 1'b1              ;
            plru_tree_wdata_d   = plru_tree_rdata   ;
            case (1'b1)
                hit_q[3]: begin plru_tree_wdata_d[0] = 1'b1; plru_tree_wdata_d[2] = 1'b1; end
                hit_q[2]: begin plru_tree_wdata_d[0] = 1'b1; plru_tree_wdata_d[2] = 1'b0; end
                hit_q[1]: begin plru_tree_wdata_d[0] = 1'b0; plru_tree_wdata_d[1] = 1'b1; end
                default : begin plru_tree_wdata_d[0] = 1'b0; plru_tree_wdata_d[1] = 1'b0; end
            endcase
        end
        if (we_q[replace_q]) begin
            plru_tree_we_d      = 1'b1              ;
            plru_tree_wdata_d   = plru_tree_rdata   ;
            case (replace_q)
                'h3     : begin plru_tree_wdata_d[0] = 1'b1; plru_tree_wdata_d[2] = 1'b1; end
                'h2     : begin plru_tree_wdata_d[0] = 1'b1; plru_tree_wdata_d[2] = 1'b0; end
                'h1     : begin plru_tree_wdata_d[0] = 1'b0; plru_tree_wdata_d[1] = 1'b1; end
                default : begin plru_tree_wdata_d[0] = 1'b0; plru_tree_wdata_d[1] = 1'b0; end
            endcase
        end
        replace_d   = (plru_tree_rdata[0]) ? ((plru_tree_rdata[1]) ? 'h0 : 'h1) : ((plru_tree_rdata[2]) ? 'h2 : 'h3);
    end

    always @(posedge clk_i) begin
        plru_tree_we_q      <= plru_tree_we_d       ;
        plru_tree_wdata_q   <= plru_tree_wdata_d    ;
        replace_q           <= replace_d            ;
        plru_tree_rdata     <= plru_tree_ram[idx]   ;
        if (plru_tree_we_q) begin
            plru_tree_ram[idx]  <= plru_tree_wdata_q    ;
        end
    end

    // cache access
    reg   [TAG_WIDTH+1:0] rmeta_pipe_reg [0:N_WAYS-1]   ;
    reg  [DATA_WIDTH-1:0] rdata_pipe_reg [0:N_WAYS-1]   ;
    always @(posedge clk_i) begin
        rmeta_pipe_reg[3]   <= meta_ram3[idx]   ;
        rmeta_pipe_reg[2]   <= meta_ram2[idx]   ;
        rmeta_pipe_reg[1]   <= meta_ram1[idx]   ;
        rmeta_pipe_reg[0]   <= meta_ram0[idx]   ;
        rdata_pipe_reg[3]   <= data_ram3[idx]   ;
        rdata_pipe_reg[2]   <= data_ram2[idx]   ;
        rdata_pipe_reg[1]   <= data_ram1[idx]   ;
        rdata_pipe_reg[0]   <= data_ram0[idx]   ;
        for (i=0; i<N_WAYS; i=i+1) begin
            {rvalid[i], rdirty[i], rtag[i]} <= rmeta_pipe_reg[i];
            rdata[i]                        <= rdata_pipe_reg[i];
        end
        if (we_q[3]) begin
            meta_ram3[idx]      <= {1'b1, wdirty_q, wtag}   ;
            for (i=0; i<STRB_WIDTH; i=i+1) begin
                if (wstrb_q[i]) data_ram3[idx][8*i+:8]  <= wdata_q[8*i+:8]  ;
            end
        end
        if (we_q[2]) begin
            meta_ram2[idx]      <= {1'b1, wdirty_q, wtag}   ;
            for (i=0; i<STRB_WIDTH; i=i+1) begin
                if (wstrb_q[i]) data_ram2[idx][8*i+:8]  <= wdata_q[8*i+:8]  ;
            end
        end
        if (we_q[1]) begin
            meta_ram1[idx]      <= {1'b1, wdirty_q, wtag}   ;
            for (i=0; i<STRB_WIDTH; i=i+1) begin
                if (wstrb_q[i]) data_ram1[idx][8*i+:8]  <= wdata_q[8*i+:8]  ;
            end
        end
        if (we_q[0]) begin
            meta_ram0[idx]      <= {1'b1, wdirty_q, wtag}   ;
            for (i=0; i<STRB_WIDTH; i=i+1) begin
                if (wstrb_q[i]) data_ram0[idx][8*i+:8]  <= wdata_q[8*i+:8]  ;
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall
