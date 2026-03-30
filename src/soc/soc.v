/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* system on chip */
/******************************************************************************************/
module soc (
    input  wire        clk_i            , // clock
    input  wire        rst_ni           , // reset
    input  wire        rxd_i            , // receive data 
    output wire        txd_o            , // transmit data
    // Ethernet PHY
    output wire        eth_mdc          , // MDC (Management Data Clock)
    inout  wire        eth_mdio         , // MDIO (Management Data I/O)
    output wire        eth_rstn         , // PHY Reset (active low)
`ifdef ETH_IF_RMII
    input  wire        eth_crsdv        , // CRS_DV (Carrier Sense/Receive Data Valid)
    input  wire        eth_rxerr        , // RX_ER (Receive Error)
    input  wire  [1:0] eth_rxd          , // RXD (Receive Data)
    output wire        eth_txen         , // TX_EN (Transmit Enable)
    output wire  [1:0] eth_txd          , // TXD (Transmit Data)
    output wire        eth_refclk       , // REF_CLK (Reference Clock 50MHz)
    input  wire        eth_intn         , // INT (Interrupt, active low)
`else
    input  wire        eth_rx_clk       , // RX_CLK (Receive clock from PHY)
    input  wire        eth_tx_clk       , // TX_CLK (Transmit clock from PHY)
    input  wire        eth_rx_dv        , // RX_DV (Receive Data Valid)
    input  wire        eth_rxerr        , // RX_ER (Receive Error)
    input  wire  [3:0] eth_rxd          , // RXD[3:0] (Receive Data)
    output wire        eth_tx_en        , // TX_EN (Transmit Enable)
    output wire  [3:0] eth_txd          , // TXD[3:0] (Transmit Data)
    output wire        eth_refclk       , // REF_CLK (Reference Clock 25MHz)
`endif
`ifdef NEXYS // DDR2, Nexys
    output wire [12:0] ddr2_addr        , // address
    output wire  [2:0] ddr2_ba          , // bank address
    output wire        ddr2_cas_n       , // column address strobe 
    output wire  [0:0] ddr2_ck_n        , // inverted differential clock
    output wire  [0:0] ddr2_ck_p        , // non-inverted differential clock
    output wire  [0:0] ddr2_cke         , // clock enable
    output wire        ddr2_ras_n       , // row address strobe 
    output wire        ddr2_we_n        , // write enable
    inout  wire [15:0] ddr2_dq          , // bidirectional data bus
    inout  wire  [1:0] ddr2_dqs_n       , // inverted differential data strobe
    inout  wire  [1:0] ddr2_dqs_p       , // non-inverted differential data strobe
    output wire  [0:0] ddr2_cs_n        , // chip select
    output wire  [1:0] ddr2_dm          , // data mask
    output wire  [0:0] ddr2_odt         , // on-die termination 
    input  wire        sd_cd            , // sd card detect
    output wire        sd_rst           , // sd card reset
    output wire        sd_sclk          , // sd card serial clock
    inout  wire        sd_cmd           , // sd card command
    inout  wire  [3:0] sd_dat             // sd card data bus
`else // DDR3, Arty
    output wire [13:0] ddr3_addr        , // address
    output wire  [2:0] ddr3_ba          , // bank address
    output wire        ddr3_cas_n       , // column address strobe 
    output wire  [0:0] ddr3_ck_n        , // inverted differential clock
    output wire  [0:0] ddr3_ck_p        , // non-inverted differential clock
    output wire  [0:0] ddr3_cke         , // clock enable
    output wire        ddr3_ras_n       , // row address strobe 
    output wire        ddr3_reset_n     , // reset
    output wire        ddr3_we_n        , // write enable 
    inout  wire [15:0] ddr3_dq          , // bidirectional data bus
    inout  wire  [1:0] ddr3_dqs_n       , // inverted differential data strobe
    inout  wire  [1:0] ddr3_dqs_p       , // non-inverted differential data strobe
    output wire  [0:0] ddr3_cs_n        , // chip select 
    output wire  [1:0] ddr3_dm          , // data mask
    output wire  [0:0] ddr3_odt           // on-die termination 
`endif
);

    wire clk_ibuf, clk_bufg, clk ;
    wire ui_rst, locked_1        ;
    wire clk_50mhz, locked_2     ;
    wire eth_refclk_int          ;
    ///// input buffer
    IBUF ibuf_clk (
        .I (clk_i   ), // input  clk_i   : 100 MHz
        .O (clk_ibuf)  // output clk_ibuf: 100 MHz
    );
    ///// global buffer
    BUFG bufg_clk (
        .I (clk_ibuf), // input  clk_ibuf: 100 MHz
        .O (clk_bufg)  // output clk_bufg: 100 MHz
    );
    ///// clock generation
    clk_wiz_1 clk_wiz_1 (
        .clk_out1    (clk      ), // output wire clk     : `CLK_FREQ_MHZ
        .reset       (ui_rst   ), // input  wire reset   : dram reset
        .locked      (locked_1 ), // output wire locked
        .clk_in1     (clk_bufg )  // input  wire clk_bufg: 100 MHz
    );

    clk_wiz_2 clk_wiz_2 (
        .clk_out1    (clk_50mhz      ), // output wire clk_50mhz     : 50 MHz
        .clk_out2    (eth_refclk_int ), // output wire clk_phy_90deg : 50 MHz 90 degree phase shift for PHY
        .reset       (ui_rst         ), // input  wire reset         : dram reset
        .locked      (locked_2       ), // output wire locked
        .clk_in1     (clk_bufg       )  // input  wire clk_bufg: 100 MHz
    );
`ifdef ETH_IF_RMII
    assign eth_refclk = eth_refclk_int;
`elsif ETH_IF_MII
    assign eth_refclk = eth_refclk_int;
