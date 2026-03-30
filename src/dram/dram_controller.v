/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "config.vh"

/* dynamic random access memory (DRAM) controller */
/******************************************************************************************/
module dram_controller #(
    parameter  DRAM_SIZE            = 0                                 , // dram size in bytes
    localparam ID_WIDTH             = 4                                 , // ID width
    parameter  ADDR_WIDTH           = 0                                 , // address width
    parameter  DATA_WIDTH           = 0                                 , // data width
    localparam STRB_WIDTH           = DATA_WIDTH/8                      , // strobe width
    localparam OFFSET_WIDTH         = $clog2(DATA_WIDTH/8)              , // offset width
    localparam VALID_ADDR_WIDTH     = $clog2(DRAM_SIZE)-(OFFSET_WIDTH)    // valid address width
) (
    input  wire                    clk_i                , // system clock (100 MHz)
    input  wire                    rst_ni               , // reset X
    input  wire                    clk_bufg_i           , // buffered clock
    input  wire                    soc_clk_i            , // soc clock (CLK_FREQ_MHZ MHz)
    input  wire                    soft_rst_i           , // soft reset for controller front-end
    output wire                    ui_rst_o             , // reset from MIG
    input  wire                    locked_1_i           , // locked from PLL
    input  wire                    locked_2_i           , // locked from PLL
    output wire                    rst_o                , // reset output
    input  wire                    wvalid_i             , // write request valid
    output wire                    wready_o             , // write request ready
    input  wire   [ADDR_WIDTH-1:0] awaddr_i             , // write request address
    input  wire   [DATA_WIDTH-1:0] wdata_i              , // write request data
    input  wire   [STRB_WIDTH-1:0] wstrb_i              , // write request strobe
    output wire                    bvalid_o             , // write response valid
    input  wire                    bready_i             , // write response ready
    output wire [`BRESP_WIDTH-1:0] bresp_o              , // write response status
    input  wire                    arvalid_i            , // read request valid
    output wire                    arready_o            , // read request ready
    input  wire   [ADDR_WIDTH-1:0] araddr_i             , // read request address
    output wire                    rvalid_o             , // read response valid
    input  wire                    rready_i             , // read response ready
    output wire   [DATA_WIDTH-1:0] rdata_o              , // read response data
    output wire [`RRESP_WIDTH-1:0] rresp_o              , // read response status
`ifdef NEXYS // Nexys
    output wire             [12:0] ddr2_addr            , // address
    output wire              [2:0] ddr2_ba              , // bank address
    output wire                    ddr2_cas_n           , // column address strobe
    output wire              [0:0] ddr2_ck_n            , // inverted differential clock
    output wire              [0:0] ddr2_ck_p            , // non-inverted differential clock
    output wire              [0:0] ddr2_cke             , // clock enable
    output wire                    ddr2_ras_n           , // row address strobe
    output wire                    ddr2_we_n            , // write enable
    inout  wire             [15:0] ddr2_dq              , // bidirectional data bus
    inout  wire              [1:0] ddr2_dqs_n           , // inverted differential data strobe
    inout  wire              [1:0] ddr2_dqs_p           , // non-inverted differential data strobe
    output wire              [0:0] ddr2_cs_n            , // chip select
    output wire              [1:0] ddr2_dm              , // data mask
    output wire              [0:0] ddr2_odt               // on-die termination
`else // DDR3, Arty
    output wire             [13:0] ddr3_addr            , // address
    output wire              [2:0] ddr3_ba              , // bank address
    output wire                    ddr3_cas_n           , // column address strobe
    output wire              [0:0] ddr3_ck_n            , // inverted differential clock
    output wire              [0:0] ddr3_ck_p            , // non-inverted differential clock
    output wire              [0:0] ddr3_cke             , // clock enable
    output wire                    ddr3_ras_n           , // row address strobe
    output wire                    ddr3_reset_n         , // reset
    output wire                    ddr3_we_n            , // write enable
    inout  wire             [15:0] ddr3_dq              , // bidirectional data bus
    inout  wire              [1:0] ddr3_dqs_n           , // inverted differential data strobe
    inout  wire              [1:0] ddr3_dqs_p           , // non-inverted differential data strobe
    output wire              [0:0] ddr3_cs_n            , // chip select
    output wire              [1:0] ddr3_dm              , // data mask
    output wire              [0:0] ddr3_odt               // on-die termination
`endif
);

    // DRC: design rule check
    initial begin
        if (DRAM_SIZE ==0  ) $fatal(1, "specify a dram DRAM_SIZE");
        if (ADDR_WIDTH==0  ) $fatal(1, "specify a dram ADDR_WIDTH");
        if (DATA_WIDTH==0  ) $fatal(1, "specify a dram DATA_WIDTH");
        if (DATA_WIDTH!=128) $fatal(1, "This DRAM controller only supports 128-bit DATA_WIDTH");
    end

    assign ui_rst_o = ui_rst;

    // clock
    wire sys_clk, clk_ref, locked_0;
    clk_wiz_0 clk_wiz_0 (
        // Clock out ports
        .clk_out1               (sys_clk                ), // output clk_out1 // sys_clk: 166.66667 MHz
        .clk_out2               (clk_ref                ), // output clk_out2 // clk_ref: 200.00000 MHz
        // Status and control signals
        .reset                  (!rst_ni                ), // input  reset
        .locked                 (locked_0               ), // output locked
        // Clock in ports
        .clk_in1                (clk_bufg_i             )  // input  clk_in1  // clk_i  : 100.00000 MHz
    );

    wire ui_rst, ui_clk;

    // reset
    wire sys_rst;
    synchronizer sync_sys_rst (
        .clk_i                  (sys_clk                                                ), // input  wire
        .d_i                    (!rst_ni || !locked_0                                   ), // input  wire
        .q_o                    (sys_rst                                                )  // output wire
    );

    wire init_calib_complete, ui_clk_sync_rst, mmcm_locked;
    synchronizer sync_ui_rst (
        .clk_i                  (ui_clk                                                 ), // input  wire
        .d_i                    (!init_calib_complete || ui_clk_sync_rst || !mmcm_locked), // input  wire
        .q_o                    (ui_rst                                                 )  // output wire
    );

    synchronizer sync_rst_o (
        .clk_i                  (soc_clk_i                                              ), // input  wire
        .d_i                    (ui_rst || !locked_1_i || !locked_2_i                   ), // input  wire
        .q_o                    (rst_o                                                  )  // output wire
    );

    wire soft_rst_ui;
    synchronizer sync_soft_rst_ui (
        .clk_i                  (ui_clk                                                 ), // input  wire
        .d_i                    (soft_rst_i                                             ), // input  wire
        .q_o                    (soft_rst_ui                                            )  // output wire
    );

    wire front_rst_soc;
    wire front_rst_ui;
    assign front_rst_soc = rst_o || soft_rst_i;
    assign front_rst_ui  = ui_rst || soft_rst_ui;

//==============================================================================

    // request fifo

    // req_fifo_data: {strb, data, addr, valid}
    localparam REQ_FIFO_DATA_WIDTH  = STRB_WIDTH+DATA_WIDTH+VALID_ADDR_WIDTH+1  ;
    localparam REQ_FIFO_ADDR_LSB    = 1                                         ;
    localparam REQ_FIFO_DATA_LSB    = REQ_FIFO_ADDR_LSB+VALID_ADDR_WIDTH        ;
    localparam REQ_FIFO_STRB_LSB    = REQ_FIFO_DATA_LSB+DATA_WIDTH              ;
    localparam REQ_FIFO_ADDR_MSB    = REQ_FIFO_DATA_LSB-1                       ;
    localparam REQ_FIFO_DATA_MSB    = REQ_FIFO_STRB_LSB-1                       ;
    localparam REQ_FIFO_STRB_MSB    = REQ_FIFO_DATA_WIDTH-1                     ;

    wire                           req_fifo_wvalid  ;
    wire                           req_fifo_wready  ;
    wire [REQ_FIFO_DATA_WIDTH-1:0] req_fifo_wdata   ;

    assign req_fifo_wvalid  = wvalid_i || arvalid_i         ;
    assign wready_o         = req_fifo_wready && !arvalid_i ;
    assign arready_o        = req_fifo_wready               ;
    assign req_fifo_wdata   = {wstrb_i, wdata_i, ((arvalid_i) ? araddr_i[$clog2(DRAM_SIZE)-1:OFFSET_WIDTH] : awaddr_i[$clog2(DRAM_SIZE)-1:OFFSET_WIDTH]), arvalid_i};

    wire                           req_fifo_rvalid  ;
    wire                           req_fifo_rready  ;
    wire [REQ_FIFO_DATA_WIDTH-1:0] req_fifo_rdata   ;

    async_fifo #(
        .ADDR_WIDTH             (9                      ),
        .DATA_WIDTH             (REQ_FIFO_DATA_WIDTH    )
    ) req_fifo (
        .wclk_i                 (soc_clk_i              ), // input  wire
        .rclk_i                 (ui_clk                 ), // input  wire
        .wrst_i                 (front_rst_soc          ), // input  wire
        .rrst_i                 (front_rst_ui           ), // input  wire
        .wvalid_i               (req_fifo_wvalid        ), // input  wire
        .wready_o               (req_fifo_wready        ), // output wire
        .wdata_i                (req_fifo_wdata         ), // input  wire [DATA_WIDTH-1:0]
        .rvalid_o               (req_fifo_rvalid        ), // output wire
        .rready_i               (req_fifo_rready        ), // input  wire
        .rdata_o                (req_fifo_rdata         )  // output reg  [DATA_WIDTH-1:0]
    );

    // response fifo

    // {resp, data, valid}
    localparam RSP_FIFO_DATA_WIDTH  = 2+DATA_WIDTH+1                                    ;
    localparam RSP_FIFO_DATA_LSB    = 1                                                 ;
    localparam RSP_FIFO_RESP_LSB    = RSP_FIFO_DATA_LSB+DATA_WIDTH                      ;
    localparam RSP_FIFO_DATA_MSB    = RSP_FIFO_RESP_LSB-1                               ;
    localparam RSP_FIFO_RESP_MSB    = RSP_FIFO_DATA_WIDTH-1                             ;

    wire                           rsp_fifo_wvalid  ;
    wire                           rsp_fifo_wready  ;
    wire [RSP_FIFO_DATA_WIDTH-1:0] rsp_fifo_wdata   ;

    wire                           rsp_fifo_rvalid  ;
    wire                           rsp_fifo_rready  ;
    wire [RSP_FIFO_DATA_WIDTH-1:0] rsp_fifo_rdata   ;

    assign bvalid_o         = rsp_fifo_rvalid && (rsp_fifo_rdata[0]==1'b0)              ;
    assign rvalid_o         = rsp_fifo_rvalid && (rsp_fifo_rdata[0]==1'b1)              ;
    assign rsp_fifo_rready  = bready_i || rready_i                                      ; // NOTE: It is better to retain whether it's a write or read request.
    assign rdata_o          = rsp_fifo_rdata[RSP_FIFO_DATA_MSB:RSP_FIFO_DATA_LSB]       ;
    assign bresp_o          = rsp_fifo_rdata[RSP_FIFO_RESP_MSB:RSP_FIFO_RESP_LSB]       ;
    assign rresp_o          = rsp_fifo_rdata[RSP_FIFO_RESP_MSB:RSP_FIFO_RESP_LSB]       ;

    async_fifo #(
        .ADDR_WIDTH             (9                      ),
        .DATA_WIDTH             (RSP_FIFO_DATA_WIDTH    )
    ) rsp_fifo (
        .wclk_i                 (ui_clk                 ), // input  wire
        .rclk_i                 (soc_clk_i              ), // input  wire
        .wrst_i                 (front_rst_ui           ), // input  wire
        .rrst_i                 (front_rst_soc          ), // input  wire
        .wvalid_i               (rsp_fifo_wvalid        ), // input  wire
        .wready_o               (rsp_fifo_wready        ), // output wire
        .wdata_i                (rsp_fifo_wdata         ), // input  wire [DATA_WIDTH-1:0]
        .rvalid_o               (rsp_fifo_rvalid        ), // output wire
        .rready_i               (rsp_fifo_rready        ), // input  wire
        .rdata_o                (rsp_fifo_rdata         )  // output reg  [DATA_WIDTH-1:0]
    );

//==============================================================================

    // write request chennel
    wire                        dram_awvalid    ;
    wire                        dram_awready    ;
    wire       [ADDR_WIDTH-1:0] dram_awaddr     ;

    assign dram_awvalid     = req_fifo_rvalid && (req_fifo_rdata[0]==1'b0)                          ;
    assign dram_awaddr      = {req_fifo_rdata[REQ_FIFO_ADDR_MSB:REQ_FIFO_ADDR_LSB], 4'h0}           ;

    // write data chennel
    wire                        dram_wvalid     ;
    wire                        dram_wready     ;
    wire       [DATA_WIDTH-1:0] dram_wdata      ;
    wire       [STRB_WIDTH-1:0] dram_wstrb      ;

    assign dram_wvalid      = req_fifo_rvalid && (req_fifo_rdata[0]==1'b0)                          ;
    assign dram_wdata       = req_fifo_rdata[REQ_FIFO_DATA_MSB:REQ_FIFO_DATA_LSB]                   ;
    assign dram_wstrb       = req_fifo_rdata[REQ_FIFO_STRB_MSB:REQ_FIFO_STRB_LSB]                   ;

    // write response channel
    wire         [ID_WIDTH-1:0] dram_bid        ;
    wire                  [1:0] dram_bresp      ;
    wire                        dram_bvalid     ;
    wire                        dram_bready     ;

    assign dram_bready      = 1'b1              ;

    // read request channel
    wire                        dram_arvalid    ;
    wire                        dram_arready    ;
    wire       [ADDR_WIDTH-1:0] dram_araddr     ;
    wire                        req_is_read     ;

    assign dram_arvalid     = req_fifo_rvalid && (req_fifo_rdata[0]==1'b1)                          ;
    assign dram_araddr      = {req_fifo_rdata[REQ_FIFO_ADDR_MSB:REQ_FIFO_ADDR_LSB], 4'h0}           ;
    assign req_is_read      = req_fifo_rdata[0]                                                      ;

    // read data channel
    wire                        dram_rvalid     ;
    wire                        dram_rready     ;
    wire       [DATA_WIDTH-1:0] dram_rdata      ;
    wire         [ID_WIDTH-1:0] dram_rid        ;
    wire                  [1:0] dram_rresp      ;
    wire                        dram_rlast      ;

    assign req_fifo_rready  = req_fifo_rvalid &&
                              ((req_is_read && dram_arready) ||
                              (!req_is_read && dram_awready && dram_wready))                         ;

    assign rsp_fifo_wvalid  = dram_bvalid || dram_rvalid                                            ;
    assign dram_rready      = rsp_fifo_wready                                                       ;
    assign rsp_fifo_wdata   = {((dram_rvalid) ? dram_rresp : dram_bresp), dram_rdata, dram_rvalid}  ;

    // MIG: Xilinx Memory Interface Generator
    wire app_sr_active, app_ref_ack, app_zq_ack;
    mig_7series_0 u_mig_7series_0 (
        // Memory interface ports
`ifdef NEXYS // Nexys
        .ddr2_addr              (ddr2_addr              ), // output  [12:0] ddr2_addr
        .ddr2_ba                (ddr2_ba                ), // output   [2:0] ddr2_ba
        .ddr2_cas_n             (ddr2_cas_n             ), // output         ddr2_cas_n
        .ddr2_ck_n              (ddr2_ck_n              ), // output   [0:0] ddr2_ck_n
        .ddr2_ck_p              (ddr2_ck_p              ), // output   [0:0] ddr2_ck_p
        .ddr2_cke               (ddr2_cke               ), // output   [0:0] ddr2_cke
        .ddr2_ras_n             (ddr2_ras_n             ), // output         ddr2_ras_n
        .ddr2_we_n              (ddr2_we_n              ), // output         ddr2_we_n
        .ddr2_dq                (ddr2_dq                ), // inout   [15:0] ddr2_dq
        .ddr2_dqs_n             (ddr2_dqs_n             ), // inout    [1:0] ddr2_dqs_n
        .ddr2_dqs_p             (ddr2_dqs_p             ), // inout    [1:0] ddr2_dqs_p
        .init_calib_complete    (init_calib_complete    ), // output         init_calib_complete
        .ddr2_cs_n              (ddr2_cs_n              ), // output   [0:0] ddr2_cs_n
        .ddr2_dm                (ddr2_dm                ), // output   [1:0] ddr2_dm
        .ddr2_odt               (ddr2_odt               ), // output   [0:0] ddr2_odt
`else // DDR3, Arty
        .ddr3_addr              (ddr3_addr              ), // output  [13:0] ddr3_addr
        .ddr3_ba                (ddr3_ba                ), // output   [2:0] ddr3_ba
        .ddr3_cas_n             (ddr3_cas_n             ), // output         ddr3_cas_n
        .ddr3_ck_n              (ddr3_ck_n              ), // output   [0:0] ddr3_ck_n
        .ddr3_ck_p              (ddr3_ck_p              ), // output   [0:0] ddr3_ck_p
        .ddr3_cke               (ddr3_cke               ), // output   [0:0] ddr3_cke
        .ddr3_ras_n             (ddr3_ras_n             ), // output         ddr3_ras_n
        .ddr3_reset_n           (ddr3_reset_n           ), // output         ddr3_reset_n
        .ddr3_we_n              (ddr3_we_n              ), // output         ddr3_we_n
        .ddr3_dq                (ddr3_dq                ), // inout   [15:0] ddr3_dq
        .ddr3_dqs_n             (ddr3_dqs_n             ), // inout    [1:0] ddr3_dqs_n
        .ddr3_dqs_p             (ddr3_dqs_p             ), // inout    [1:0] ddr3_dqs_p
        .init_calib_complete    (init_calib_complete    ), // output         init_calib_complete
        .ddr3_cs_n              (ddr3_cs_n              ), // output   [0:0] ddr3_cs_n
        .ddr3_dm                (ddr3_dm                ), // output   [1:0] ddr3_dm
        .ddr3_odt               (ddr3_odt               ), // output   [0:0] ddr3_odt
`endif
        // Application interface ports
        .ui_clk                 (ui_clk                 ), // output         ui_clk
        .ui_clk_sync_rst        (ui_clk_sync_rst        ), // output         ui_clk_sync_rst
        .mmcm_locked            (mmcm_locked            ), // output         mmcm_locked
        .aresetn                (!sys_rst               ), // input          aresetn
        .app_sr_req             (1'b0                   ), // input          app_sr_req
        .app_ref_req            (1'b0                   ), // input          app_ref_req
        .app_zq_req             (1'b0                   ), // input          app_zq_req
        .app_sr_active          (app_sr_active          ), // output         app_sr_active
        .app_ref_ack            (app_ref_ack            ), // output         app_ref_ack
        .app_zq_ack             (app_zq_ack             ), // output         app_zq_ack
        // Slave Interface Write Address Ports
        .s_axi_awid             ('d0                    ), // input    [3:0] s_axi_awid
        .s_axi_awaddr           (dram_awaddr            ), // input   [27:0] s_axi_awaddr
        .s_axi_awlen            (8'h00                  ), // input    [7:0] s_axi_awlen
        .s_axi_awsize           (3'b111                 ), // input    [2:0] s_axi_awsize           // 3'b111 : 128-bit
        .s_axi_awburst          (2'b01                  ), // input    [1:0] s_axi_awburst          // 2'b01  : INCR (incrementing)
        .s_axi_awlock           (1'b0                   ), // input    [0:0] s_axi_awlock           // This is not used in the current mig implementation.
        .s_axi_awcache          (4'b0000                ), // input    [3:0] s_axi_awcache          // This is not used in the current mig implementation.
        .s_axi_awprot           (3'b000                 ), // input    [2:0] s_axi_awprot           // This is not used in the current mig implementation.
        .s_axi_awqos            (4'h0                   ), // input    [3:0] s_axi_awqos
        .s_axi_awvalid          (dram_awvalid           ), // input          s_axi_awvalid
        .s_axi_awready          (dram_awready           ), // output         s_axi_awready
        // Slave Interface Write Data Ports
        .s_axi_wdata            (dram_wdata             ), // input  [127:0] s_axi_wdata
        .s_axi_wstrb            (dram_wstrb             ), // input   [15:0] s_axi_wstrb
        .s_axi_wlast            (1'b1                   ), // input          s_axi_wlast
        .s_axi_wvalid           (dram_wvalid            ), // input          s_axi_wvalid
        .s_axi_wready           (dram_wready            ), // output         s_axi_wready
        // Slave Interface Write Response Ports
        .s_axi_bid              (dram_bid               ), // output   [3:0] s_axi_bid
        .s_axi_bresp            (dram_bresp             ), // output   [1:0] s_axi_bresp
        .s_axi_bvalid           (dram_bvalid            ), // output         s_axi_bvalid
        .s_axi_bready           (dram_bready            ), // input          s_axi_bready
        // Slave Interface Read Address Ports
        .s_axi_arid             ('d0                    ), // input    [3:0] s_axi_arid
        .s_axi_araddr           (dram_araddr            ), // input   [27:0] s_axi_araddr
        .s_axi_arlen            (8'h00                  ), // input    [7:0] s_axi_arlen
        .s_axi_arsize           (3'b111                 ), // input    [2:0] s_axi_arsize           // 3'b111 : 128-bit
        .s_axi_arburst          (2'b01                  ), // input    [1:0] s_axi_arburst          // 2'b01  : INCR (incrementing)
        .s_axi_arlock           (1'b0                   ), // input    [0:0] s_axi_arlock           // This is not used in the current mig implementation.
        .s_axi_arcache          (4'b0000                ), // input    [3:0] s_axi_arcache          // This is not used in the current mig implementation.
        .s_axi_arprot           (3'b000                 ), // input    [2:0] s_axi_arprot           // This is not used in the current mig implementation.
        .s_axi_arqos            (4'h0                   ), // input    [3:0] s_axi_arqos
        .s_axi_arvalid          (dram_arvalid           ), // input          s_axi_arvalid
        .s_axi_arready          (dram_arready           ), // output         s_axi_arready
        // Slave Interface Read Data Ports
        .s_axi_rid              (dram_rid               ), // output   [3:0] s_axi_rid
        .s_axi_rdata            (dram_rdata             ), // output [127:0] s_axi_rdata
        .s_axi_rresp            (dram_rresp             ), // output   [1:0] s_axi_rresp
        .s_axi_rlast            (dram_rlast             ), // output         s_axi_rlast
        .s_axi_rvalid           (dram_rvalid            ), // output         s_axi_rvalid
        .s_axi_rready           (dram_rready            ), // input          s_axi_rready
        // System Clock Ports
        .sys_clk_i              (sys_clk                ), // 166.66667 MHz
        // Reference Clock Ports
        .clk_ref_i              (clk_ref                ), // 200.00000 MHz
        .sys_rst                (sys_rst                )  // input          sys_rst
    );

endmodule
/******************************************************************************************/

`resetall
