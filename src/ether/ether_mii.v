/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"
`include "axi.vh"

/* ethernet wrapper with AXI interface (MII)
 *
 * Memory map:
 *   0x14000000-0x14003fff : CSR
 *   0x18000000-(0x18000000 + RX size - 1) : RX buffer
 *   0x1c000000-(0x1c000000 + TX size - 1) : TX buffer
 */
/******************************************************************************************/
module ether_mii #(
    parameter  ADDR_WIDTH = `ETHER_ADDR_WIDTH,
    parameter  DATA_WIDTH = `ETHER_DATA_WIDTH
) (
    input  wire                     clk_i          ,
    input  wire                     rx_clk_i       ,
    input  wire                     tx_clk_i       ,
    input  wire                     rst_i          ,
    input  wire                     wvalid_i       ,
    output wire                     wready_o       ,
    input  wire  [ADDR_WIDTH-1:0]   awaddr_i       ,
    input  wire  [DATA_WIDTH-1:0]   wdata_i        ,
    input  wire  [DATA_WIDTH/8-1:0] wstrb_i        ,
    output wire                     bvalid_o       ,
    input  wire                     bready_i       ,
    output wire  [`BRESP_WIDTH-1:0] bresp_o        ,
    input  wire                     arvalid_i      ,
    output wire                     arready_o      ,
    input  wire  [ADDR_WIDTH-1:0]   araddr_i       ,
    output wire                     rvalid_o       ,
    input  wire                     rready_i       ,
    output wire  [DATA_WIDTH-1:0]   rdata_o        ,
    output wire  [`RRESP_WIDTH-1:0] rresp_o        ,
    output wire                     irq_o          ,
    // Ethernet PHY interface (MII)
    output wire                     mdc_o          ,
    inout  wire                     mdio_io        ,
    output wire                     rstn_o         ,
    input  wire                     rx_dv_i        ,
    input  wire                     rxerr_i        ,
    input  wire                [3:0] rxd_i         ,
    output wire                     txen_o         ,
    output wire                [3:0] txd_o
);

    localparam STRB_WIDTH            = DATA_WIDTH/8;
    localparam RX_BUFFER_ADDR_WIDTH  = $clog2(`ETHER_RXBUF_SIZE/4);
    localparam TX_BUFFER_ADDR_WIDTH  = $clog2(`ETHER_TXBUF_SIZE/4);

    localparam RECEIVE_ADDR_START = 'h0;
    localparam RECEIVE_ADDR_END   = 'h1;
    localparam RECEIVE_READ_BYTE  = 'h2;
    localparam RECEIVE_ERR        = 'h3;
    localparam TX_BUSY          = 'h4;
    localparam TX_BUFFER_START  = 'h5;
    localparam TX_BUFFER_END    = 'h6;

    localparam RD_IDLE            = 2'd0;
    localparam RD_SDP             = 2'd1;
    localparam RD_RET             = 2'd2;

    localparam WR_IDLE            = 2'd0;
    localparam WR_CSR             = 2'd1;
    localparam WR_SDP             = 2'd2;
    localparam WR_RET             = 2'd3;

    // Hold PHY reset for 10ms using system clock (avoid RX/TX-clock deadlock).
    localparam integer RST_WAIT_CYCLES = (`CLK_FREQ_MHZ*1000*10);
    localparam integer RST_WAIT_WIDTH  = $clog2(RST_WAIT_CYCLES);
    localparam integer RST_WAIT_MAX    = RST_WAIT_CYCLES-1;

    reg [RST_WAIT_WIDTH-1:0] rst_wait;

    // DRC: design rule check
    initial begin
        if (DATA_WIDTH!=32) $fatal(1, "ether_mii supports only DATA_WIDTH=32");
        if (ADDR_WIDTH<16) $fatal(1, "ether_mii requires ADDR_WIDTH >= 16");
        if (RST_WAIT_CYCLES<=0) $fatal(1, "ether_mii requires RST_WAIT_CYCLES > 0");
    end

    // NOTE: MDIO is reserved for future use in this wrapper.
    assign mdio_io = 1'bz;
    assign mdc_o   = 1'b0;
    assign rstn_o  = (rst_wait==RST_WAIT_MAX[RST_WAIT_WIDTH-1:0]);

    always @(posedge clk_i) begin
        if (rst_i) begin
            rst_wait <= {RST_WAIT_WIDTH{1'b0}};
        end else if (rst_wait!=RST_WAIT_MAX[RST_WAIT_WIDTH-1:0]) begin
            rst_wait <= rst_wait+'h1;
        end
    end

    // ------------------------------------------------------------------------
    // Read path
    // ------------------------------------------------------------------------
    reg [1:0]              rd_state_q       , rd_state_d        ;
    reg [DATA_WIDTH-1:0]   rdata_q          , rdata_d           ;
    reg [ADDR_WIDTH-1:0]   araddr_q         , araddr_d          ;
    reg                    rvalid_q         , rvalid_d          ;
    reg [`RRESP_WIDTH-1:0] rresp_q          , rresp_d           ;
    reg                    rxbuf_valid_q    , rxbuf_valid_d     ;

    wire [DATA_WIDTH-1:0]  rxbuf_data;

    assign arready_o = (rd_state_q==RD_IDLE);
    assign rvalid_o  = rvalid_q;
    assign rdata_o   = rdata_q;
    assign rresp_o   = rresp_q;

    // CSR register bank
    reg [31:0] csr_q [0:7];
    reg [31:0] csr_d [0:7];

    always @(*) begin
        rd_state_d      = rd_state_q;
        araddr_d        = araddr_q;
        rdata_d         = rdata_q;
        rvalid_d        = rvalid_q;
        rresp_d         = rresp_q;
        rxbuf_valid_d   = rxbuf_valid_q;

        case (rd_state_q)
            RD_IDLE: begin
                if (arvalid_i) begin
                    araddr_d    = araddr_i;
                    rd_state_d  = RD_RET;
                    case (araddr_i[31:28])
                        'h1: begin
                            case (araddr_i[27:26])
                                2'b01: begin
                                    case (araddr_i[4:2])
                                        RECEIVE_ADDR_START,
                                        RECEIVE_ADDR_END,
                                        RECEIVE_ERR,
                                        TX_BUSY,
                                        TX_BUFFER_START,
                                        TX_BUFFER_END: begin
                                            rdata_d  = csr_q[araddr_i[4:2]];
                                            rvalid_d = 1'b1;
                                            rresp_d  = `RRESP_OKAY;
                                        end
                                        default: begin
                                            rdata_d  = 32'h0;
                                            rvalid_d = 1'b1;
                                            rresp_d  = `RRESP_SLVERR;
                                        end
                                    endcase
                                end
                                2'b10: begin
                                    rxbuf_valid_d = 1'b1;
                                    rd_state_d    = RD_SDP;
                                end
                                default: begin
                                    rvalid_d = 1'b1;
                                    rresp_d  = `RRESP_SLVERR;
                                end
                            endcase
                        end
                        default: begin
                            rvalid_d = 1'b1;
                            rresp_d  = `RRESP_SLVERR;
                        end
                    endcase
                end
            end
            RD_SDP: begin
                rxbuf_valid_d = 1'b0;
                rvalid_d      = 1'b1;
                rdata_d       = rxbuf_data;
                rresp_d       = `RRESP_OKAY;
                rd_state_d    = RD_RET;
            end
            RD_RET: begin
                if (rready_i) begin
                    rd_state_d = RD_IDLE;
                    rvalid_d   = 1'b0;
                end
            end
            default: ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            rd_state_q    <= RD_IDLE;
            araddr_q      <= {ADDR_WIDTH{1'b0}};
            rdata_q       <= {DATA_WIDTH{1'b0}};
            rvalid_q      <= 1'b0;
            rresp_q       <= `RRESP_OKAY;
            rxbuf_valid_q <= 1'b0;
        end else begin
            rd_state_q    <= rd_state_d;
            araddr_q      <= araddr_d;
            rdata_q       <= rdata_d;
            rvalid_q      <= rvalid_d;
            rresp_q       <= rresp_d;
            rxbuf_valid_q <= rxbuf_valid_d;
        end
    end

    // RX buffer RAM (MII RX clock -> CPU clock)
    wire                           rx_data_valid;
    wire       [STRB_WIDTH-1:0]    rx_data_strobe;
    wire [RX_BUFFER_ADDR_WIDTH-1:0]   rx_addr;
    wire       [DATA_WIDTH-1:0]    rx_data;

    sdp_2clk #(
        .NUM_COL         (STRB_WIDTH),
        .COL_WIDTH       (8),
        .RAM_WIDTH       (DATA_WIDTH),
        .RAM_DEPTH       (`ETHER_RXBUF_SIZE/4),
        .RAM_PERFORMANCE ("LOW_LATENCY"),
        .INIT_FILE       ("")
    ) receive_buffer (
        // ether RX
        .clka            (rx_clk_i),
        .ena             (rx_data_valid),
        .wea             (rx_data_strobe),
        .addra           (rx_addr),
        .dina            (rx_data),
        // cpu
        .addrb           (araddr_d[RX_BUFFER_ADDR_WIDTH+1:2]),
        .enb             (rxbuf_valid_d),
        .clkb            (clk_i),
        .rstb            (rst_i),
        .regceb          (1'b0),
        .doutb           (rxbuf_data)
    );

    // ------------------------------------------------------------------------
    // Write path
    // ------------------------------------------------------------------------
    reg                         [1:0] wr_state_q         , wr_state_d          ;
    reg [TX_BUFFER_ADDR_WIDTH-1:0] txbuf_awaddr_q        , txbuf_awaddr_d      ;
    reg         [DATA_WIDTH-1:0] txbuf_wdata_q        , txbuf_wdata_d       ;
    reg         [STRB_WIDTH-1:0] txbuf_wstrb_q        , txbuf_wstrb_d       ;
    reg                            txbuf_wvalid_q      , txbuf_wvalid_d      ;

    reg                            bvalid_q            , bvalid_d            ;
    reg         [`BRESP_WIDTH-1:0] bresp_q             , bresp_d             ;
    reg                            txend_wvalid_q      , txend_wvalid_d      ;
    reg                            rxcfg_wvalid_q      , rxcfg_wvalid_d      ;
    reg                            wr_csr_is_tx_q    , wr_csr_is_tx_d    ;

    reg                            irq_q               , irq_d               ;

    assign wready_o = (wr_state_q==WR_IDLE);
    assign bvalid_o = bvalid_q;
    assign bresp_o  = bresp_q;
    assign irq_o    = irq_q;

    always @(*) begin
        wr_state_d         = wr_state_q;
        txbuf_awaddr_d     = txbuf_awaddr_q;
        txbuf_wdata_d      = txbuf_wdata_q;
        txbuf_wstrb_d      = txbuf_wstrb_q;
        txbuf_wvalid_d     = 1'b0;
        bvalid_d           = bvalid_q;
        bresp_d            = bresp_q;
        txend_wvalid_d     = txend_wvalid_q;
        rxcfg_wvalid_d     = rxcfg_wvalid_q;
        wr_csr_is_tx_d   = wr_csr_is_tx_q;

        csr_d[RECEIVE_ADDR_START] = csr_q[RECEIVE_ADDR_START];
        csr_d[RECEIVE_ADDR_END]   = csr_q[RECEIVE_ADDR_END];
        csr_d[RECEIVE_READ_BYTE]  = csr_q[RECEIVE_READ_BYTE];
        csr_d[RECEIVE_ERR]        = csr_q[RECEIVE_ERR];
        csr_d[TX_BUSY]          = 32'h0;
        csr_d[TX_BUFFER_START]  = csr_q[TX_BUFFER_START];
        csr_d[TX_BUFFER_END]    = csr_q[TX_BUFFER_END];
        csr_d[7]                  = csr_q[7];

        irq_d = irq_q;

        case (wr_state_q)
            WR_IDLE: begin
                if (wvalid_i) begin
                    txbuf_wdata_d  = wdata_i;
                    txbuf_wstrb_d  = wstrb_i;
                    case (awaddr_i[31:28])
                        'h1: begin
                            case (awaddr_i[27:26])
                                2'b01: begin
                                    case (awaddr_i[4:2])
                                        RECEIVE_ADDR_START: begin
                                            csr_d[RECEIVE_ADDR_START] = wdata_i;
                                            rxcfg_wvalid_d            = 1'b1;
                                            wr_csr_is_tx_d          = 1'b0;
                                            wr_state_d                = WR_CSR;
                                        end
                                        RECEIVE_READ_BYTE: begin
                                            csr_d[RECEIVE_READ_BYTE]  = wdata_i;
                                            bvalid_d                  = 1'b1;
                                            bresp_d                   = `BRESP_OKAY;
                                            wr_state_d                = WR_RET;
                                        end
                                        TX_BUFFER_END: begin
                                            if ((wdata_i[DATA_WIDTH-1:TX_BUFFER_ADDR_WIDTH+2]!=0)
                                             || (wdata_i[1:0]!=2'b00)) begin
                                                bvalid_d  = 1'b1;
                                                bresp_d   = `BRESP_SLVERR;
                                                wr_state_d = WR_RET;
                                            end else begin
                                                csr_d[TX_BUFFER_END] = wdata_i;
                                                txend_wvalid_d         = 1'b1;
                                                wr_csr_is_tx_d       = 1'b1;
                                                wr_state_d             = WR_CSR;
                                            end
                                        end
                                        default: begin
                                            bvalid_d  = 1'b1;
                                            bresp_d   = `BRESP_SLVERR;
                                            wr_state_d = WR_RET;
                                        end
                                    endcase
                                end
                                2'b11: begin
                                    txbuf_awaddr_d = awaddr_i[TX_BUFFER_ADDR_WIDTH+1:2];
                                    txbuf_wvalid_d = 1'b1;
                                    wr_state_d     = WR_SDP;
                                end
                                default: begin
                                    bvalid_d  = 1'b1;
                                    bresp_d   = `BRESP_SLVERR;
                                    wr_state_d = WR_RET;
                                end
                            endcase
                        end
                        default: begin
                            bvalid_d  = 1'b1;
                            bresp_d   = `BRESP_SLVERR;
                            wr_state_d = WR_RET;
                        end
                    endcase
                end
            end
            WR_CSR: begin
                if ((wr_csr_is_tx_q && txend_wready) || (!wr_csr_is_tx_q && rxcfg_wready)) begin
                    if (wr_csr_is_tx_q) begin
                        txend_wvalid_d = 1'b0;
                    end else begin
                        rxcfg_wvalid_d = 1'b0;
                    end
                    bvalid_d   = 1'b1;
                    bresp_d    = `BRESP_OKAY;
                    wr_state_d = WR_RET;
                end
            end
            WR_SDP: begin
                bvalid_d   = 1'b1;
                bresp_d    = `BRESP_OKAY;
                wr_state_d = WR_RET;
            end
            WR_RET: begin
                if (bready_i) begin
                    wr_state_d = WR_IDLE;
                    bvalid_d   = 1'b0;
                end
            end
            default: ;
        endcase

        // status update from Ethernet side
        if (tx2s_rvalid) begin
            csr_d[TX_BUFFER_START] = {{(DATA_WIDTH-(TX_BUFFER_ADDR_WIDTH+2)){1'b0}}, tx_start_ptr_s};
        end

        if (rx2s_rvalid) begin
            csr_d[RECEIVE_ERR][0] = rx_err_s;
            if (rx_done_s) begin
                csr_d[RECEIVE_ADDR_END] = rx_addr_end_s;
            end
        end

        csr_d[TX_BUSY] = 32'h0;
        csr_d[TX_BUSY][0] = (csr_d[TX_BUFFER_START][TX_BUFFER_ADDR_WIDTH+1:0]
                             != csr_d[TX_BUFFER_END][TX_BUFFER_ADDR_WIDTH+1:0]);

        irq_d = (csr_d[RECEIVE_ADDR_START]!=csr_d[RECEIVE_ADDR_END]);
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            wr_state_q                <= WR_IDLE;
            txbuf_awaddr_q            <= {TX_BUFFER_ADDR_WIDTH{1'b0}};
            txbuf_wdata_q             <= {DATA_WIDTH{1'b0}};
            txbuf_wstrb_q             <= {STRB_WIDTH{1'b0}};
            txbuf_wvalid_q            <= 1'b0;
            bvalid_q                  <= 1'b0;
            bresp_q                   <= `BRESP_OKAY;
            txend_wvalid_q            <= 1'b0;
            rxcfg_wvalid_q            <= 1'b0;
            wr_csr_is_tx_q          <= 1'b0;
            irq_q                     <= 1'b0;
            csr_q[RECEIVE_ADDR_START] <= 32'h0;
            csr_q[RECEIVE_ADDR_END]   <= 32'h0;
            csr_q[RECEIVE_READ_BYTE]  <= 32'h0;
            csr_q[RECEIVE_ERR]        <= 32'h0;
            csr_q[TX_BUSY]          <= 32'h0;
            csr_q[TX_BUFFER_START]  <= 32'h0;
            csr_q[TX_BUFFER_END]    <= 32'h0;
            csr_q[7]                  <= 32'h0;
        end else begin
            wr_state_q                <= wr_state_d;
            txbuf_awaddr_q            <= txbuf_awaddr_d;
            txbuf_wdata_q             <= txbuf_wdata_d;
            txbuf_wstrb_q             <= txbuf_wstrb_d;
            txbuf_wvalid_q            <= txbuf_wvalid_d;
            bvalid_q                  <= bvalid_d;
            bresp_q                   <= bresp_d;
            txend_wvalid_q            <= txend_wvalid_d;
            rxcfg_wvalid_q            <= rxcfg_wvalid_d;
            wr_csr_is_tx_q          <= wr_csr_is_tx_d;
            irq_q                     <= irq_d;
            csr_q[RECEIVE_ADDR_START] <= csr_d[RECEIVE_ADDR_START];
            csr_q[RECEIVE_ADDR_END]   <= csr_d[RECEIVE_ADDR_END];
            csr_q[RECEIVE_READ_BYTE]  <= csr_d[RECEIVE_READ_BYTE];
            csr_q[RECEIVE_ERR]        <= csr_d[RECEIVE_ERR];
            csr_q[TX_BUSY]          <= csr_d[TX_BUSY];
            csr_q[TX_BUFFER_START]  <= csr_d[TX_BUFFER_START];
            csr_q[TX_BUFFER_END]    <= csr_d[TX_BUFFER_END];
            csr_q[7]                  <= csr_d[7];
        end
    end

    // TX buffer RAM (CPU clock -> MII TX clock)
    wire [TX_BUFFER_ADDR_WIDTH-1:0] tx_addr;
    wire       [DATA_WIDTH-1:0]  tx_data;
    wire                          tx_rvalid;

    sdp_2clk #(
        .NUM_COL         (STRB_WIDTH),
        .COL_WIDTH       (8),
        .RAM_WIDTH       (DATA_WIDTH),
        .RAM_DEPTH       (`ETHER_TXBUF_SIZE/4),
        .RAM_PERFORMANCE ("LOW_LATENCY"),
        .INIT_FILE       ("")
    ) transmit_buffer (
        // cpu
        .clka            (clk_i),
        .ena             (txbuf_wvalid_q),
        .wea             (txbuf_wstrb_q),
        .addra           (txbuf_awaddr_q),
        .dina            (txbuf_wdata_q),
        // ether TX
        .addrb           (tx_addr),
        .enb             (tx_rvalid),
        .clkb            (tx_clk_i),
        .rstb            (rst_i),
        .regceb          (1'b0),
        .doutb           (tx_data)
    );

    // ------------------------------------------------------------------------
    // Clock domain crossing FIFOs
    // ------------------------------------------------------------------------
    wire txend_wready;
    wire txend_rvalid;
    wire [TX_BUFFER_ADDR_WIDTH+1:0] tx_end_ptr_e;
    wire txend_rready;

    async_fifo #(
        .DATA_WIDTH  (TX_BUFFER_ADDR_WIDTH+2),
        .ADDR_WIDTH  (2)
    ) tx_end_fifo (
        .wclk_i      (clk_i),
        .rclk_i      (tx_clk_i),
        .wrst_i      (rst_i),
        .rrst_i      (rst_i),
        .wvalid_i    (txend_wvalid_q),
        .wready_o    (txend_wready),
        .wdata_i     (csr_q[TX_BUFFER_END][TX_BUFFER_ADDR_WIDTH+1:0]),
        .rvalid_o    (txend_rvalid),
        .rready_i    (txend_rready),
        .rdata_o     (tx_end_ptr_e)
    );

    wire rxcfg_wready;
    wire rxcfg_rvalid;
    wire [RX_BUFFER_ADDR_WIDTH-1:0] rx_addr_start_word;

    async_fifo #(
        .DATA_WIDTH  (RX_BUFFER_ADDR_WIDTH),
        .ADDR_WIDTH  (2)
    ) rx_cfg_fifo (
        .wclk_i      (clk_i),
        .rclk_i      (rx_clk_i),
        .wrst_i      (rst_i),
        .rrst_i      (rst_i),
        .wvalid_i    (rxcfg_wvalid_q),
        .wready_o    (rxcfg_wready),
        .wdata_i     (csr_q[RECEIVE_ADDR_START][RX_BUFFER_ADDR_WIDTH+1:2]),
        .rvalid_o    (rxcfg_rvalid),
        .rready_i    (1'b1),
        .rdata_o     (rx_addr_start_word)
    );

    wire tx_update_e;
    wire tx_busy_unused;
    wire [TX_BUFFER_ADDR_WIDTH+1:0] tx_start_ptr_e;

    wire tx2s_wready;
    wire tx2s_rvalid;
    wire [TX_BUFFER_ADDR_WIDTH+1:0] tx_start_ptr_s;

    async_fifo #(
        .DATA_WIDTH  (TX_BUFFER_ADDR_WIDTH+2),
        .ADDR_WIDTH  (2)
    ) tx_status_fifo (
        .wclk_i      (tx_clk_i),
        .rclk_i      (clk_i),
        .wrst_i      (rst_i),
        .rrst_i      (rst_i),
        .wvalid_i    (tx_update_e),
        .wready_o    (tx2s_wready),
        .wdata_i     (tx_start_ptr_e),
        .rvalid_o    (tx2s_rvalid),
        .rready_i    (1'b1),
        .rdata_o     (tx_start_ptr_s)
    );

    wire rx_done_e;
    wire rx_err_e;
    wire rx_done_s;
    wire rx_err_s;
    wire [DATA_WIDTH-1:0] rx_addr_end_e;
    wire [DATA_WIDTH-1:0] rx_addr_end_s;

    wire rx2s_wready;
    wire rx2s_rvalid;
    wire rx2s_wvalid = rx_done_e || rx_err_e;

    async_fifo #(
        .DATA_WIDTH  (2+DATA_WIDTH),
        .ADDR_WIDTH  (2)
    ) rx_status_fifo (
        .wclk_i      (rx_clk_i),
        .rclk_i      (clk_i),
        .wrst_i      (rst_i),
        .rrst_i      (rst_i),
        .wvalid_i    (rx2s_wvalid),
        .wready_o    (rx2s_wready),
        .wdata_i     ({rx_done_e, rx_err_e, rx_addr_end_e}),
        .rvalid_o    (rx2s_rvalid),
        .rready_i    (1'b1),
        .rdata_o     ({rx_done_s, rx_err_s, rx_addr_end_s})
    );

    wire rx_addr_start_valid = rxcfg_rvalid;

    ether_rx_mii #(
        .DATA_WIDTH         (DATA_WIDTH),
        .BUFFER_ADDR_WIDTH  (RX_BUFFER_ADDR_WIDTH)
    ) ether_rx_mii (
        .rx_clk_i               (rx_clk_i),
        .rst_rx_i               (rst_i),
        .e2s_wready_i           (rx2s_wready),
        .rx_done_o              (rx_done_e),
        .rx_err_o               (rx_err_e),
        .rx_addr_end_o          (rx_addr_end_e),
        .rx_addr_start_valid_i  (rx_addr_start_valid),
        .rx_addr_start_i        (rx_addr_start_word),
        .rx_valid_o             (rx_data_valid),
        .rx_strobe_o            (rx_data_strobe),
        .rx_addr_o              (rx_addr),
        .rx_data_o              (rx_data),
        .rx_dv_i                (rx_dv_i),
        .rxerr_i                (rxerr_i),
        .rxd_i                  (rxd_i)
    );

    wire tx_err_unused;

    ether_tx_mii #(
        .DATA_WIDTH         (DATA_WIDTH),
        .BUFFER_ADDR_WIDTH  (TX_BUFFER_ADDR_WIDTH)
    ) ether_tx_mii (
        .tx_clk_i               (tx_clk_i),
        .rst_tx_i               (rst_i),
        .tx_end_valid_i         (txend_rvalid),
        .tx_end_i               (tx_end_ptr_e),
        .tx_end_ready_o         (txend_rready),
        .e2s_wready_i           (tx2s_wready),
        .tx_update_o            (tx_update_e),
        .tx_busy_o              (tx_busy_unused),
        .tx_start_o             (tx_start_ptr_e),
        .tx_rvalid_o            (tx_rvalid),
        .tx_addr_o              (tx_addr),
        .tx_data_i              (tx_data),
        .txen_o                 (txen_o),
        .tx_err_o               (tx_err_unused),
        .txd_o                  (txd_o)
    );

endmodule
/******************************************************************************************/

`resetall