`endif

    wire rst;
    wire sw_rst_req;
    localparam [9:0] SOFT_RST_CYCLES = 10'd1023;
    reg  sw_rst_req_tgl_q;
    reg  sw_rst_req_sync_ff1_q, sw_rst_req_sync_ff2_q, sw_rst_req_sync_ff2_d_q;
    reg  [9:0] soft_rst_cnt_raw_q;
    reg  soft_rst_sync_ff1_q, soft_rst_sync_ff2_q;
    wire mem_rst_ni;
    wire soft_rst_active_raw;
    wire soft_rst_active;
    wire soc_rst;

    assign soft_rst_active_raw = (soft_rst_cnt_raw_q != 10'd0);
    assign soft_rst_active     = soft_rst_sync_ff2_q;
    assign soc_rst             = rst || soft_rst_active;
    assign mem_rst_ni          = rst_ni;

    // Cross software reset request from clk to clk_bufg to keep pulse width stable
    // in the root clock domain.
    always @(posedge clk) begin
        if (rst) begin
            sw_rst_req_tgl_q <= 1'b0;
            soft_rst_sync_ff1_q <= 1'b0;
            soft_rst_sync_ff2_q <= 1'b0;
        end else begin
            if (sw_rst_req) begin
                sw_rst_req_tgl_q <= ~sw_rst_req_tgl_q;
            end
            soft_rst_sync_ff1_q <= soft_rst_active_raw;
            soft_rst_sync_ff2_q <= soft_rst_sync_ff1_q;
        end
    end

    always @(posedge clk_bufg or negedge rst_ni) begin
        if (!rst_ni) begin
            sw_rst_req_sync_ff1_q   <= 1'b0;
            sw_rst_req_sync_ff2_q   <= 1'b0;
            sw_rst_req_sync_ff2_d_q <= 1'b0;
            soft_rst_cnt_raw_q      <= 10'd0;
        end else begin
            sw_rst_req_sync_ff1_q   <= sw_rst_req_tgl_q;
            sw_rst_req_sync_ff2_q   <= sw_rst_req_sync_ff1_q;
            sw_rst_req_sync_ff2_d_q <= sw_rst_req_sync_ff2_q;
            if (sw_rst_req_sync_ff2_q ^ sw_rst_req_sync_ff2_d_q) begin
                soft_rst_cnt_raw_q <= SOFT_RST_CYCLES;
            end else if (soft_rst_cnt_raw_q != 10'd0) begin
                soft_rst_cnt_raw_q <= soft_rst_cnt_raw_q - 10'd1;
            end
        end
    end
    // cpu
    wire                   [1:0] priv_lvl       ;
    wire             [`XLEN-1:0] satp           ;
    wire                         mxr            ;
    wire                         sum            ;
    wire                         mprv           ;
    wire                   [1:0] mpp            ;
    wire                         flush_tlb      ;
    wire                  [63:0] mtime          ;
    wire                         timer_irq      ;
    wire                         ipi            ;
    wire [1:0] irq    ;
    wire                         ibus_arvalid   ;
    wire                         ibus_arready   ;
    wire  [`IBUS_ADDR_WIDTH-1:0] ibus_araddr    ;
    wire                         ibus_rvalid    ;
    wire                         ibus_rready    ;
    wire  [`IBUS_DATA_WIDTH-1:0] ibus_rdata     ;
    wire      [`RRESP_WIDTH-1:0] ibus_rresp     ;
    wire  [`DBUS_ADDR_WIDTH-1:0] dbus_axaddr    ;
    wire                         dbus_wvalid    ;
    wire                         dbus_wready    ;
    wire                         dbus_awlock    ;
    wire  [`DBUS_DATA_WIDTH-1:0] dbus_wdata     ;
    wire  [`DBUS_STRB_WIDTH-1:0] dbus_wstrb     ;
    wire                         dbus_bvalid    ;
    wire                         dbus_bready    ;
    wire      [`BRESP_WIDTH-1:0] dbus_bresp     ;
    wire                         dbus_arvalid   ;
    wire                         dbus_arready   ;
    wire                         dbus_arlock    ;
    wire                         dbus_aramo     ;
    wire                         dbus_rvalid    ;
    wire                         dbus_rready    ;
    wire  [`DBUS_DATA_WIDTH-1:0] dbus_rdata     ;
    wire      [`RRESP_WIDTH-1:0] dbus_rresp     ;
    cpu #(
        .HART_ID            (0                      )
    ) cpu (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .priv_lvl_o         (priv_lvl               ), // output wire                   [1:0]
        .satp_o             (satp                   ), // output wire             [`XLEN-1:0]
        .mxr_o              (mxr                    ), // output wire
        .sum_o              (sum                    ), // output wire
        .mprv_o             (mprv                   ), // output wire
        .mpp_o              (mpp                    ), // output wire                   [1:0]
        .flush_tlb_o        (flush_tlb              ), // output wire
        .mtime_i            (mtime                  ), // input  wire                  [63:0]
        .timer_irq_i        (timer_irq              ), // input  wire
        .ipi_i              (ipi                    ), // input  wire
        .irq_i              (irq                    ), // input  wire                   [1:0]
        .ibus_arvalid_o     (ibus_arvalid           ), // output wire
        .ibus_arready_i     (ibus_arready           ), // input  wire
        .ibus_araddr_o      (ibus_araddr            ), // output wire  [`IBUS_ADDR_WIDTH-1:0]
        .ibus_rvalid_i      (ibus_rvalid            ), // input  wire
        .ibus_rready_o      (ibus_rready            ), // output wire
        .ibus_rdata_i       (ibus_rdata             ), // input  wire  [`IBUS_DATA_WIDTH-1:0]
        .ibus_rresp_i       (ibus_rresp             ), // input  wire      [`RRESP_WIDTH-1:0]
        .dbus_axaddr_o      (dbus_axaddr            ), // output wire  [`DBUS_ADDR_WIDTH-1:0]
        .dbus_wvalid_o      (dbus_wvalid            ), // output wire
        .dbus_wready_i      (dbus_wready            ), // input  wire
        .dbus_awlock_o      (dbus_awlock            ), // output wire
        .dbus_wdata_o       (dbus_wdata             ), // output wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_wstrb_o       (dbus_wstrb             ), // output wire  [`DBUS_STRB_WIDTH-1:0]
        .dbus_bvalid_i      (dbus_bvalid            ), // input  wire
        .dbus_bready_o      (dbus_bready            ), // output wire
        .dbus_bresp_i       (dbus_bresp             ), // input  wire      [`BRESP_WIDTH-1:0]
        .dbus_arvalid_o     (dbus_arvalid           ), // output wire
        .dbus_arready_i     (dbus_arready           ), // input  wire
        .dbus_arlock_o      (dbus_arlock            ), // output wire
        .dbus_aramo_o       (dbus_aramo             ), // output wire
        .dbus_rvalid_i      (dbus_rvalid            ), // input  wire
        .dbus_rready_o      (dbus_rready            ), // output wire
        .dbus_rdata_i       (dbus_rdata             ), // input  wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_rresp_i       (dbus_rresp             )  // input  wire      [`RRESP_WIDTH-1:0]
    );

    wire                        cache_wvalid    ;
    wire                        cache_wready    ;
    wire  [`BUS_ADDR_WIDTH-1:0] cache_awaddr    ;
    wire  [`BUS_DATA_WIDTH-1:0] cache_wdata     ;
    wire  [`BUS_STRB_WIDTH-1:0] cache_wstrb     ;
    wire                        cache_bvalid    ;
    wire                        cache_bready    ;
    wire     [`BRESP_WIDTH-1:0] cache_bresp     ;
    wire                        cache_arvalid   ;
    wire                        cache_arready   ;
    wire  [`BUS_ADDR_WIDTH-1:0] cache_araddr    ;
    wire                        cache_rvalid    ;
    wire                        cache_rready    ;
    wire  [`BUS_DATA_WIDTH-1:0] cache_rdata     ;
    wire     [`RRESP_WIDTH-1:0] cache_rresp     ;
    mmu mmu (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .priv_lvl_i         (priv_lvl               ), // input  wire                   [1:0]
        .satp_i             (satp                   ), // input  wire             [`XLEN-1:0]
        .mxr_i              (mxr                    ), // input  wire
        .sum_i              (sum                    ), // input  wire
        .mprv_i             (mprv                   ), // input  wire
        .mpp_i              (mpp                    ), // input  wire                   [1:0]
        .flush_tlb_i        (flush_tlb              ), // input  wire
        .ibus_arvalid_i     (ibus_arvalid           ), // input  wire
        .ibus_arready_o     (ibus_arready           ), // output wire
        .ibus_araddr_i      (ibus_araddr            ), // input  wire  [`IBUS_ADDR_WIDTH-1:0]
        .ibus_rvalid_o      (ibus_rvalid            ), // output wire
        .ibus_rready_i      (ibus_rready            ), // input  wire
        .ibus_rdata_o       (ibus_rdata             ), // output wire  [`IBUS_DATA_WIDTH-1:0]
        .ibus_rresp_o       (ibus_rresp             ), // output wire      [`RRESP_WIDTH-1:0]
        .dbus_axaddr_i      (dbus_axaddr            ), // input  wire  [`DBUS_ADDR_WIDTH-1:0]
        .dbus_wvalid_i      (dbus_wvalid            ), // input  wire
        .dbus_wready_o      (dbus_wready            ), // output wire
        .dbus_awlock_i      (dbus_awlock            ), // input  wire
        .dbus_wdata_i       (dbus_wdata             ), // input  wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_wstrb_i       (dbus_wstrb             ), // input  wire  [`DBUS_STRB_WIDTH-1:0]
        .dbus_bvalid_o      (dbus_bvalid            ), // output wire
        .dbus_bready_i      (dbus_bready            ), // input  wire
        .dbus_bresp_o       (dbus_bresp             ), // output wire      [`BRESP_WIDTH-1:0]
        .dbus_arvalid_i     (dbus_arvalid           ), // input  wire
        .dbus_arready_o     (dbus_arready           ), // output wire
        .dbus_arlock_i      (dbus_arlock            ), // input  wire
        .dbus_aramo_i       (dbus_aramo             ), // input  wire
        .dbus_rvalid_o      (dbus_rvalid            ), // output wire
        .dbus_rready_i      (dbus_rready            ), // input  wire
        .dbus_rdata_o       (dbus_rdata             ), // output wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_rresp_o       (dbus_rresp             ), // output wire      [`RRESP_WIDTH-1:0]
        .bus_wvalid_o       (cache_wvalid           ), // output wire
        .bus_wready_i       (cache_wready           ), // input  wire
        .bus_awaddr_o       (cache_awaddr           ), // output wire   [`BUS_ADDR_WIDTH-1:0]
        .bus_wdata_o        (cache_wdata            ), // output wire   [`BUS_DATA_WIDTH-1:0]
        .bus_wstrb_o        (cache_wstrb            ), // output wire   [`BUS_STRB_WIDTH-1:0]
        .bus_bvalid_i       (cache_bvalid           ), // input  wire
        .bus_bready_o       (cache_bready           ), // output wire
        .bus_bresp_i        (cache_bresp            ), // input  wire      [`BRESP_WIDTH-1:0]
        .bus_arvalid_o      (cache_arvalid          ), // output wire
        .bus_arready_i      (cache_arready          ), // input  wire
        .bus_araddr_o       (cache_araddr           ), // output wire   [`BUS_ADDR_WIDTH-1:0]
        .bus_rvalid_i       (cache_rvalid           ), // input  wire
        .bus_rready_o       (cache_rready           ), // output wire
        .bus_rdata_i        (cache_rdata            ), // input  wire   [`BUS_DATA_WIDTH-1:0]
        .bus_rresp_i        (cache_rresp            )  // input  wire      [`RRESP_WIDTH-1:0]
    );

    wire                         bus_wvalid     ;
    wire                         bus_wready     ;
    wire   [`BUS_ADDR_WIDTH-1:0] bus_awaddr     ;
    wire   [`BUS_DATA_WIDTH-1:0] bus_wdata      ;
    wire   [`BUS_STRB_WIDTH-1:0] bus_wstrb      ;
    wire                         bus_bvalid     ;
    wire                         bus_bready     ;
    wire      [`BRESP_WIDTH-1:0] bus_bresp      ;
    wire                         bus_arvalid    ;
    wire                         bus_arready    ;
    wire   [`BUS_ADDR_WIDTH-1:0] bus_araddr     ;
    wire                         bus_rvalid     ;
    wire                         bus_rready     ;
    wire   [`BUS_DATA_WIDTH-1:0] bus_rdata      ;
    wire      [`RRESP_WIDTH-1:0] bus_rresp      ;

    l2_cache #(
        .CACHE_SIZE         (`L2_CACHE_SIZE         ),
        .ADDR_WIDTH         (`BUS_ADDR_WIDTH        )
    ) l2_cache (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .cpu_wvalid_i       (cache_wvalid           ), // input  wire
        .cpu_wready_o       (cache_wready           ), // output wire
        .cpu_awaddr_i       (cache_awaddr           ), // input  wire   [ADDR_WIDTH-1:0]
        .cpu_wdata_i        (cache_wdata            ), // input  wire   [DATA_WIDTH-1:0]
        .cpu_wstrb_i        (cache_wstrb            ), // input  wire   [STRB_WIDTH-1:0]
        .cpu_bvalid_o       (cache_bvalid           ), // output wire
        .cpu_bready_i       (cache_bready           ), // input  wire
        .cpu_bresp_o        (cache_bresp            ), // output wire [`BRESP_WIDTH-1:0]
        .cpu_arvalid_i      (cache_arvalid          ), // input  wire
        .cpu_arready_o      (cache_arready          ), // output wire
        .cpu_araddr_i       (cache_araddr           ), // input  wire   [ADDR_WIDTH-1:0]
        .cpu_rvalid_o       (cache_rvalid           ), // output wire
        .cpu_rready_i       (cache_rready           ), // input  wire
        .cpu_rdata_o        (cache_rdata            ), // output wire   [DATA_WIDTH-1:0]
        .cpu_rresp_o        (cache_rresp            ), // output wire [`RRESP_WIDTH-1:0]
        .bus_wvalid_o       (bus_wvalid             ), // output wire
        .bus_wready_i       (bus_wready             ), // input  wire
        .bus_awaddr_o       (bus_awaddr             ), // output wire   [ADDR_WIDTH-1:0]
        .bus_wdata_o        (bus_wdata              ), // output wire   [DATA_WIDTH-1:0]
        .bus_wstrb_o        (bus_wstrb              ), // output wire   [STRB_WIDTH-1:0]
        .bus_bvalid_i       (bus_bvalid             ), // input  wire
        .bus_bready_o       (bus_bready             ), // output wire
        .bus_bresp_i        (bus_bresp              ), // input  wire [`BRESP_WIDTH-1:0]
        .bus_arvalid_o      (bus_arvalid            ), // output wire
        .bus_arready_i      (bus_arready            ), // input  wire
        .bus_araddr_o       (bus_araddr             ), // output wire   [ADDR_WIDTH-1:0]
        .bus_rvalid_i       (bus_rvalid             ), // input  wire
        .bus_rready_o       (bus_rready             ), // output wire
        .bus_rdata_i        (bus_rdata              ), // input  wire   [DATA_WIDTH-1:0]
        .bus_rresp_i        (bus_rresp              )  // input  wire [`RRESP_WIDTH-1:0]
    );

    // interconnect
    wire                            bootrom_arvalid     ;
    wire                            bootrom_arready     ;
    wire  [`BOOTROM_ADDR_WIDTH-1:0] bootrom_araddr      ;
    wire                            bootrom_rvalid      ;
    wire                            bootrom_rready      ;
    wire  [`BOOTROM_DATA_WIDTH-1:0] bootrom_rdata       ;
    wire         [`RRESP_WIDTH-1:0] bootrom_rresp       ;
    wire                            clint_wvalid        ;
    wire                            clint_wready        ;
    wire    [`CLINT_ADDR_WIDTH-1:0] clint_awaddr        ;
    wire    [`CLINT_DATA_WIDTH-1:0] clint_wdata         ;
    wire    [`CLINT_STRB_WIDTH-1:0] clint_wstrb         ;
    wire                            clint_bvalid        ;
    wire                            clint_bready        ;
    wire         [`BRESP_WIDTH-1:0] clint_bresp         ;
    wire                            clint_arvalid       ;
    wire                            clint_arready       ;
    wire    [`CLINT_ADDR_WIDTH-1:0] clint_araddr        ;
    wire                            clint_rvalid        ;
    wire                            clint_rready        ;
    wire    [`CLINT_DATA_WIDTH-1:0] clint_rdata         ;
    wire         [`RRESP_WIDTH-1:0] clint_rresp         ;
    wire                            plic_wvalid         ;
    wire                            plic_wready         ;
    wire     [`PLIC_ADDR_WIDTH-1:0] plic_awaddr         ;
    wire     [`PLIC_DATA_WIDTH-1:0] plic_wdata          ;
    wire     [`PLIC_STRB_WIDTH-1:0] plic_wstrb          ;
    wire                            plic_bvalid         ;
    wire                            plic_bready         ;
    wire         [`BRESP_WIDTH-1:0] plic_bresp          ;
    wire                            plic_arvalid        ;
    wire                            plic_arready        ;
    wire     [`PLIC_ADDR_WIDTH-1:0] plic_araddr         ;
    wire                            plic_rvalid         ;
    wire                            plic_rready         ;
    wire     [`PLIC_DATA_WIDTH-1:0] plic_rdata          ;
    wire         [`RRESP_WIDTH-1:0] plic_rresp          ;
    wire                            uart_wvalid         ;
    wire                            uart_wready         ;
    wire     [`UART_ADDR_WIDTH-1:0] uart_awaddr         ;
    wire     [`UART_DATA_WIDTH-1:0] uart_wdata          ;
    wire     [`UART_STRB_WIDTH-1:0] uart_wstrb          ;
    wire                            uart_bvalid         ;
    wire                            uart_bready         ;
    wire         [`BRESP_WIDTH-1:0] uart_bresp          ;
    wire                            uart_arvalid        ;
    wire                            uart_arready        ;
    wire     [`UART_ADDR_WIDTH-1:0] uart_araddr         ;
    wire                            uart_rvalid         ;
    wire                            uart_rready         ;
    wire     [`UART_DATA_WIDTH-1:0] uart_rdata          ;
    wire         [`RRESP_WIDTH-1:0] uart_rresp          ;
    wire                            ether_wvalid        ;
    wire                            ether_wready        ;
    wire   [`ETHER_ADDR_WIDTH-1:0]  ether_awaddr        ;
    wire   [`ETHER_DATA_WIDTH-1:0]  ether_wdata         ;
    wire   [`ETHER_STRB_WIDTH-1:0]  ether_wstrb         ;
    wire                            ether_bvalid        ;
    wire                            ether_bready        ;
    wire         [`BRESP_WIDTH-1:0] ether_bresp         ;
    wire                            ether_arvalid       ;
    wire                            ether_arready       ;
    wire   [`ETHER_ADDR_WIDTH-1:0]  ether_araddr        ;
    wire                            ether_rvalid        ;
    wire                            ether_rready        ;
    wire   [`ETHER_DATA_WIDTH-1:0]  ether_rdata         ;
    wire         [`RRESP_WIDTH-1:0] ether_rresp         ;
    wire                            dram_wvalid         ;
    wire                            dram_wready         ;
    wire     [`DRAM_ADDR_WIDTH-1:0] dram_awaddr         ;
    wire     [`DRAM_DATA_WIDTH-1:0] dram_wdata          ;
    wire     [`DRAM_STRB_WIDTH-1:0] dram_wstrb          ;
    wire                            dram_bvalid         ;
    wire                            dram_bready         ;
    wire         [`BRESP_WIDTH-1:0] dram_bresp          ;
    wire                            dram_arvalid        ;
    wire                            dram_arready        ;
    wire     [`DRAM_ADDR_WIDTH-1:0] dram_araddr         ;
    wire                            dram_rvalid         ;
    wire                            dram_rready         ;
    wire     [`DRAM_DATA_WIDTH-1:0] dram_rdata          ;
    wire         [`RRESP_WIDTH-1:0] dram_rresp          ;

