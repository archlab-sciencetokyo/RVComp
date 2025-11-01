/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`resetall
`default_nettype none

`include "axi.vh"

/* universal asynchronous receiver transmitter (UART) */
/******************************************************************************************/
module uart #(
    parameter  CLK_FREQ_MHZ     = 0             , // clock frequency [MHz]
    parameter  BAUD_RATE        = 0             , // baud rate [bps]
    parameter  DETECT_COUNT     = 0             , // detection count + 1 (start bit detect)
    parameter  FIFO_DEPTH       = 0             , // fifo depth
    parameter  ADDR_WIDTH       = 0             , // address width
    parameter  DATA_WIDTH       = 0             , // data width
    localparam STRB_WIDTH       = (DATA_WIDTH/8)  // strobe width
) (
    input  wire                    clk_i        , // clock
    input  wire                    rst_i        , // reset
    input  wire                    rxd_i        , // receive data (uart pin)
    output wire                    txd_o        , // transmit data (uart pin)
    output wire                    irq_o        , // interrupt request
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
        if (CLK_FREQ_MHZ==0) $fatal(1, "specify a uart CLK_FREQ_MHZ");
        if (BAUD_RATE   ==0) $fatal(1, "specify a uart BAUD_RATE");
        if (DETECT_COUNT==0) $fatal(1, "specify a uart DETECT_COUNT");
        if (FIFO_DEPTH  ==0) $fatal(1, "specify a uart FIFO_DEPTH");
        if (ADDR_WIDTH  ==0) $fatal(1, "specify a uart ADDR_WIDTH");
        if (DATA_WIDTH  ==0) $fatal(1, "specify a uart DATA_WIDTH");
    end

    // offset of uart registers
    localparam RXTX_OFFSET      = 'h0;
    localparam TXFULL_OFFSET    = 'h4;
    localparam RXEMPTY_OFFSET   = 'h8;

    // uart registers
    wire [7:0] rx_rdata                     ;
    reg  [7:0] tx_wdata_q   , tx_wdata_d    ;
    wire       tx_full                      ;
    wire       rx_empty                     ;

    assign irq_o        = !rx_empty  ;

    // read
    localparam RD_IDLE = 1'd0, RD_WAIT = 1'd1;
    reg [0:0] rd_state_q, rd_state_d;

    wire                    rx_rvalid                   ;
    wire                    rx_rready                   ;
    reg                     rvalid_q    , rvalid_d      ;
    reg    [DATA_WIDTH-1:0] rdata_q     , rdata_d       ;
    reg  [`RRESP_WIDTH-1:0] rresp_q     , rresp_d       ;

    assign rx_rvalid    = (rd_state_q==RD_WAIT)             ;
    wire   arready      = (!rvalid_o || rready_i)           ;
    assign arready_o    = (rd_state_q==RD_IDLE) && arready  ;
    assign rvalid_o     = rvalid_q                          ;
    assign rdata_o      = rdata_q                           ;
    assign rresp_o      = rresp_q                           ;

    always @(*) begin
        rvalid_d    = rvalid_q      ;
        rdata_d     = rdata_q       ;
        rresp_d     = rresp_q       ;
        rd_state_d  = rd_state_q    ;
        case (rd_state_q)
            RD_IDLE : begin
                if (arready) begin
                    rvalid_d    = arvalid_i     ;
                    if (arvalid_i) begin
                        rresp_d     = `RRESP_OKAY   ;
                        case (araddr_i)
                            RXTX_OFFSET     : begin
                                rvalid_d    = 1'b0                                              ;
                                rd_state_d  = RD_WAIT                                           ;
                            end
                            TXFULL_OFFSET   : rdata_d   = {{(DATA_WIDTH-1){1'b0}}, tx_full}     ;
                            RXEMPTY_OFFSET  : rdata_d   = {{(DATA_WIDTH-1){1'b0}}, rx_empty}    ;
                            default         : rresp_d   = `RRESP_DECERR                         ;
                        endcase
                    end
                end
            end
            RD_WAIT : begin
                if (rx_rready) begin
                    rvalid_d    = 1'b1          ;
                    rdata_d     = rx_rdata      ;
                    rd_state_d  = RD_IDLE       ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rvalid_q    <= 1'b0         ;
            rd_state_q  <= RD_IDLE      ;
        end else begin
            rvalid_q    <= rvalid_d     ;
            rdata_q     <= rdata_d      ;
            rresp_q     <= rresp_d      ;
            rd_state_q  <= rd_state_d   ;
        end
    end

    // write
    localparam WR_IDLE = 1'd0, WR_WAIT = 1'd1;
    reg [0:0] wr_state_q, wr_state_d;

    wire                    tx_wvalid                   ;
    wire                    tx_wready                   ;
    reg                     bvalid_q    , bvalid_d      ;
    reg  [`BRESP_WIDTH-1:0] bresp_q     , bresp_d       ;

    assign tx_wvalid    = (wr_state_q==WR_WAIT)             ;
    wire   wready       = (!bvalid_o || bready_i)           ;
    assign wready_o     = (wr_state_q==WR_IDLE) && wready   ;
    assign bvalid_o     = bvalid_q                          ;
    assign bresp_o      = bresp_q                           ;

    always @(*) begin
        tx_wdata_d      = tx_wdata_q    ;
        bvalid_d        = bvalid_q      ;
        bresp_d         = bresp_q       ;
        wr_state_d      = wr_state_q    ;
        case (wr_state_q)
            WR_IDLE : begin
                if (wready_o) begin
                    bvalid_d    = wvalid_i      ;
                    if (wvalid_i) begin
                        bresp_d     = `BRESP_OKAY   ;
                        if (wstrb_i=='b0001) begin
                            case (awaddr_i)
                                RXTX_OFFSET     : begin
                                    bvalid_d    = 1'b0                          ;
                                    tx_wdata_d  = wdata_i[7:0]                  ;
                                    wr_state_d  = WR_WAIT                       ;
                                end
                                TXFULL_OFFSET   : bresp_d       = `BRESP_SLVERR ;
                                RXEMPTY_OFFSET  : bresp_d       = `BRESP_SLVERR ;
                                default         : bresp_d       = `BRESP_DECERR ;
                            endcase
                        end else begin
                            bresp_d = `BRESP_SLVERR ;
                        end
                    end
                end
            end
            WR_WAIT: begin
                if (tx_wready) begin
                    bvalid_d    = 1'b1          ;
                    wr_state_d  = WR_IDLE       ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            bvalid_q        <= 1'b0         ;
            wr_state_q      <= WR_IDLE      ;
        end else begin
            tx_wdata_q      <= tx_wdata_d   ;
            bvalid_q        <= bvalid_d     ;
            bresp_q         <= bresp_d      ;
            wr_state_q      <= wr_state_d   ;
        end
    end

    // uart

    // uart receiver
    wire       uart_rvalid      ;
    wire       rx_fifo_wready   ;
    wire [7:0] uart_rdata       ;

    uart_rx #(
        .CLK_FREQ_MHZ   (CLK_FREQ_MHZ   ),
        .BAUD_RATE      (BAUD_RATE      ),
        .DETECT_COUNT   (DETECT_COUNT   )
    ) uart_rx (
        .clk_i          (clk_i          ),
        .rst_i          (rst_i          ),
        .rxd_i          (rxd_i          ),
        .rvalid_o       (uart_rvalid    ),
        .rready_i       (rx_fifo_wready ),
        .rdata_o        (uart_rdata     )
    );

    // fifo for uart receiver
    fifo #(
        .DATA_WIDTH     (8              ),
        .FIFO_DEPTH     (FIFO_DEPTH     )
    ) rx_fifo (
        .clk_i          (clk_i          ),
        .rst_i          (rst_i          ),
        .full_o         (               ),
        .empty_o        (rx_empty       ),
        .wvalid_i       (uart_rvalid    ),
        .wready_o       (rx_fifo_wready ),
        .wdata_i        (uart_rdata     ),
        .rvalid_i       (rx_rvalid      ),
        .rready_o       (rx_rready      ),
        .rdata_o        (rx_rdata       )
    );

    // fifo for uart transmitter
    wire       tx_fifo_rready   ;
    wire       uart_wready      ;
    wire [7:0] tx_fifo_rdata    ;

    fifo #(
        .DATA_WIDTH     (8              ),
        .FIFO_DEPTH     (FIFO_DEPTH     )
    ) tx_fifo (
        .clk_i          (clk_i          ),
        .rst_i          (rst_i          ),
        .full_o         (tx_full        ),
        .empty_o        (               ),
        .wvalid_i       (tx_wvalid      ),
        .wready_o       (tx_wready      ),
        .wdata_i        (tx_wdata_q     ),
        .rvalid_i       (uart_wready    ),
        .rready_o       (tx_fifo_rready ),
        .rdata_o        (tx_fifo_rdata  )
    );

    // uart transmitter
    uart_tx #(
        .CLK_FREQ_MHZ   (CLK_FREQ_MHZ   ),
        .BAUD_RATE      (BAUD_RATE      )
    ) uart_tx (
        .clk_i          (clk_i          ),
        .rst_i          (rst_i          ),
        .txd_o          (txd_o          ),
        .wvalid_i       (tx_fifo_rready ),
        .wready_o       (uart_wready    ),
        .wdata_i        (tx_fifo_rdata  )
    );

endmodule
/******************************************************************************************/

`resetall
