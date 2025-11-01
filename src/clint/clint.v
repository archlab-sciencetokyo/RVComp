/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"

/* core local interruptor */
/******************************************************************************************/
module clint #(
    parameter  ADDR_WIDTH               = 0             , // address width
    localparam DATA_WIDTH               = 32            , // data width
    localparam STRB_WIDTH               = DATA_WIDTH/8  , // strobe width
    localparam CLINT_MSIP_OFFSET        = 20'h0         , 
    localparam CLINT_MTIMECMP_OFFSET    = 20'h4000      ,
    localparam CLINT_MTIME_OFFSET       = 20'hbff8
) (
    input  wire                    clk_i        , // clock 
    input  wire                    rst_i        , // reset
    output wire             [63:0] mtime_o      , // machine time
    output wire                    timer_irq_o  , // timer interrupt request
    output wire                    ipi_o        , // inter processor (or software) interrupts
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
        if (ADDR_WIDTH==0 ) $fatal(1, "specify a clint ADDR_WIDTH");
        if (DATA_WIDTH!=32) $fatal(1, "This clint module supports only 32-bit");
    end

    // mswi: machine-level software interrupt device
    reg         msip_q      , msip_d        ; // 0x0000

    assign ipi_o        = msip_q        ;

    // mtimer: machine-level timer device
    reg  [63:0] mtimecmp_q  , mtimecmp_d    ; // 0x4000
    reg  [63:0] mtime_q     , mtime_d       ; // 0xbff8
    reg         timer_irq_q , timer_irq_d   ; // timer interrupt request

    assign mtime_o      = mtime_q       ;
    assign timer_irq_o  = timer_irq_q   ;

    always @(*) begin
        timer_irq_d = 1'b0  ;
        if (mtime_q>=mtimecmp_q) begin
            timer_irq_d = 1'b1  ;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            timer_irq_q <= 1'b0         ;
        end else begin
            timer_irq_q <= timer_irq_d  ;
        end
    end

    // read
    reg                     rvalid_q    , rvalid_d  ;
    reg    [DATA_WIDTH-1:0] rdata_q     , rdata_d   ;
    reg  [`RRESP_WIDTH-1:0] rresp_q     , rresp_d   ;

    assign arready_o    = (!rvalid_o || rready_i)   ;
    assign rvalid_o     = rvalid_q                  ;
    assign rdata_o      = rdata_q                   ;
    assign rresp_o      = rresp_q                   ;

    always @(*) begin
        rvalid_d    = rvalid_q      ;
        rdata_d     = rdata_q       ;
        rresp_d     = rresp_q       ;
        if (arready_o) begin
            rvalid_d    = arvalid_i     ;
            if (arvalid_i) begin
                rresp_d     = `RRESP_OKAY   ;
                case (araddr_i)
                    CLINT_MSIP_OFFSET       : rdata_d   = {31'h00000000, msip_q};
                    CLINT_MTIMECMP_OFFSET   : rdata_d   = mtimecmp_q[31:0]      ;
                    CLINT_MTIMECMP_OFFSET+4 : rdata_d   = mtimecmp_q[63:32]     ;
                    CLINT_MTIME_OFFSET      : rdata_d   = mtime_q[31:0]         ;
                    CLINT_MTIME_OFFSET+4    : rdata_d   = mtime_q[63:32]        ;
                    default                 : rresp_d   = `RRESP_DECERR         ;
                endcase
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rvalid_q    <= 1'b0     ;
        end else begin
            rvalid_q    <= rvalid_d ;
            rdata_q     <= rdata_d  ;
            rresp_q     <= rresp_d  ;
        end
    end

    // write
    reg                     bvalid_q    , bvalid_d  ;
    reg  [`BRESP_WIDTH-1:0] bresp_q     , bresp_d   ;

    assign wready_o     = (!bvalid_o || bready_i)   ;
    assign bvalid_o     = bvalid_q                  ;
    assign bresp_o      = bresp_q                   ;

    always @(*) begin
        msip_d      = msip_q        ;
        mtimecmp_d  = mtimecmp_q    ;
        mtime_d     = mtime_q+'h1   ;
        bvalid_d    = bvalid_q      ;
        bresp_d     = bresp_q       ;
        if (wready_o) begin
            bvalid_d    = wvalid_i      ;
            if (wvalid_i) begin
                if (wstrb_i=={STRB_WIDTH{1'b1}}) begin
                    bresp_d     = `BRESP_OKAY   ;
                    case (awaddr_i)
                        CLINT_MSIP_OFFSET       : msip_d            = wdata_i[0]    ;
                        CLINT_MTIMECMP_OFFSET   : mtimecmp_d[31:0]  = wdata_i       ;
                        CLINT_MTIMECMP_OFFSET+4 : mtimecmp_d[63:32] = wdata_i       ;
                        CLINT_MTIME_OFFSET      : mtime_d[31:0]     = wdata_i       ;
                        CLINT_MTIME_OFFSET+4    : mtime_d[63:32]    = wdata_i       ;
                        default                 : bresp_d           = `BRESP_DECERR ;
                    endcase
                end else begin
                    bresp_d     = `BRESP_SLVERR ;
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            msip_q      <= 1'b0         ;
            mtimecmp_q  <= 64'h0        ;
            mtime_q     <= 64'h0        ;
            bvalid_q    <= 1'b0         ;
        end else begin
            msip_q      <= msip_d       ;
            mtimecmp_q  <= mtimecmp_d   ;
            mtime_q     <= mtime_d      ;
            bvalid_q    <= bvalid_d     ;
            bresp_q     <= bresp_d      ;
        end
    end

endmodule

/******************************************************************************************/
`resetall