`ifdef NEXYS
    wire                            sdcram_wvalid       ;
    wire                            sdcram_wready       ;
    wire  [`SDCRAM_ADDR_WIDTH-1:0]  sdcram_awaddr       ;
    wire  [`SDCRAM_DATA_WIDTH-1:0]  sdcram_wdata        ;
    wire  [`SDCRAM_STRB_WIDTH-1:0]  sdcram_wstrb        ;
    wire                            sdcram_bvalid       ;
    wire                            sdcram_bready       ;
    wire  [`BRESP_WIDTH-1:0]        sdcram_bresp        ;
    wire                            sdcram_arvalid      ;
    wire                            sdcram_arready      ;
    wire  [`SDCRAM_ADDR_WIDTH-1:0]  sdcram_araddr       ;
    wire                            sdcram_rvalid       ;
    wire                            sdcram_rready       ;
    wire  [`SDCRAM_DATA_WIDTH-1:0]  sdcram_rdata        ;
    wire  [`RRESP_WIDTH-1:0]        sdcram_rresp        ;
`endif

    axi_interconnect axi_interconnect (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .sw_rst_req_o       (sw_rst_req             ), // output wire
        .cpu_wvalid_i       (bus_wvalid             ), // input  wire
        .cpu_wready_o       (bus_wready             ), // output wire
        .cpu_awaddr_i       (bus_awaddr             ), // input  wire      [`BUS_ADDR_WIDTH-1:0]
        .cpu_wdata_i        (bus_wdata              ), // input  wire      [`BUS_DATA_WIDTH-1:0]
        .cpu_wstrb_i        (bus_wstrb              ), // input  wire      [`BUS_STRB_WIDTH-1:0]
        .cpu_bvalid_o       (bus_bvalid             ), // output wire
        .cpu_bready_i       (bus_bready             ), // input  wire
        .cpu_bresp_o        (bus_bresp              ), // output wire         [`BRESP_WIDTH-1:0]
        .cpu_arvalid_i      (bus_arvalid            ), // input  wire
        .cpu_arready_o      (bus_arready            ), // output wire
        .cpu_araddr_i       (bus_araddr             ), // input  wire      [`BUS_ADDR_WIDTH-1:0]
        .cpu_rvalid_o       (bus_rvalid             ), // output wire
        .cpu_rready_i       (bus_rready             ), // input  wire
        .cpu_rdata_o        (bus_rdata              ), // output wire      [`BUS_DATA_WIDTH-1:0]
        .cpu_rresp_o        (bus_rresp              ), // output wire         [`RRESP_WIDTH-1:0]
        .bootrom_arvalid_o  (bootrom_arvalid        ), // output wire
        .bootrom_arready_i  (bootrom_arready        ), // input  wire
        .bootrom_araddr_o   (bootrom_araddr         ), // output wire  [`BOOTROM_ADDR_WIDTH-1:0]
        .bootrom_rvalid_i   (bootrom_rvalid         ), // input  wire
        .bootrom_rready_o   (bootrom_rready         ), // output wire
        .bootrom_rdata_i    (bootrom_rdata          ), // input  wire  [`BOOTROM_DATA_WIDTH-1:0]
        .bootrom_rresp_i    (bootrom_rresp          ), // input  wire         [`RRESP_WIDTH-1:0]
        .clint_wvalid_o     (clint_wvalid           ), // output wire
        .clint_wready_i     (clint_wready           ), // input  wire
        .clint_awaddr_o     (clint_awaddr           ), // output wire    [`CLINT_ADDR_WIDTH-1:0]
        .clint_wdata_o      (clint_wdata            ), // output wire    [`CLINT_DATA_WIDTH-1:0]
        .clint_wstrb_o      (clint_wstrb            ), // output wire    [`CLINT_STRB_WIDTH-1:0]
        .clint_bvalid_i     (clint_bvalid           ), // input  wire
        .clint_bready_o     (clint_bready           ), // output wire
        .clint_bresp_i      (clint_bresp            ), // input  wire         [`BRESP_WIDTH-1:0]
        .clint_arvalid_o    (clint_arvalid          ), // output wire
        .clint_arready_i    (clint_arready          ), // input  wire
        .clint_araddr_o     (clint_araddr           ), // output wire    [`CLINT_ADDR_WIDTH-1:0]
        .clint_rvalid_i     (clint_rvalid           ), // input  wire
        .clint_rready_o     (clint_rready           ), // output wire
        .clint_rdata_i      (clint_rdata            ), // input  wire    [`CLINT_DATA_WIDTH-1:0]
        .clint_rresp_i      (clint_rresp            ), // input  wire         [`RRESP_WIDTH-1:0]
        .plic_wvalid_o      (plic_wvalid            ), // output wire
        .plic_wready_i      (plic_wready            ), // input  wire
        .plic_awaddr_o      (plic_awaddr            ), // output wire     [`PLIC_ADDR_WIDTH-1:0]
        .plic_wdata_o       (plic_wdata             ), // output wire     [`PLIC_DATA_WIDTH-1:0]
        .plic_wstrb_o       (plic_wstrb             ), // output wire     [`PLIC_STRB_WIDTH-1:0]
        .plic_bvalid_i      (plic_bvalid            ), // input  wire
        .plic_bready_o      (plic_bready            ), // output wire
        .plic_bresp_i       (plic_bresp             ), // input  wire         [`BRESP_WIDTH-1:0]
        .plic_arvalid_o     (plic_arvalid           ), // output wire
        .plic_arready_i     (plic_arready           ), // input  wire
        .plic_araddr_o      (plic_araddr            ), // output wire     [`PLIC_ADDR_WIDTH-1:0]
        .plic_rvalid_i      (plic_rvalid            ), // input  wire
        .plic_rready_o      (plic_rready            ), // output wire
        .plic_rdata_i       (plic_rdata             ), // input  wire     [`PLIC_DATA_WIDTH-1:0]
        .plic_rresp_i       (plic_rresp             ), // input  wire         [`RRESP_WIDTH-1:0]
        .uart_wvalid_o      (uart_wvalid            ), // output wire
        .uart_wready_i      (uart_wready            ), // input  wire
        .uart_awaddr_o      (uart_awaddr            ), // output wire     [`UART_ADDR_WIDTH-1:0]
        .uart_wdata_o       (uart_wdata             ), // output wire     [`UART_DATA_WIDTH-1:0]
        .uart_wstrb_o       (uart_wstrb             ), // output wire     [`UART_STRB_WIDTH-1:0]
        .uart_bvalid_i      (uart_bvalid            ), // input  wire
        .uart_bready_o      (uart_bready            ), // output wire
        .uart_bresp_i       (uart_bresp             ), // input  wire         [`BRESP_WIDTH-1:0]
        .uart_arvalid_o     (uart_arvalid           ), // output wire
        .uart_arready_i     (uart_arready           ), // input  wire
        .uart_araddr_o      (uart_araddr            ), // output wire     [`UART_ADDR_WIDTH-1:0]
        .uart_rvalid_i      (uart_rvalid            ), // input  wire
        .uart_rready_o      (uart_rready            ), // output wire
        .uart_rdata_i       (uart_rdata             ), // input  wire     [`UART_DATA_WIDTH-1:0]
        .uart_rresp_i       (uart_rresp             ), // input  wire         [`RRESP_WIDTH-1:0]
        .ether_wvalid_o     (ether_wvalid           ), // output wire
        .ether_wready_i     (ether_wready           ), // input  wire
        .ether_awaddr_o     (ether_awaddr           ), // output wire    [`ETHER_ADDR_WIDTH-1:0]
        .ether_wdata_o      (ether_wdata            ), // output wire    [`ETHER_DATA_WIDTH-1:0]
        .ether_wstrb_o      (ether_wstrb            ), // output wire    [`ETHER_STRB_WIDTH-1:0]
        .ether_bvalid_i     (ether_bvalid           ), // input  wire
        .ether_bready_o     (ether_bready           ), // output wire
        .ether_bresp_i      (ether_bresp            ), // input  wire         [`BRESP_WIDTH-1:0]
        .ether_arvalid_o    (ether_arvalid          ), // output wire
        .ether_arready_i    (ether_arready          ), // input  wire
        .ether_araddr_o     (ether_araddr           ), // output wire    [`ETHER_ADDR_WIDTH-1:0]
        .ether_rvalid_i     (ether_rvalid           ), // input  wire
        .ether_rready_o     (ether_rready           ), // output wire
        .ether_rdata_i      (ether_rdata            ), // input  wire    [`ETHER_DATA_WIDTH-1:0]
        .ether_rresp_i      (ether_rresp            ), // input  wire         [`RRESP_WIDTH-1:0]
        .dram_wvalid_o      (dram_wvalid            ), // output wire
        .dram_wready_i      (dram_wready            ), // input  wire
        .dram_awaddr_o      (dram_awaddr            ), // output wire     [`DBUS_ADDR_WIDTH-1:0]
        .dram_wdata_o       (dram_wdata             ), // output wire     [`DBUS_DATA_WIDTH-1:0]
        .dram_wstrb_o       (dram_wstrb             ), // output wire     [`DBUS_STRB_WIDTH-1:0]
        .dram_bvalid_i      (dram_bvalid            ), // input  wire
        .dram_bready_o      (dram_bready            ), // output wire
        .dram_bresp_i       (dram_bresp             ), // input  wire         [`BRESP_WIDTH-1:0]
        .dram_arvalid_o     (dram_arvalid           ), // output wire
        .dram_arready_i     (dram_arready           ), // input  wire
        .dram_araddr_o      (dram_araddr            ), // output wire     [`DBUS_ADDR_WIDTH-1:0]
        .dram_rvalid_i      (dram_rvalid            ), // input  wire
        .dram_rready_o      (dram_rready            ), // output wire
        .dram_rdata_i       (dram_rdata             ), // input  wire     [`DBUS_DATA_WIDTH-1:0]
        .dram_rresp_i       (dram_rresp             )  // input  wire         [`RRESP_WIDTH-1:0]
