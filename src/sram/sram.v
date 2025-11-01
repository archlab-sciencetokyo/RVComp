/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"

/* static random access memory */
/******************************************************************************************/
module sram #(
    parameter  ADDR_WIDTH       = 0             , // address width
    parameter  DATA_WIDTH       = 0             , // data width
    localparam STRB_WIDTH       = DATA_WIDTH/8    // strobe width
) (
    input  wire                    clk_i        , // clock
    input  wire                    rst_i        , // reset
    input  wire                    wvalid_i     , // write request valid
    output wire                    wready_o     , // write request ready
    input  wire   [ADDR_WIDTH-1:0] awaddr_i     , // write request address
    input  wire                    awlock_i     , // is store conditional
    input  wire   [DATA_WIDTH-1:0] wdata_i      , // write request data
    input  wire   [STRB_WIDTH-1:0] wstrb_i      , // write request strobe
    output wire                    bvalid_o     , // write response valid
    input  wire                    bready_i     , // write response ready
    output wire [`BRESP_WIDTH-1:0] bresp_o      , // write response status
    input  wire                    arvalid_i    , // read request valid
    output wire                    arready_o    , // read request ready
    input  wire   [ADDR_WIDTH-1:0] araddr_i     , // read request address
    input  wire                    arlock_i     , // is load reserved
    output wire                    rvalid_o     , // read response valid
    input  wire                    rready_i     , // read response ready
    output reg    [DATA_WIDTH-1:0] rdata_o      , // read response data
    output wire [`RRESP_WIDTH-1:0] rresp_o        // read response status
);

    // DRC: design rule check
    initial begin
        if (ADDR_WIDTH==0) $fatal(1, "specify a sram ADDR_WIDTH");
        if (DATA_WIDTH==0) $fatal(1, "specify a sram DATA_WIDTH");
    end

    localparam RAM_SIZE         = 32*1024                       ;

    localparam OFFSET_WIDTH     = $clog2(DATA_WIDTH/8)          ;
    localparam VALID_ADDR_WIDTH = $clog2(RAM_SIZE)-OFFSET_WIDTH ;
    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] ram [0:(2**VALID_ADDR_WIDTH)-1] ;

    wire [VALID_ADDR_WIDTH-1:0] valid_awaddr = awaddr_q[$clog2(RAM_SIZE)-1:OFFSET_WIDTH];
    wire [VALID_ADDR_WIDTH-1:0] valid_araddr = araddr_i[$clog2(RAM_SIZE)-1:OFFSET_WIDTH];

    reg                   rsvd_q        , rsvd_d        ;
    reg  [ADDR_WIDTH-1:0] rsvd_addr_q   , rsvd_addr_d   ;

    // write channel
    localparam WR_IDLE = 2'd0, WR_WRITE = 2'd1, WR_RET = 2'd2;
    reg  [1:0] wr_state_q   , wr_state_d    ;

    reg   [ADDR_WIDTH-1:0] awaddr_q     , awaddr_d      ;
    reg                    awlock_q     , awlock_d      ;
    reg   [DATA_WIDTH-1:0] wdata_q      , wdata_d       ;
    reg   [STRB_WIDTH-1:0] wstrb_q      , wstrb_d       ;
    reg                    we_q         , we_d          ;
    reg [`BRESP_WIDTH-1:0] bresp_q      , bresp_d       ;

    assign wready_o     = (wr_state_q==WR_IDLE)         ;
    assign bvalid_o     = (wr_state_q==WR_RET)          ;
    assign bresp_o      = bresp_q                       ;

    // read channel
    reg                    rvalid_q     , rvalid_d      ;

    assign arready_o    = !rvalid_o || rready_i         ;
    assign rvalid_o     = rvalid_q                      ;
    assign rresp_o      = `RRESP_OKAY                   ;

    always @(*) begin
        rsvd_d          = rsvd_q        ;
        rsvd_addr_d     = rsvd_addr_q   ;
        awaddr_d        = awaddr_q      ;
        awlock_d        = 1'b0          ;
        wdata_d         = wdata_q       ;
        wstrb_d         = wstrb_q       ;
        we_d            = 1'b0          ;
        bresp_d         = bresp_q       ;
        rvalid_d        = rvalid_q      ;
        wr_state_d      = wr_state_q    ;
        case (wr_state_q)
            WR_IDLE : begin
                if (wvalid_i) begin
                    awaddr_d        = awaddr_i          ;
                    awlock_d        = awlock_i          ;
                    wdata_d         = wdata_i           ;
                    wstrb_d         = wstrb_i           ;
                    wr_state_d      = WR_WRITE          ;
                end
            end
            WR_WRITE: begin
                if (awaddr_q[ADDR_WIDTH-1:OFFSET_WIDTH]==rsvd_addr_q[ADDR_WIDTH-1:OFFSET_WIDTH]) begin
                    rsvd_d          = 1'b0              ;
                end
                if (awlock_q) begin
                    rsvd_d          = 1'b0              ;
                    if (rsvd_q && (awaddr_q[ADDR_WIDTH-1:OFFSET_WIDTH]==rsvd_addr_q[ADDR_WIDTH-1:OFFSET_WIDTH])) begin
                        we_d            = 1'b1              ;
                        bresp_d         = `BRESP_EXOKAY     ;
                    end else begin
                        bresp_d         = `BRESP_OKAY       ;
                    end
                end else begin
                    we_d            = 1'b1              ;
                    bresp_d         = `BRESP_OKAY       ;
                end
                wr_state_d      = WR_RET            ;
            end
            WR_RET  : begin
                if (bready_i) begin
                    wr_state_d      = WR_IDLE           ;
                end
            end
            default : ;
        endcase
        if (arready_o) begin
            rvalid_d        = arvalid_i         ;
            if (arvalid_i) begin
                if (arlock_i) begin
                    rsvd_d          = 1'b1              ;
                    rsvd_addr_d     = araddr_i          ;
                end
            end
        end
    end

    integer i;
    always @(posedge clk_i) begin
        if (rst_i) begin
            rsvd_q          <= 1'b0                 ;
            awlock_q        <= 1'b0                 ;
            we_q            <= 1'b0                 ;
            wr_state_q      <= WR_IDLE              ;
        end else begin
            rsvd_q          <= rsvd_d               ;
            rsvd_addr_q     <= rsvd_addr_d          ;
            awaddr_q        <= awaddr_d             ;
            awlock_q        <= awlock_d             ;
            wdata_q         <= wdata_d              ;
            wstrb_q         <= wstrb_d              ;
            we_q            <= we_d                 ;
            bresp_q         <= bresp_d              ;
            rvalid_q        <= rvalid_d             ;
            wr_state_q      <= wr_state_d           ;
        end
        // memory access
        if (arvalid_i && arready_o) begin
            rdata_o <= ram[valid_araddr];
        end
        if (we_q) begin
            for (i=0; i<STRB_WIDTH; i=i+1) begin
                if (wstrb_q[i]) ram[valid_awaddr][8*i+:8] <= wdata_q[8*i+:8];
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall
