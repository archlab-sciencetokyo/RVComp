/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"

/* plic: platform-level interrupt controller */
/******************************************************************************************/
module plic #(
    parameter  ADDR_WIDTH       = 0                     ,
    localparam DATA_WIDTH       = 32                    ,
    localparam STRB_WIDTH       = DATA_WIDTH/8          ,
    parameter  NUM_SRCS         = 3                     , // interrupt source 0 is reserved (it does not exist)
    parameter  NUM_CTXS         = 2                     , // number of hart contexts (a hart context is a given privilege mode on a given hart)
    parameter  MAX_PRIORITY     = 15                    , // (> 0)
    localparam PRIORITY_WIDTH   = $clog2(MAX_PRIORITY+1),
    localparam PRIORITY_BASE    = 'h0                   ,
    localparam PENDING_BASE     = 'h1000                ,
    localparam ENABLE_BASE      = 'h2000                ,
    localparam ENABLE_SIZE      = 'h80                  ,
    localparam CONTEXT_BASE     = 'h200000              ,
    localparam CONTEXT_SIZE     = 'h1000
) (
    input  wire                    clk_i        , // clock
    input  wire                    rst_i        , // reset
    input  wire     [NUM_SRCS-1:0] src_irq_i    , // source's interrupt request. interrupt source 0 is reserved (it does not exist)
    output wire     [NUM_CTXS-1:0] irq_o        , // external interrupt request
    input  wire                    wvalid_i     , // write request valid
    output wire                    wready_o     , // write request ready
    input  wire   [ADDR_WIDTH-1:0] awaddr_i     , // write request address
    input  wire   [DATA_WIDTH-1:0] wdata_i      , // write request data
    input  wire   [STRB_WIDTH-1:0] wstrb_i      , // write request strobe
    output wire                    bvalid_o     , // write response valid
    input  wire                    bready_i     , // write response ready
    output wire [`BRESP_WIDTH-1:0] bresp_o      , // write response status
    input  wire                    arvalid_i    , // read request valid
    output wire                    arready_o    , // read request ready
    input  wire   [ADDR_WIDTH-1:0] araddr_i     , // read request address
    output wire                    rvalid_o     , // read response valid
    input  wire                    rready_i     , // read response ready
    output wire   [DATA_WIDTH-1:0] rdata_o      , // read response data
    output wire [`RRESP_WIDTH-1:0] rresp_o        // read response status
);

    // DRC: design rule check
    initial begin
        if (ADDR_WIDTH  ==0 ) $fatal(1, "specify a plic ADDR_WIDTH");
        if (DATA_WIDTH  !=32) $fatal(1, "plic DATA_WIDTH is assumed to be 32-bit");
        if (NUM_SRCS    < 2 ) $fatal(1, "number of interrupt sources must be at least 2");
        if (NUM_CTXS    !=2 ) $fatal(1, "number of interrupt contexts must be 2");
        if (MAX_PRIORITY<=0 ) $fatal(1, "maximum priority value must be greater than 0");
    end

    // loop index
    integer i, j    ;
    genvar  gi, gj  ;

    // plic gateway registers
    // wait-for-low state avoids re-pending level-triggered IRQs until source deasserts
    localparam IDLE = 2'd0, BUSY = 2'd1, WAIT_LOW = 2'd2;
    reg  [1:0] gw_state_q [0:NUM_SRCS-1], gw_state_d [0:NUM_SRCS-1] ;
    reg  [0:0] src_irq_q [0:NUM_SRCS-1] , src_irq_d [0:NUM_SRCS-1]  ; // source interrupt request

    // plic core registers
    reg  [PRIORITY_WIDTH-1:0] priority_q [0:NUM_SRCS-1] , priority_d [0:NUM_SRCS-1] ; // interrupt source priority
    reg        [NUM_SRCS-1:0] pending_q                 , pending_d                 ; // interrupt source pending bits
    reg        [NUM_SRCS-1:0] enable_q [0:NUM_CTXS-1]   , enable_d [0:NUM_CTXS-1]   ; // interrupt source enable bits on context
    reg  [PRIORITY_WIDTH-1:0] threshold_q [0:NUM_CTXS-1], threshold_d [0:NUM_CTXS-1]; // priority threshold for context
    reg                [31:0] claim_q [0:NUM_CTXS-1]    , claim_d [0:NUM_CTXS-1]    ; // interrupt claim process for context
    reg                [31:0] complete_q [0:NUM_CTXS-1] , complete_d [0:NUM_CTXS-1] ; // interrupt completion for context
    reg                 [0:0] eip_q [0:NUM_CTXS-1]      , eip_d [0:NUM_CTXS-1]      ; // external interrupt pending

    generate
        for (gi=0; gi<NUM_CTXS; gi=gi+1) begin
            assign irq_o[gi] = eip_q[gi]  ;
        end
    endgenerate

    // plic gateway

    // NOTE: interrupt source 0 is reserved (it does not exist)
    always @(posedge clk_i) begin
        src_irq_q[0]    <= 1'b0         ;
        gw_state_q[0]   <= IDLE         ;
    end

    generate
        for (gi=1; gi<NUM_SRCS; gi=gi+1) begin
            always @(*) begin
                src_irq_d[gi]    = 1'b0         ;
                gw_state_d[gi]   = gw_state_q[gi];
                case (gw_state_q[gi])
                    IDLE    : begin
                        if (src_irq_i[gi]) begin
                            src_irq_d[gi]    = 1'b1          ;
                            gw_state_d[gi]   = BUSY          ;
                        end
                    end
                    BUSY    : begin
                        for (j=0; j<NUM_CTXS; j=j+1) begin
                            if ((complete_q[j]==gi) && enable_q[j][gi]) begin
                                // stay armed until source deasserts to avoid immediate re-pending
                                gw_state_d[gi]   = src_irq_i[gi] ? WAIT_LOW : IDLE;
                            end
                        end
                    end
                    WAIT_LOW: begin
                        if (!src_irq_i[gi]) begin
                            gw_state_d[gi]   = IDLE          ;
                        end
                    end
                    default : ;
                endcase
            end

            always @(posedge clk_i) begin
                if (rst_i) begin
                    src_irq_q[gi]    <= 1'b0         ;
                    gw_state_q[gi]   <= IDLE         ;
                end else begin
                    src_irq_q[gi]    <= src_irq_d[gi] ;
                    gw_state_q[gi]   <= gw_state_d[gi];
                end
            end
        end
    endgenerate

    // plic core
    reg                     rvalid_q    , rvalid_d  ;
    reg    [DATA_WIDTH-1:0] rdata_q     , rdata_d   ;
    reg  [`RRESP_WIDTH-1:0] rresp_q     , rresp_d   ;
    reg                     bvalid_q    , bvalid_d  ;
    reg  [`BRESP_WIDTH-1:0] bresp_q     , bresp_d   ;

    assign arready_o    = (!rvalid_q || rready_i)   ;
    assign rvalid_o     = rvalid_q                  ;
    assign rdata_o      = rdata_q                   ;
    assign rresp_o      = rresp_q                   ;
    assign wready_o     = (!bvalid_q || bready_i)   ;
    assign bvalid_o     = bvalid_q                  ;
    assign bresp_o      = bresp_q                   ;

    reg      [PRIORITY_WIDTH-1:0] max_priority [0:NUM_CTXS-1]   ;
    reg  [$clog2(NUM_SRCS+1)-1:0] max_id [0:NUM_CTXS-1]         ;

    always @(*) begin
        for (i=1; i<NUM_SRCS; i=i+1) begin
            priority_d[i]   = priority_q[i]     ;
        end
        pending_d       = pending_q         ;
        for (j=0; j<NUM_CTXS; j=j+1) begin
            enable_d[j]     = enable_q[j]       ;
            threshold_d[j]  = threshold_q[j]    ;
            claim_d[j]      = claim_q[j]        ;
            complete_d[j]   = complete_q[j]     ;
            eip_d[j]        = eip_q[j]          ;
        end
        rvalid_d        = rvalid_q          ;
        rdata_d         = rdata_q           ;
        rresp_d         = rresp_q           ;
        bvalid_d        = bvalid_q          ;
        bresp_d         = bresp_q           ;
        if (arready_o) begin
            rvalid_d        = arvalid_i         ;
            if (arvalid_i) begin
                rresp_d         = `RRESP_OKAY       ;
                case (araddr_i)
                    PRIORITY_BASE                   : rdata_d   = 'h0                                       ; // interrupt source 0 is reserved (it does not exist)
                    PRIORITY_BASE+4                 : rdata_d   = {{(32-PRIORITY_WIDTH){1'b0}}, priority_q[1]};
                    PRIORITY_BASE+8                 : rdata_d   = {{(32-PRIORITY_WIDTH){1'b0}}, priority_q[2]};
                    PENDING_BASE                    : rdata_d   = {{(32-NUM_SRCS){1'b0}}, pending_q}        ;
                    ENABLE_BASE+(ENABLE_SIZE)*0     : rdata_d   = {{32-NUM_SRCS{1'b0}}, enable_q[0]}        ;
                    ENABLE_BASE+(ENABLE_SIZE)*1     : rdata_d   = {{32-NUM_SRCS{1'b0}}, enable_q[1]}        ;
                    CONTEXT_BASE+(CONTEXT_SIZE*0)   : rdata_d   = threshold_q[0]                            ;
                    CONTEXT_BASE+(CONTEXT_SIZE*0)+4 : begin
                        rdata_d                                 = claim_q[0]                                ;
                        if (enable_q[0][claim_q[0][$clog2(NUM_SRCS+1)-1:0]]) begin
                            pending_d[claim_q[0][$clog2(NUM_SRCS+1)-1:0]]   = 1'b0                          ;
                        end
                    end
                    CONTEXT_BASE+(CONTEXT_SIZE*1)   : rdata_d   = threshold_q[1]                            ;
                    CONTEXT_BASE+(CONTEXT_SIZE*1)+4 : begin
                        rdata_d                                 = claim_q[1]                                ;
                        if (enable_q[1][claim_q[1][$clog2(NUM_SRCS+1)-1:0]]) begin
                            pending_d[claim_q[1][$clog2(NUM_SRCS+1)-1:0]]   = 1'b0                          ;
                        end
                    end
                    default                         : rresp_d   = `RRESP_DECERR                             ;
                endcase
            end
        end
        if (wready_o) begin
            bvalid_d        = wvalid_i          ;
            if (wvalid_i) begin
                if (wstrb_i==4'b1111) begin
                    bresp_d         = `BRESP_OKAY       ;
                    case (awaddr_i)
                        PRIORITY_BASE                   :                                                       ; // interrupt source 0 is reserved (it does not exist)
                        PRIORITY_BASE+4                 : priority_d[1]     = wdata_i[PRIORITY_WIDTH-1:0]       ;
                        PRIORITY_BASE+8                 : priority_d[2]     = wdata_i[PRIORITY_WIDTH-1:0]       ;
                        PENDING_BASE                    : pending_d         = {wdata_i[NUM_SRCS-1:1], 1'b0}     ; // interrupt source 0 is reserved (it does not exist)
                        ENABLE_BASE+(ENABLE_SIZE*0)     : enable_d[0]       = {wdata_i[NUM_SRCS-1:1], 1'b0}     ; // interrupt source 0 is reserved (it does not exist)
                        ENABLE_BASE+(ENABLE_SIZE*1)     : enable_d[1]       = {wdata_i[NUM_SRCS-1:1], 1'b0}     ; // interrupt source 0 is reserved (it does not exist)
                        CONTEXT_BASE+(CONTEXT_SIZE*0)   : threshold_d[0]    = wdata_i[PRIORITY_WIDTH-1:0]       ;
                        CONTEXT_BASE+(CONTEXT_SIZE*0)+4 : complete_d[0]     = wdata_i                           ;
                        CONTEXT_BASE+(CONTEXT_SIZE*1)   : threshold_d[1]    = wdata_i[PRIORITY_WIDTH-1:0]       ;
                        CONTEXT_BASE+(CONTEXT_SIZE*1)+4 : complete_d[1]     = wdata_i                           ;
                        default                         : bresp_d           = `BRESP_DECERR                     ;
                    endcase
                end else begin
                    bresp_d         = `BRESP_SLVERR     ;
                end
            end
        end
        for (i=1; i<NUM_SRCS; i=i+1) begin
            if (src_irq_q[i]) begin
                pending_d[i]    = 1'b1          ;
            end
        end
        for (j=0; j<NUM_CTXS; j=j+1) begin
            max_priority[j] = 'h0           ;
            max_id[j]       = 'h0           ;
            for (i=1; i<NUM_SRCS; i=i+1) begin
                if (pending_q[i] && enable_q[j][i]) begin
                    if (priority_q[i] > max_priority[j]) begin // if prio(x)==prio(y) && id(x)<id(y), max_id = id(x)
                        max_priority[j] = priority_q[i] ;
                        max_id[j]       = i             ;
                    end
                end
            end
            claim_d[j]      = max_id[j]                         ;
            eip_d[j]        = max_priority[j] > threshold_q[j]  ;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i=1; i<NUM_SRCS; i=i+1) begin
                priority_q[i]   <= 'h0              ;
            end
            pending_q       <= 'h0              ;
            for (j=0; j<NUM_CTXS; j=j+1) begin
                enable_q[j]     <= 'h0              ;
                threshold_q[j]  <= 'h0              ;
                claim_q[j]      <= 'h0              ;
                complete_q[j]   <= 'h0              ;
                eip_q[j]        <= 'h0              ;
            end
            rvalid_q        <= 1'b0             ;
            bvalid_q        <= 1'b0             ;
            bresp_q         <= 'h0              ;
        end else begin
            for (i=1; i<NUM_SRCS; i=i+1) begin
                priority_q[i]   <= priority_d[i]    ;
            end
            pending_q       <= pending_d        ;
            for (j=0; j<NUM_CTXS; j=j+1) begin
                enable_q[j]     <= enable_d[j]      ;
                threshold_q[j]  <= threshold_d[j]   ;
                claim_q[j]      <= claim_d[j]       ;
                complete_q[j]   <= complete_d[j]    ;
                eip_q[j]        <= eip_d[j]         ;
            end
            rvalid_q        <= rvalid_d         ;
            rdata_q         <= rdata_d          ;
            rresp_q         <= rresp_d          ;
            bvalid_q        <= bvalid_d         ;
            bresp_q         <= bresp_d          ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