`ifdef NEXYS
        ,
        .sdcram_wvalid_o    (sdcram_wvalid          ), // output wire
        .sdcram_wready_i    (sdcram_wready          ), // input  wire
        .sdcram_awaddr_o    (sdcram_awaddr          ), // output wire   [`SDCRAM_ADDR_WIDTH-1:0]
        .sdcram_wdata_o     (sdcram_wdata           ), // output wire   [`SDCRAM_DATA_WIDTH-1:0]
        .sdcram_wstrb_o     (sdcram_wstrb           ), // output wire   [`SDCRAM_STRB_WIDTH-1:0]
        .sdcram_bvalid_i    (sdcram_bvalid          ), // input  wire
        .sdcram_bready_o    (sdcram_bready          ), // output wire
        .sdcram_bresp_i     (sdcram_bresp           ), // input  wire         [`BRESP_WIDTH-1:0]
        .sdcram_arvalid_o   (sdcram_arvalid         ), // output wire
        .sdcram_arready_i   (sdcram_arready         ), // input  wire
        .sdcram_araddr_o    (sdcram_araddr          ), // output wire   [`SDCRAM_ADDR_WIDTH-1:0]
        .sdcram_rvalid_i    (sdcram_rvalid          ), // input  wire
        .sdcram_rready_o    (sdcram_rready          ), // output wire
        .sdcram_rdata_i     (sdcram_rdata           ), // input  wire   [`SDCRAM_DATA_WIDTH-1:0]
        .sdcram_rresp_i     (sdcram_rresp           )  // input  wire         [`RRESP_WIDTH-1:0]
`endif
    );

    // bootrom
    bootrom #(
        .ROM_SIZE           (`BOOTROM_SIZE          ),
        .ADDR_WIDTH         (`BOOTROM_ADDR_WIDTH    ),
        .DATA_WIDTH         (`BOOTROM_DATA_WIDTH    )
    ) bootrom (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .arvalid_i          (bootrom_arvalid        ), // input  wire
        .arready_o          (bootrom_arready        ), // output wire
        .araddr_i           (bootrom_araddr         ), // input  wire  [ADDR_WIDTH-1:0]
        .rvalid_o           (bootrom_rvalid         ), // output reg
        .rready_i           (bootrom_rready         ), // input  wire
        .rdata_o            (bootrom_rdata          ), // output reg   [DATA_WIDTH-1:0]
        .rresp_o            (bootrom_rresp          )  // output wire [RRESP_WIDTH-1:0]
    );

    // clint
    clint #(
        .ADDR_WIDTH         (`CLINT_ADDR_WIDTH      )
    ) clint (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .mtime_o            (mtime                  ), // output wire            [63:0]
        .timer_irq_o        (timer_irq              ), // output wire
        .ipi_o              (ipi                    ), // output wire
        .wvalid_i           (clint_wvalid           ), // input  wire
        .wready_o           (clint_wready           ), // output wire
        .awaddr_i           (clint_awaddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .wdata_i            (clint_wdata            ), // input  wire  [DATA_WIDTH-1:0]
        .wstrb_i            (clint_wstrb            ), // input  wire  [STRB_WIDTH-1:0]
        .bvalid_o           (clint_bvalid           ), // output wire
        .bready_i           (clint_bready           ), // input  wire
        .bresp_o            (clint_bresp            ), // output wire [BRESP_WIDTH-1:0]
        .arvalid_i          (clint_arvalid          ), // input  wire
        .arready_o          (clint_arready          ), // output wire
        .araddr_i           (clint_araddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .rvalid_o           (clint_rvalid           ), // output wire
        .rready_i           (clint_rready           ), // input  wire
        .rdata_o            (clint_rdata            ), // output wire  [DATA_WIDTH-1:0]
        .rresp_o            (clint_rresp            )  // output wire [RRESP_WIDTH-1:0]
    );

    // plic
    wire uart_irq;
    wire ether_irq;
    plic #(
        .ADDR_WIDTH         (`PLIC_ADDR_WIDTH       )
    ) plic (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .src_irq_i          ({ether_irq, uart_irq, 1'b0}), // input  wire    [NUM_SRCS-1:0]  // source's interrupt request. interrupt source 0 is reserved (it does not exist)
        .irq_o              (irq                    ), // output wire    [NUM_CTXS-1:0]  // external interrupt request
        .wvalid_i           (plic_wvalid            ), // input  wire
        .wready_o           (plic_wready            ), // output wire
        .awaddr_i           (plic_awaddr            ), // input  wire  [ADDR_WIDTH-1:0]
        .wdata_i            (plic_wdata             ), // input  wire  [DATA_WIDTH-1:0]
        .wstrb_i            (plic_wstrb             ), // input  wire  [STRB_WIDTH-1:0]
        .bvalid_o           (plic_bvalid            ), // output wire
        .bready_i           (plic_bready            ), // input  wire
        .bresp_o            (plic_bresp             ), // output wire [BRESP_WIDTH-1:0]
        .arvalid_i          (plic_arvalid           ), // input  wire
        .arready_o          (plic_arready           ), // output wire
        .araddr_i           (plic_araddr            ), // input  wire  [ADDR_WIDTH-1:0]
        .rvalid_o           (plic_rvalid            ), // output wire
        .rready_i           (plic_rready            ), // input  wire
        .rdata_o            (plic_rdata             ), // output wire  [DATA_WIDTH-1:0]
        .rresp_o            (plic_rresp             )  // output wire [RRESP_WIDTH-1:0]
    );

    // uart
    uart #(
        .CLK_FREQ_MHZ       (`CLK_FREQ_MHZ          ),
        .BAUD_RATE          (`BAUD_RATE             ),
        .DETECT_COUNT       (`DETECT_COUNT          ),
        .FIFO_DEPTH         (`FIFO_DEPTH            ),
        .ADDR_WIDTH         (`UART_ADDR_WIDTH       ),
        .DATA_WIDTH         (`UART_DATA_WIDTH       )
    ) uart (
        .clk_i              (clk                    ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .rxd_i              (rxd_i                  ), // input  wire
        .txd_o              (txd_o                  ), // output wire
        .irq_o              (uart_irq               ), // output wire
        .wvalid_i           (uart_wvalid            ), // input  wire
        .wready_o           (uart_wready            ), // output wire
        .awaddr_i           (uart_awaddr            ), // input  wire   [ADDR_WIDTH-1:0]
        .wdata_i            (uart_wdata             ), // input  wire   [DATA_WIDTH-1:0]
        .wstrb_i            (uart_wstrb             ), // input  wire   [STRB_WIDTH-1:0]
        .bvalid_o           (uart_bvalid            ), // output wire
        .bready_i           (uart_bready            ), // input  wire
        .bresp_o            (uart_bresp             ), // output wire [`BRESP_WIDTH-1:0]
        .arvalid_i          (uart_arvalid           ), // input  wire
        .arready_o          (uart_arready           ), // output wire
        .araddr_i           (uart_araddr            ), // input  wire   [ADDR_WIDTH-1:0]
        .rvalid_o           (uart_rvalid            ), // output wire
        .rready_i           (uart_rready            ), // input  wire
        .rdata_o            (uart_rdata             ), // output wire   [DATA_WIDTH-1:0]
        .rresp_o            (uart_rresp             )  // output wire [`RRESP_WIDTH-1:0]
    );

`ifdef ETH_IF_RMII
    // Ethernet IOB registers for RX signals
    (* IOB = "TRUE" *) reg [1:0] rxd_iob;
    (* IOB = "TRUE" *) reg crs_dv_iob;
    (* IOB = "TRUE" *) reg rxerr_iob;

    // Ethernet IOB registers for TX signals
    (* IOB = "TRUE" *) reg [1:0] txd_iob;
    (* IOB = "TRUE" *) reg txen_iob;

    // Internal wires from ether module
    wire [1:0] txd_internal;
    wire txen_internal;

    always @(posedge clk_50mhz) begin
        // RX: capture inputs at IOB
        rxd_iob    <= eth_rxd;
        crs_dv_iob <= eth_crsdv;
        rxerr_iob  <= eth_rxerr;
    end

    always @(posedge clk_50mhz) begin
        // TX: drive outputs from IOB
        txd_iob  <= txd_internal;
        txen_iob <= txen_internal;
    end

    // Connect IOB outputs to top-level ports
    assign eth_txd  = txd_iob;
    assign eth_txen = txen_iob;

    ether_rmii #(
        .ADDR_WIDTH         (`ETHER_ADDR_WIDTH      ),
        .DATA_WIDTH         (`ETHER_DATA_WIDTH      )
    ) ether (
        .clk_i              (clk                    ), // input  wire
        .clk_50mhz_i        (clk_50mhz              ), // input  wire : 50MHz 0deg for internal logic
        .rst_i              (soc_rst                ), // input  wire
        .irq_o              (ether_irq              ), // output wire
        .wvalid_i           (ether_wvalid           ), // input  wire
        .wready_o           (ether_wready           ), // output wire
        .awaddr_i           (ether_awaddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .wdata_i            (ether_wdata            ), // input  wire  [DATA_WIDTH-1:0]
        .wstrb_i            (ether_wstrb            ), // input  wire  [STRB_WIDTH-1:0]
        .bvalid_o           (ether_bvalid           ), // output wire
        .bready_i           (ether_bready           ), // input  wire
        .bresp_o            (ether_bresp            ), // output wire [`BRESP_WIDTH-1:0]
        .arvalid_i          (ether_arvalid          ), // input  wire
        .arready_o          (ether_arready          ), // output wire
        .araddr_i           (ether_araddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .rvalid_o           (ether_rvalid           ), // output wire
        .rready_i           (ether_rready           ), // input  wire
        .rdata_o            (ether_rdata            ), // output wire  [DATA_WIDTH-1:0]
        .rresp_o            (ether_rresp            ), // output wire [`RRESP_WIDTH-1:0]
        .mdc_o              (eth_mdc                ), // output wire
        .mdio_io            (eth_mdio               ), // inout  wire
        .rstn_o             (eth_rstn               ), // output wire
        .crs_dv_i           (crs_dv_iob             ), // input  wire (from IOB)
        .rxerr_i            (rxerr_iob              ), // input  wire (from IOB)
        .rxd_i              (rxd_iob                ), // input  wire [1:0] (from IOB)
        .txen_o             (txen_internal          ), // output wire (to IOB)
        .txd_o              (txd_internal           ), // output wire [1:0] (to IOB)
        .intn_i             (eth_intn               )  // input  wire
    );
`else
    // Ethernet IOB registers for RX signals (MII)
    (* IOB = "TRUE" *) reg [3:0] rxd_iob;
    (* IOB = "TRUE" *) reg rx_dv_iob;
    (* IOB = "TRUE" *) reg rxerr_iob;

    // Ethernet IOB registers for TX signals (MII)
    (* IOB = "TRUE" *) reg [3:0] txd_iob;
    (* IOB = "TRUE" *) reg txen_iob;

    // Internal wires from ether module
    wire [3:0] txd_internal;
    wire txen_internal;

    always @(posedge eth_rx_clk) begin
        // RX: capture inputs at IOB
        rxd_iob   <= eth_rxd;
        rx_dv_iob <= eth_rx_dv;
        rxerr_iob <= eth_rxerr;
    end

    always @(posedge eth_tx_clk) begin
        // TX: drive outputs from IOB
        txd_iob  <= txd_internal;
        txen_iob <= txen_internal;
    end

    // Connect IOB outputs to top-level ports
    assign eth_txd   = txd_iob;
    assign eth_tx_en = txen_iob;

    ether_mii #(
        .ADDR_WIDTH         (`ETHER_ADDR_WIDTH      ),
        .DATA_WIDTH         (`ETHER_DATA_WIDTH      )
    ) ether_mii (
        .clk_i              (clk                    ), // input  wire
        .rx_clk_i           (eth_rx_clk             ), // input  wire
        .tx_clk_i           (eth_tx_clk             ), // input  wire
        .rst_i              (soc_rst                ), // input  wire
        .irq_o              (ether_irq              ), // output wire
        .wvalid_i           (ether_wvalid           ), // input  wire
        .wready_o           (ether_wready           ), // output wire
        .awaddr_i           (ether_awaddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .wdata_i            (ether_wdata            ), // input  wire  [DATA_WIDTH-1:0]
        .wstrb_i            (ether_wstrb            ), // input  wire  [STRB_WIDTH-1:0]
        .bvalid_o           (ether_bvalid           ), // output wire
        .bready_i           (ether_bready           ), // input  wire
        .bresp_o            (ether_bresp            ), // output wire [`BRESP_WIDTH-1:0]
        .arvalid_i          (ether_arvalid          ), // input  wire
        .arready_o          (ether_arready          ), // output wire
        .araddr_i           (ether_araddr           ), // input  wire  [ADDR_WIDTH-1:0]
        .rvalid_o           (ether_rvalid           ), // output wire
        .rready_i           (ether_rready           ), // input  wire
        .rdata_o            (ether_rdata            ), // output wire  [DATA_WIDTH-1:0]
        .rresp_o            (ether_rresp            ), // output wire [`RRESP_WIDTH-1:0]
        .mdc_o              (eth_mdc                ), // output wire
        .mdio_io            (eth_mdio               ), // inout  wire
        .rstn_o             (eth_rstn               ), // output wire
        .rx_dv_i            (rx_dv_iob              ), // input  wire (from IOB)
        .rxerr_i            (rxerr_iob              ), // input  wire (from IOB)
        .rxd_i              (rxd_iob                ), // input  wire [3:0] (from IOB)
        .txen_o             (txen_internal          ), // output wire (to IOB)
        .txd_o              (txd_internal           )  // output wire [3:0] (to IOB)
    );
`endif

    // dram
    dram_controller #(
        .DRAM_SIZE          (`DRAM_SIZE             ),
        .ADDR_WIDTH         (`DRAM_ADDR_WIDTH       ),
        .DATA_WIDTH         (`DRAM_DATA_WIDTH       )
    ) dram_controller (
        .clk_i              (clk_i                  ), // input  wire
        .rst_ni             (mem_rst_ni             ), // input  wire
        .clk_bufg_i         (clk_bufg               ), // input  wire
        .soc_clk_i          (clk                    ), // input  wire
        .soft_rst_i         (soft_rst_active        ), // input  wire
        .ui_rst_o           (ui_rst                 ), // output wire
        .locked_1_i         (locked_1               ), // input  wire
        .locked_2_i         (locked_2               ), // input  wire
        .rst_o              (rst                    ), // output wire
        .wvalid_i           (dram_wvalid            ), // input  wire
        .wready_o           (dram_wready            ), // output wire
        .awaddr_i           (dram_awaddr            ), // input  wire   [ADDR_WIDTH-1:0]
        .wdata_i            (dram_wdata             ), // input  wire   [DATA_WIDTH-1:0]
        .wstrb_i            (dram_wstrb             ), // input  wire   [STRB_WIDTH-1:0]
        .bvalid_o           (dram_bvalid            ), // output wire
        .bready_i           (dram_bready            ), // input  wire
        .bresp_o            (dram_bresp             ), // output wire [`BRESP_WIDTH-1:0]
        .arvalid_i          (dram_arvalid           ), // input  wire
        .arready_o          (dram_arready           ), // output wire
        .araddr_i           (dram_araddr            ), // input  wire   [ADDR_WIDTH-1:0]
        .rvalid_o           (dram_rvalid            ), // output wire
        .rready_i           (dram_rready            ), // input  wire
        .rdata_o            (dram_rdata             ), // output reg    [DATA_WIDTH-1:0]
        .rresp_o            (dram_rresp             ), // output wire [`RRESP_WIDTH-1:0]
`ifdef NEXYS  // Nexys
        .ddr2_addr          (ddr2_addr              ), // output wire             [12:0]
        .ddr2_ba            (ddr2_ba                ), // output wire              [2:0]
        .ddr2_cas_n         (ddr2_cas_n             ), // output wire
        .ddr2_ck_n          (ddr2_ck_n              ), // output wire              [0:0]
        .ddr2_ck_p          (ddr2_ck_p              ), // output wire              [0:0]
        .ddr2_cke           (ddr2_cke               ), // output wire              [0:0]
        .ddr2_ras_n         (ddr2_ras_n             ), // output wire
        .ddr2_we_n          (ddr2_we_n              ), // output wire
        .ddr2_dq            (ddr2_dq                ), // inout  wire             [15:0]
        .ddr2_dqs_n         (ddr2_dqs_n             ), // inout  wire              [1:0]
        .ddr2_dqs_p         (ddr2_dqs_p             ), // inout  wire              [1:0]
        .ddr2_cs_n          (ddr2_cs_n              ), // output wire              [0:0]
        .ddr2_dm            (ddr2_dm                ), // output wire              [1:0]
        .ddr2_odt           (ddr2_odt               )  // output wire              [0:0]
`else // DDR3, Arty
        .ddr3_addr          (ddr3_addr              ), // output wire             [13:0]
        .ddr3_ba            (ddr3_ba                ), // output wire              [2:0]
        .ddr3_cas_n         (ddr3_cas_n             ), // output wire
        .ddr3_ck_n          (ddr3_ck_n              ), // output wire              [0:0]
        .ddr3_ck_p          (ddr3_ck_p              ), // output wire              [0:0]
        .ddr3_cke           (ddr3_cke               ), // output wire              [0:0]
        .ddr3_ras_n         (ddr3_ras_n             ), // output wire
        .ddr3_reset_n       (ddr3_reset_n           ), // output wire
        .ddr3_we_n          (ddr3_we_n              ), // output wire
        .ddr3_dq            (ddr3_dq                ), // inout  wire             [15:0]
        .ddr3_dqs_n         (ddr3_dqs_n             ), // inout  wire              [1:0]
        .ddr3_dqs_p         (ddr3_dqs_p             ), // inout  wire              [1:0]
        .ddr3_cs_n          (ddr3_cs_n              ), // output wire              [0:0]
        .ddr3_dm            (ddr3_dm                ), // output wire              [1:0]
        .ddr3_odt           (ddr3_odt               )  // output wire              [0:0]
`endif
    );

`ifdef NEXYS
    // sdcram
    sdcram_controller sdcram_controller(
        .clk_i             (clk                    ), // input  wire
        .clk_50mhz_i       (clk_50mhz              ), // input  wire
        .rst_ni            (mem_rst_ni             ), // input  wire
        .wvalid_i          (sdcram_wvalid          ), // input  wire
        .wready_o          (sdcram_wready          ), // output wire
        .awaddr_i          (sdcram_awaddr          ), // input  wire
        .wdata_i           (sdcram_wdata           ), // input  wire
        .wstrb_i           (sdcram_wstrb           ), // input
        .bvalid_o          (sdcram_bvalid          ), // output wire
        .bready_i          (sdcram_bready          ), // input  wire
        .bresp_o           (sdcram_bresp           ), // output wire
        .arvalid_i         (sdcram_arvalid         ), // input  wire
        .arready_o         (sdcram_arready         ), // output wire
        .araddr_i          (sdcram_araddr          ), // input  wire
        .rvalid_o          (sdcram_rvalid          ), // output wire
        .rready_i          (sdcram_rready          ), // input  wire
        .rdata_o           (sdcram_rdata           ), // output wire
        .rresp_o           (sdcram_rresp           ), // output wire
        // sd interface
        .sd_cd             (sd_cd                 ), // input  wire
        .sd_rst            (sd_rst                ), // output wire
        .sd_sclk           (sd_sclk               ), // output wire
        .sd_cmd            (sd_cmd                ), // output wire
        .sd_dat            (sd_dat                )  // inout  wire                [3:0]
    );
`endif

endmodule
/******************************************************************************************/

`resetall
