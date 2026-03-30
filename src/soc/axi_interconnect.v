/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* advanced extension interface (AXI) interconnect */
/******************************************************************************************/
module axi_interconnect (
    input  wire                            clk_i                , // clock
    input  wire                            rst_i                , // reset
    output wire                            sw_rst_req_o         , // software reset request pulse
    // cpu interface
    input  wire                            cpu_wvalid_i         , // store request valid
    output wire                            cpu_wready_o         , // store request ready
    input  wire      [`BUS_ADDR_WIDTH-1:0] cpu_awaddr_i         , // store request address
    input  wire      [`BUS_DATA_WIDTH-1:0] cpu_wdata_i          , // store request data
    input  wire      [`BUS_STRB_WIDTH-1:0] cpu_wstrb_i          , // store request strobe
    output wire                            cpu_bvalid_o         , // store response valid
    input  wire                            cpu_bready_i         , // store response ready
    output wire         [`BRESP_WIDTH-1:0] cpu_bresp_o          , // store response status
    input  wire                            cpu_arvalid_i        , // read request valid
    output wire                            cpu_arready_o        , // read request ready
    input  wire      [`BUS_ADDR_WIDTH-1:0] cpu_araddr_i         , // read request address
    output wire                            cpu_rvalid_o         , // read response valid
    input  wire                            cpu_rready_i         , // read response ready
    output wire      [`BUS_DATA_WIDTH-1:0] cpu_rdata_o          , // read response data
    output wire         [`RRESP_WIDTH-1:0] cpu_rresp_o          , // read response status
    // bootrom interface
    output wire                            bootrom_arvalid_o    , // read request valid
    input  wire                            bootrom_arready_i    , // read request ready
    output wire  [`BOOTROM_ADDR_WIDTH-1:0] bootrom_araddr_o     , // read request address
    input  wire                            bootrom_rvalid_i     , // read response valid
    output wire                            bootrom_rready_o     , // read response ready
    input  wire  [`BOOTROM_DATA_WIDTH-1:0] bootrom_rdata_i      , // read response data
    input  wire         [`RRESP_WIDTH-1:0] bootrom_rresp_i      , // read response status
    // clint interface
    output wire                            clint_wvalid_o       , // write request valid
    input  wire                            clint_wready_i       , // write request ready
    output wire    [`CLINT_ADDR_WIDTH-1:0] clint_awaddr_o       , // write request address
    output wire    [`CLINT_DATA_WIDTH-1:0] clint_wdata_o        , // write request data
    output wire    [`CLINT_STRB_WIDTH-1:0] clint_wstrb_o        , // write request strobe
    input  wire                            clint_bvalid_i       , // write response valid
    output wire                            clint_bready_o       , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] clint_bresp_i        , // write response status
    output wire                            clint_arvalid_o      , // read request valid
    input  wire                            clint_arready_i      , // read request ready
    output wire    [`CLINT_ADDR_WIDTH-1:0] clint_araddr_o       , // read request address
    input  wire                            clint_rvalid_i       , // read response valid
    output wire                            clint_rready_o       , // read response ready
    input  wire    [`CLINT_DATA_WIDTH-1:0] clint_rdata_i        , // read response data
    input  wire         [`RRESP_WIDTH-1:0] clint_rresp_i        , // read response status
    // plic interface
    output wire                            plic_wvalid_o        , // write request valid
    input  wire                            plic_wready_i        , // write request ready
    output wire     [`PLIC_ADDR_WIDTH-1:0] plic_awaddr_o        , // write request address
    output wire     [`PLIC_DATA_WIDTH-1:0] plic_wdata_o         , // write request data
    output wire     [`PLIC_STRB_WIDTH-1:0] plic_wstrb_o         , // write request strobe
    input  wire                            plic_bvalid_i        , // write response valid
    output wire                            plic_bready_o        , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] plic_bresp_i         , // write response status
    output wire                            plic_arvalid_o       , // read request valid
    input  wire                            plic_arready_i       , // read request ready
    output wire     [`PLIC_ADDR_WIDTH-1:0] plic_araddr_o        , // read request address
    input  wire                            plic_rvalid_i        , // read response valid
    output wire                            plic_rready_o        , // read response ready
    input  wire     [`PLIC_DATA_WIDTH-1:0] plic_rdata_i         , // read response data
    input  wire         [`RRESP_WIDTH-1:0] plic_rresp_i         , // read response status
    // uart interface
    output wire                            uart_wvalid_o        , // write request valid
    input  wire                            uart_wready_i        , // write request ready
    output wire     [`UART_ADDR_WIDTH-1:0] uart_awaddr_o        , // write request address
    output wire     [`UART_DATA_WIDTH-1:0] uart_wdata_o         , // write request data
    output wire     [`UART_STRB_WIDTH-1:0] uart_wstrb_o         , // write request strobe
    input  wire                            uart_bvalid_i        , // write response valid
    output wire                            uart_bready_o        , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] uart_bresp_i         , // write response status
    output wire                            uart_arvalid_o       , // read request valid
    input  wire                            uart_arready_i       , // read request ready
    output wire     [`UART_ADDR_WIDTH-1:0] uart_araddr_o        , // read request address
    input  wire                            uart_rvalid_i        , // read response valid
    output wire                            uart_rready_o        , // read response ready
    input  wire     [`UART_DATA_WIDTH-1:0] uart_rdata_i         , // read response data
    input  wire         [`RRESP_WIDTH-1:0] uart_rresp_i         , // read response status
    // ether interface
    output wire                            ether_wvalid_o       , // write request valid
    input  wire                            ether_wready_i       , // write request ready
    output wire    [`ETHER_ADDR_WIDTH-1:0] ether_awaddr_o       , // write request address
    output wire    [`ETHER_DATA_WIDTH-1:0] ether_wdata_o        , // write request data
    output wire    [`ETHER_STRB_WIDTH-1:0] ether_wstrb_o        , // write request strobe
    input  wire                            ether_bvalid_i       , // write response valid
    output wire                            ether_bready_o       , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] ether_bresp_i        , // write response status
    output wire                            ether_arvalid_o      , // read request valid
    input  wire                            ether_arready_i      , // read request ready
    output wire    [`ETHER_ADDR_WIDTH-1:0] ether_araddr_o       , // read request address
    input  wire                            ether_rvalid_i       , // read response valid
    output wire                            ether_rready_o       , // read response ready
    input  wire    [`ETHER_DATA_WIDTH-1:0] ether_rdata_i        , // read response data
    input  wire         [`RRESP_WIDTH-1:0] ether_rresp_i        , // read response status
    // dram interface
    output wire                            dram_wvalid_o        , // write request valid
    input  wire                            dram_wready_i        , // write request ready
    output wire     [`DRAM_ADDR_WIDTH-1:0] dram_awaddr_o        , // write request address
    output wire     [`DRAM_DATA_WIDTH-1:0] dram_wdata_o         , // write request data
    output wire     [`DRAM_STRB_WIDTH-1:0] dram_wstrb_o         , // write request strobe
    input  wire                            dram_bvalid_i        , // write response valid
    output wire                            dram_bready_o        , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] dram_bresp_i         , // write response status
    output wire                            dram_arvalid_o       , // read request valid
    input  wire                            dram_arready_i       , // read request ready
    output wire     [`DRAM_ADDR_WIDTH-1:0] dram_araddr_o        , // read request address
    input  wire                            dram_rvalid_i        , // read response valid
    output wire                            dram_rready_o        , // read response ready
    input  wire     [`DRAM_DATA_WIDTH-1:0] dram_rdata_i         , // read response data
    input  wire         [`RRESP_WIDTH-1:0] dram_rresp_i           // read response status
`ifdef NEXYS
    ,
    // sdcram interface
    output wire                            sdcram_wvalid_o      , // write request valid
    input  wire                            sdcram_wready_i      , // write request ready
    output wire   [`SDCRAM_ADDR_WIDTH-1:0] sdcram_awaddr_o      , // write request address
    output wire   [`SDCRAM_DATA_WIDTH-1:0] sdcram_wdata_o       , // write request data
    output wire   [`SDCRAM_STRB_WIDTH-1:0] sdcram_wstrb_o       , // write request strobe
    input  wire                            sdcram_bvalid_i      , // write response valid
    output wire                            sdcram_bready_o      , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] sdcram_bresp_i       , // write response status
    output wire                            sdcram_arvalid_o     , // read request valid
    input  wire                            sdcram_arready_i     , // read request ready
    output wire   [`SDCRAM_ADDR_WIDTH-1:0] sdcram_araddr_o      , // read request address
    input  wire                            sdcram_rvalid_i      , // read response valid
    output wire                            sdcram_rready_o      , // read response ready
    input  wire   [`SDCRAM_DATA_WIDTH-1:0] sdcram_rdata_i       , // read response data
    input  wire         [`RRESP_WIDTH-1:0] sdcram_rresp_i       , // read response status
    // camera interface
    output wire                            camera_wvalid_o      , // write request valid
    input  wire                            camera_wready_i      , // write request ready
    output wire   [`CAMERA_ADDR_WIDTH-1:0] camera_awaddr_o      , // write request address
    output wire   [`CAMERA_DATA_WIDTH-1:0] camera_wdata_o       , // write request data
    output wire   [`CAMERA_STRB_WIDTH-1:0] camera_wstrb_o       , // write request strobe
    input  wire                            camera_bvalid_i      , // write response valid
    output wire                            camera_bready_o      , // write response ready
    input  wire         [`BRESP_WIDTH-1:0] camera_bresp_i       , // write response status
    output wire                            camera_arvalid_o     , // read request valid
    input  wire                            camera_arready_i     , // read request ready
    output wire   [`CAMERA_ADDR_WIDTH-1:0] camera_araddr_o      , // read request address
    input  wire                            camera_rvalid_i      , // read response valid
    output wire                            camera_rready_o      , // read response ready
    input  wire   [`CAMERA_DATA_WIDTH-1:0] camera_rdata_i       , // read response data
    input  wire         [`RRESP_WIDTH-1:0] camera_rresp_i         // read response status
`endif
);

//==============================================================================
// data bus control
//------------------------------------------------------------------------------
    localparam WR_IDLE     = 4'd0  ;
    localparam WR_CLINT    = 4'd1  ;
    localparam WR_PLIC     = 4'd2  ;
    localparam WR_UART     = 4'd3  ;
    localparam WR_ETHER    = 4'd4  ;
    localparam WR_DRAM     = 4'd5  ;
    localparam WR_SDCRAM   = 4'd6  ;
    localparam WR_CAMERA   = 4'd7  ;
    localparam WR_RET      = 4'd8  ;
    reg  [3:0] wr_state_q   , wr_state_d    ;

    localparam RD_IDLE     = 4'd0  ;
    localparam RD_BOOTROM  = 4'd1  ;
    localparam RD_CLINT    = 4'd2  ;
    localparam RD_PLIC     = 4'd3  ;
    localparam RD_UART     = 4'd4  ;
    localparam RD_ETHER    = 4'd5  ;
    localparam RD_DRAM     = 4'd6  ;
    localparam RD_SDCRAM   = 4'd7  ;
    localparam RD_CAMERA   = 4'd8  ;
    localparam RD_RET      = 4'd9  ;
    reg  [3:0] rd_state_q   , rd_state_d    ;

    assign cpu_wready_o     = (wr_state_q==WR_IDLE)   ;
    assign clint_bready_o   = (wr_state_q==WR_CLINT)  ;
    assign plic_bready_o    = (wr_state_q==WR_PLIC)   ;
    assign uart_bready_o    = (wr_state_q==WR_UART)   ;
    assign ether_bready_o   = (wr_state_q==WR_ETHER)  ;
    assign dram_bready_o    = (wr_state_q==WR_DRAM)   ;
    assign cpu_bvalid_o     = (wr_state_q==WR_RET)    ;

    assign cpu_arready_o    = (rd_state_q==RD_IDLE)   ;
    assign bootrom_rready_o = (rd_state_q==RD_BOOTROM);
    assign clint_rready_o   = (rd_state_q==RD_CLINT)  ;
    assign plic_rready_o    = (rd_state_q==RD_PLIC)   ;
    assign uart_rready_o    = (rd_state_q==RD_UART)   ;
    assign ether_rready_o   = (rd_state_q==RD_ETHER)  ;
    assign dram_rready_o    = (rd_state_q==RD_DRAM)   ;
    assign cpu_rvalid_o     = (rd_state_q==RD_RET)    ;

`ifdef NEXYS
    assign sdcram_bready_o  = (wr_state_q==WR_SDCRAM) ;
    assign sdcram_rready_o  = (rd_state_q==RD_SDCRAM) ;
    assign camera_bready_o  = (wr_state_q==WR_CAMERA) ;
    assign camera_rready_o  = (rd_state_q==RD_CAMERA) ;
`endif

//==============================================================================
// MMIO: Memory Mapped Input/Output
//==============================================================================
//  0x00010000 +---------------------------------------------------------------+
//             | bootrom                                                       |
//  0x00012000 +---------------------------------------------------------------+
//             |                                                               |
//  0x02000000 +---------------------------------------------------------------+
//             | clint                                                         |
//  0x020c0000 +---------------------------------------------------------------+
//             |                                                               |
//  0x0c000000 +---------------------------------------------------------------+
//             | plic                                                          |
//  0x0d000000 +---------------------------------------------------------------+
//             |                                                               |
//  0x10000000 +---------------------------------------------------------------+
//             | uart                                                          |
//  0x10000010 +---------------------------------------------------------------+
//             |                                                               |
//  0x10000100 +---------------------------------------------------------------+
//             | software reset control                                        |
//  0x10000104 +---------------------------------------------------------------+
//             |                                                               |
//  0x14000000 +---------------------------------------------------------------+
//             | ethernet CSR                                                  |
//  0x14004000 +---------------------------------------------------------------+
//             |                                                               |
//  0x18000000 +---------------------------------------------------------------+
//             | ethernet RX buffer                                            |
//  0x18000000 + size(rx) +----------------------------------------------------+
//             |                                                               |
//  0x1c000000 +---------------------------------------------------------------+
//             | ethernet TX buffer                                            |
//  0x1c000000 + size(tx) +----------------------------------------------------+
//             |                                                               |
//  0x80000000 +---------------------------------------------------------------+
//             | data memory                                                   |
//  0x90000000 +---------------------------------------------------------------+
//             |                                                               |
//  0xa0000000 +---------------------------------------------------------------+
//             | sdcram memory                                                 |
//  0xafffffff +---------------------------------------------------------------+
//             | camera CSR                                                    |
//  0xb0001000 +---------------------------------------------------------------+
//             |                                                               |
//  0xb0010000 +---------------------------------------------------------------+
//             | camera frame aperture                                         |
//  0xb0030000 +---------------------------------------------------------------+
//==============================================================================
    // write
    reg                          clint_wvalid_q     , clint_wvalid_d    ;
    reg  [`CLINT_ADDR_WIDTH-1:0] clint_awaddr_q     , clint_awaddr_d    ;
    reg  [`CLINT_DATA_WIDTH-1:0] clint_wdata_q      , clint_wdata_d     ;
    reg  [`CLINT_STRB_WIDTH-1:0] clint_wstrb_q      , clint_wstrb_d     ;

    reg                          plic_wvalid_q      , plic_wvalid_d     ;
    reg   [`PLIC_ADDR_WIDTH-1:0] plic_awaddr_q      , plic_awaddr_d     ;
    reg   [`PLIC_DATA_WIDTH-1:0] plic_wdata_q       , plic_wdata_d      ;
    reg   [`PLIC_STRB_WIDTH-1:0] plic_wstrb_q       , plic_wstrb_d      ;

    reg                          uart_wvalid_q      , uart_wvalid_d     ;
    reg   [`UART_ADDR_WIDTH-1:0] uart_awaddr_q      , uart_awaddr_d     ;
    reg   [`UART_DATA_WIDTH-1:0] uart_wdata_q       , uart_wdata_d      ;
    reg   [`UART_STRB_WIDTH-1:0] uart_wstrb_q       , uart_wstrb_d      ;

    reg                          ether_wvalid_q     , ether_wvalid_d    ;
    reg  [`ETHER_ADDR_WIDTH-1:0] ether_awaddr_q     , ether_awaddr_d    ;
    reg  [`ETHER_DATA_WIDTH-1:0] ether_wdata_q      , ether_wdata_d     ;
    reg  [`ETHER_STRB_WIDTH-1:0] ether_wstrb_q      , ether_wstrb_d     ;

    reg                          dram_wvalid_q      , dram_wvalid_d     ;
    reg   [`DRAM_ADDR_WIDTH-1:0] dram_awaddr_q      , dram_awaddr_d     ;
    reg   [`DRAM_DATA_WIDTH-1:0] dram_wdata_q       , dram_wdata_d      ;
    reg   [`DRAM_STRB_WIDTH-1:0] dram_wstrb_q       , dram_wstrb_d      ;

    reg                          sdcram_wvalid_q    , sdcram_wvalid_d   ;
    reg [`SDCRAM_ADDR_WIDTH-1:0] sdcram_awaddr_q    , sdcram_awaddr_d   ;
    reg [`SDCRAM_DATA_WIDTH-1:0] sdcram_wdata_q     , sdcram_wdata_d    ;
    reg [`SDCRAM_STRB_WIDTH-1:0] sdcram_wstrb_q     , sdcram_wstrb_d    ;
    reg                          camera_wvalid_q    , camera_wvalid_d   ;
    reg [`CAMERA_ADDR_WIDTH-1:0] camera_awaddr_q    , camera_awaddr_d   ;
    reg [`CAMERA_DATA_WIDTH-1:0] camera_wdata_q     , camera_wdata_d    ;
    reg [`CAMERA_STRB_WIDTH-1:0] camera_wstrb_q     , camera_wstrb_d    ;

    reg                          sw_rst_req_q       , sw_rst_req_d      ;

    reg       [`BRESP_WIDTH-1:0] cpu_bresp_q        , cpu_bresp_d       ;

    assign clint_wvalid_o   = clint_wvalid_q    ;
    assign clint_awaddr_o   = clint_awaddr_q    ;
    assign clint_wdata_o    = clint_wdata_q     ;
    assign clint_wstrb_o    = clint_wstrb_q     ;

    assign plic_wvalid_o    = plic_wvalid_q     ;
    assign plic_awaddr_o    = plic_awaddr_q     ;
    assign plic_wdata_o     = plic_wdata_q      ;
    assign plic_wstrb_o     = plic_wstrb_q      ;

    assign uart_wvalid_o    = uart_wvalid_q     ;
    assign uart_awaddr_o    = uart_awaddr_q     ;
    assign uart_wdata_o     = uart_wdata_q      ;
    assign uart_wstrb_o     = uart_wstrb_q      ;

    assign ether_wvalid_o   = ether_wvalid_q    ;
    assign ether_awaddr_o   = ether_awaddr_q    ;
    assign ether_wdata_o    = ether_wdata_q     ;
    assign ether_wstrb_o    = ether_wstrb_q     ;

    assign dram_wvalid_o    = dram_wvalid_q     ;
    assign dram_awaddr_o    = dram_awaddr_q     ;
    assign dram_wdata_o     = dram_wdata_q      ;
    assign dram_wstrb_o     = dram_wstrb_q      ;

`ifdef NEXYS
    assign sdcram_wvalid_o  = sdcram_wvalid_q   ;
    assign sdcram_awaddr_o  = sdcram_awaddr_q   ;
    assign sdcram_wdata_o   = sdcram_wdata_q    ;
    assign sdcram_wstrb_o   = sdcram_wstrb_q    ;
    assign camera_wvalid_o  = camera_wvalid_q   ;
    assign camera_awaddr_o  = camera_awaddr_q   ;
    assign camera_wdata_o   = camera_wdata_q    ;
    assign camera_wstrb_o   = camera_wstrb_q    ;
`endif

    assign sw_rst_req_o     = sw_rst_req_q      ;
    assign cpu_bresp_o      = cpu_bresp_q       ;

    always @(*) begin
        clint_wvalid_d      = clint_wvalid_q    ;
        clint_awaddr_d      = clint_awaddr_q    ;
        clint_wdata_d       = clint_wdata_q     ;
        clint_wstrb_d       = clint_wstrb_q     ;
        plic_wvalid_d       = plic_wvalid_q     ;
        plic_awaddr_d       = plic_awaddr_q     ;
        plic_wdata_d        = plic_wdata_q      ;
        plic_wstrb_d        = plic_wstrb_q      ;
        uart_wvalid_d       = uart_wvalid_q     ;
        uart_awaddr_d       = uart_awaddr_q     ;
        uart_wdata_d        = uart_wdata_q      ;
        uart_wstrb_d        = uart_wstrb_q      ;
        ether_wvalid_d      = ether_wvalid_q    ;
        ether_awaddr_d      = ether_awaddr_q    ;
        ether_wdata_d       = ether_wdata_q     ;
        ether_wstrb_d       = ether_wstrb_q     ;
        dram_wvalid_d       = dram_wvalid_q     ;
        dram_awaddr_d       = dram_awaddr_q     ;
        dram_wdata_d        = dram_wdata_q      ;
        dram_wstrb_d        = dram_wstrb_q      ;
        sdcram_wvalid_d     = sdcram_wvalid_q   ;
        sdcram_awaddr_d     = sdcram_awaddr_q   ;
        sdcram_wdata_d      = sdcram_wdata_q    ;
        sdcram_wstrb_d      = sdcram_wstrb_q    ;
        camera_wvalid_d     = camera_wvalid_q   ;
        camera_awaddr_d     = camera_awaddr_q   ;
        camera_wdata_d      = camera_wdata_q    ;
        camera_wstrb_d      = camera_wstrb_q    ;
        sw_rst_req_d        = 1'b0              ;
        cpu_bresp_d         = cpu_bresp_q       ;
        wr_state_d          = wr_state_q        ;
        case (wr_state_q)
            WR_IDLE    : begin
                if (cpu_wvalid_i) begin
                    case (cpu_awaddr_i[`PLEN-1:28])
                        'h0     : begin
                            case (cpu_awaddr_i[27:24])
                                4'h2    : begin // clint (0x02000000-0x020c0000)
                                    clint_wvalid_d  = 1'b1                                  ;
                                    clint_awaddr_d  = cpu_awaddr_i[`CLINT_ADDR_WIDTH-1:0]   ;
                                    clint_wdata_d   = cpu_wdata_i[`CLINT_DATA_WIDTH-1:0]    ;
                                    clint_wstrb_d   = cpu_wstrb_i[`CLINT_STRB_WIDTH-1:0]    ;
                                    wr_state_d      = WR_CLINT                              ;
                                end
                                4'hc    : begin // plic  (0x0c000000-0x0d000000)
                                    plic_wvalid_d   = 1'b1                                  ;
                                    plic_awaddr_d   = cpu_awaddr_i[`PLIC_ADDR_WIDTH-1:0]    ;
                                    plic_wdata_d    = cpu_wdata_i[`PLIC_DATA_WIDTH-1:0]     ;
                                    plic_wstrb_d    = cpu_wstrb_i[`PLIC_STRB_WIDTH-1:0]     ;
                                    wr_state_d      = WR_PLIC                               ;
                                end
                                default : begin
                                    cpu_bresp_d     = `BRESP_DECERR                         ;
                                    wr_state_d      = WR_RET                                ;
                                end
                            endcase
                        end
                        'h1     : begin
                            case (cpu_awaddr_i[27:26])
                                2'd1: begin // ether CSR (0x14000000-0x14003fff)
                                    if (cpu_awaddr_i<(`ETHER_CSR_BASE+`ETHER_CSR_SIZE)) begin
                                        ether_wvalid_d  = 1'b1                                  ;
                                        ether_awaddr_d  = cpu_awaddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        ether_wdata_d   = cpu_wdata_i[`ETHER_DATA_WIDTH-1:0]    ;
                                        ether_wstrb_d   = cpu_wstrb_i[`ETHER_STRB_WIDTH-1:0]    ;
                                        wr_state_d      = WR_ETHER                              ;
                                    end else begin
                                        cpu_bresp_d     = `BRESP_DECERR                         ;
                                        wr_state_d      = WR_RET                                ;
                                    end
                                end
                                2'd2: begin // ether RX buffer (0x18000000-...)
                                    if (cpu_awaddr_i<(`ETHER_RXBUF_BASE+`ETHER_RXBUF_SIZE)) begin
                                        ether_wvalid_d  = 1'b1                                  ;
                                        ether_awaddr_d  = cpu_awaddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        ether_wdata_d   = cpu_wdata_i[`ETHER_DATA_WIDTH-1:0]    ;
                                        ether_wstrb_d   = cpu_wstrb_i[`ETHER_STRB_WIDTH-1:0]    ;
                                        wr_state_d      = WR_ETHER                              ;
                                    end else begin
                                        cpu_bresp_d     = `BRESP_DECERR                         ;
                                        wr_state_d      = WR_RET                                ;
                                    end
                                end
                                2'd3: begin // ether TX buffer (0x1c000000-...)
                                    if (cpu_awaddr_i<(`ETHER_TXBUF_BASE+`ETHER_TXBUF_SIZE)) begin
                                        ether_wvalid_d  = 1'b1                                  ;
                                        ether_awaddr_d  = cpu_awaddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        ether_wdata_d   = cpu_wdata_i[`ETHER_DATA_WIDTH-1:0]    ;
                                        ether_wstrb_d   = cpu_wstrb_i[`ETHER_STRB_WIDTH-1:0]    ;
                                        wr_state_d      = WR_ETHER                              ;
                                    end else begin
                                        cpu_bresp_d     = `BRESP_DECERR                         ;
                                        wr_state_d      = WR_RET                                ;
                                    end
                                end
                                2'd0    : begin
                                    case (cpu_awaddr_i[13:4])
                                        8'h0    : begin // uart (0x10000000-0x1000000f)
                                            uart_wvalid_d   = 1'b1                                  ;
                                            uart_awaddr_d   = cpu_awaddr_i[`UART_ADDR_WIDTH-1:0]    ;
                                            uart_wdata_d    = cpu_wdata_i[`UART_DATA_WIDTH-1:0]     ;
                                            uart_wstrb_d    = cpu_wstrb_i[`UART_STRB_WIDTH-1:0]     ;
                                            wr_state_d      = WR_UART                               ;
                                        end
                                        10'h10 : begin // sw reset ctrl (0x10000100)
                                            sw_rst_req_d    = 1'b1                                  ;
                                            cpu_bresp_d     = `BRESP_OKAY                           ;
                                            wr_state_d      = WR_RET                                ;
                                        end
                                        default : begin
                                            cpu_bresp_d     = `BRESP_DECERR                         ;
                                            wr_state_d      = WR_RET                                ;
                                        end
                                    endcase
                                end
                            endcase
                        end
                        'h7, 'h8: begin // dram (0x80000000-0x90000000), 'h7 is needed to output signeture
                            dram_wvalid_d   = 1'b1                                  ;
                            dram_awaddr_d   = cpu_awaddr_i[`DRAM_ADDR_WIDTH-1:0]    ;
                            dram_wdata_d    = cpu_wdata_i[`DRAM_DATA_WIDTH-1:0]     ;
                            dram_wstrb_d    = cpu_wstrb_i[`DRAM_STRB_WIDTH-1:0]     ;
                            wr_state_d      = WR_DRAM                               ;
                        end
`ifdef NEXYS
                        'ha     : begin // sdcram (0xa0000000-0xafffffff)
                            sdcram_wvalid_d = 1'b1                                  ;
                            sdcram_awaddr_d = cpu_awaddr_i[`SDCRAM_ADDR_WIDTH-1:0]  ;
                            sdcram_wdata_d  = cpu_wdata_i[`SDCRAM_DATA_WIDTH-1:0]   ;
                            sdcram_wstrb_d  = cpu_wstrb_i[`SDCRAM_STRB_WIDTH-1:0]   ;
                            wr_state_d      = WR_SDCRAM                             ;
                        end
                        'hb     : begin // camera (0xb0000000-0xbfffffff, sparse)
                            camera_wvalid_d = 1'b1                                  ;
                            camera_awaddr_d = cpu_awaddr_i[`CAMERA_ADDR_WIDTH-1:0]  ;
                            camera_wdata_d  = cpu_wdata_i[`CAMERA_DATA_WIDTH-1:0]   ;
                            camera_wstrb_d  = cpu_wstrb_i[`CAMERA_STRB_WIDTH-1:0]   ;
                            wr_state_d      = WR_CAMERA                             ;
                        end
`endif
                        default : begin
                            cpu_bresp_d     = `BRESP_DECERR                         ;
                            wr_state_d      = WR_RET                                ;
                        end
                    endcase
                end
            end
            WR_CLINT   : begin
                if (clint_wready_i) begin
                    clint_wvalid_d  = 1'b0          ;
                end
                if (clint_bvalid_i) begin
                    cpu_bresp_d     = clint_bresp_i ;
                    wr_state_d      = WR_RET        ;
                end
            end
            WR_PLIC    : begin
                if (plic_wready_i) begin
                    plic_wvalid_d   = 1'b0          ;
                end
                if (plic_bvalid_i) begin
                    cpu_bresp_d     = plic_bresp_i  ;
                    wr_state_d      = WR_RET        ;
                end
            end
            WR_UART    : begin
                if (uart_wready_i) begin
                    uart_wvalid_d   = 1'b0          ;
                end
                if (uart_bvalid_i) begin
                    cpu_bresp_d     = uart_bresp_i  ;
                    wr_state_d      = WR_RET        ;
                end
            end
            WR_ETHER   : begin
                if (ether_wready_i) begin
                    ether_wvalid_d  = 1'b0          ;
                end
                if (ether_bvalid_i) begin
                    cpu_bresp_d     = ether_bresp_i ;
                    wr_state_d      = WR_RET        ;
                end
            end
            WR_DRAM    : begin
                if (dram_wready_i) begin
                    dram_wvalid_d   = 1'b0          ;
                end
                if (dram_bvalid_i) begin
                    cpu_bresp_d     = dram_bresp_i  ;
                    wr_state_d      = WR_RET        ;
                end
            end
`ifdef NEXYS
            WR_SDCRAM  : begin
                if (sdcram_wready_i) begin
                    sdcram_wvalid_d = 1'b0          ;
                end
                if (sdcram_bvalid_i) begin
                    cpu_bresp_d     = sdcram_bresp_i ;
                    wr_state_d      = WR_RET        ;
                end
            end
            WR_CAMERA  : begin
                if (camera_wready_i) begin
                    camera_wvalid_d = 1'b0          ;
                end
                if (camera_bvalid_i) begin
                    cpu_bresp_d     = camera_bresp_i;
                    wr_state_d      = WR_RET        ;
                end
            end
`endif
            WR_RET     : begin
                if (cpu_bready_i) begin
                    wr_state_d      = WR_IDLE       ;
                end
            end
            default         : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            clint_wvalid_q      <= 1'b0                 ;
            plic_wvalid_q       <= 1'b0                 ;
            uart_wvalid_q       <= 1'b0                 ;
            ether_wvalid_q      <= 1'b0                 ;
            dram_wvalid_q       <= 1'b0                 ;
            sdcram_wvalid_q     <= 1'b0                 ;
            camera_wvalid_q     <= 1'b0                 ;
            sw_rst_req_q        <= 1'b0                 ;
            wr_state_q          <= WR_IDLE              ;
        end else begin
            clint_wvalid_q      <= clint_wvalid_d       ;
            clint_awaddr_q      <= clint_awaddr_d       ;
            clint_wdata_q       <= clint_wdata_d        ;
            clint_wstrb_q       <= clint_wstrb_d        ;
            plic_wvalid_q       <= plic_wvalid_d        ;
            plic_awaddr_q       <= plic_awaddr_d        ;
            plic_wdata_q        <= plic_wdata_d         ;
            plic_wstrb_q        <= plic_wstrb_d         ;
            uart_wvalid_q       <= uart_wvalid_d        ;
            uart_awaddr_q       <= uart_awaddr_d        ;
            uart_wdata_q        <= uart_wdata_d         ;
            uart_wstrb_q        <= uart_wstrb_d         ;
            ether_wvalid_q      <= ether_wvalid_d       ;
            ether_awaddr_q      <= ether_awaddr_d       ;
            ether_wdata_q       <= ether_wdata_d        ;
            ether_wstrb_q       <= ether_wstrb_d        ;
            dram_wvalid_q       <= dram_wvalid_d        ;
            dram_awaddr_q       <= dram_awaddr_d        ;
            dram_wdata_q        <= dram_wdata_d         ;
            dram_wstrb_q        <= dram_wstrb_d         ;
            sdcram_wvalid_q     <= sdcram_wvalid_d      ;
            sdcram_awaddr_q     <= sdcram_awaddr_d      ;
            sdcram_wdata_q      <= sdcram_wdata_d       ;
            sdcram_wstrb_q      <= sdcram_wstrb_d       ;
            camera_wvalid_q     <= camera_wvalid_d      ;
            camera_awaddr_q     <= camera_awaddr_d      ;
            camera_wdata_q      <= camera_wdata_d       ;
            camera_wstrb_q      <= camera_wstrb_d       ;
            sw_rst_req_q        <= sw_rst_req_d         ;
            cpu_bresp_q         <= cpu_bresp_d          ;
            wr_state_q          <= wr_state_d           ;
        end
    end

    // read
    reg                            bootrom_arvalid_q    , bootrom_arvalid_d     ;
    reg  [`BOOTROM_ADDR_WIDTH-1:0] bootrom_araddr_q     , bootrom_araddr_d      ;

    reg                            clint_arvalid_q      , clint_arvalid_d       ;
    reg    [`CLINT_ADDR_WIDTH-1:0] clint_araddr_q       , clint_araddr_d        ;

    reg                            plic_arvalid_q       , plic_arvalid_d        ;
    reg     [`PLIC_ADDR_WIDTH-1:0] plic_araddr_q        , plic_araddr_d         ;

    reg                            uart_arvalid_q       , uart_arvalid_d        ;
    reg     [`UART_ADDR_WIDTH-1:0] uart_araddr_q        , uart_araddr_d         ;

    reg                            ether_arvalid_q      , ether_arvalid_d       ;
    reg   [`ETHER_ADDR_WIDTH-1:0]  ether_araddr_q       , ether_araddr_d        ;

    reg                            dram_arvalid_q       , dram_arvalid_d        ;
    reg     [`DRAM_ADDR_WIDTH-1:0] dram_araddr_q        , dram_araddr_d         ;

    reg                            sdcram_arvalid_q     , sdcram_arvalid_d      ;
    reg   [`SDCRAM_ADDR_WIDTH-1:0] sdcram_araddr_q      , sdcram_araddr_d       ;
    reg                            camera_arvalid_q     , camera_arvalid_d      ;
    reg   [`CAMERA_ADDR_WIDTH-1:0] camera_araddr_q      , camera_araddr_d       ;

    reg      [`BUS_DATA_WIDTH-1:0] cpu_rdata_q          , cpu_rdata_d           ;
    reg         [`RRESP_WIDTH-1:0] cpu_rresp_q          , cpu_rresp_d           ;

    assign bootrom_arvalid_o    = bootrom_arvalid_q     ;
    assign bootrom_araddr_o     = bootrom_araddr_q      ;

    assign clint_arvalid_o      = clint_arvalid_q       ;
    assign clint_araddr_o       = clint_araddr_q        ;

    assign plic_arvalid_o       = plic_arvalid_q        ;
    assign plic_araddr_o        = plic_araddr_q         ;

    assign uart_arvalid_o       = uart_arvalid_q        ;
    assign uart_araddr_o        = uart_araddr_q         ;

    assign ether_arvalid_o      = ether_arvalid_q       ;
    assign ether_araddr_o       = ether_araddr_q        ;

    assign dram_arvalid_o       = dram_arvalid_q        ;
    assign dram_araddr_o        = dram_araddr_q         ;

`ifdef NEXYS
    assign sdcram_arvalid_o     = sdcram_arvalid_q      ;
    assign sdcram_araddr_o      = sdcram_araddr_q       ;
    assign camera_arvalid_o     = camera_arvalid_q      ;
    assign camera_araddr_o      = camera_araddr_q       ;
`endif

    assign cpu_rdata_o          = cpu_rdata_q           ;
    assign cpu_rresp_o          = cpu_rresp_q           ;

    always @(*) begin
        bootrom_arvalid_d   = bootrom_arvalid_q     ;
        bootrom_araddr_d    = bootrom_araddr_q      ;
        clint_arvalid_d     = clint_arvalid_q       ;
        clint_araddr_d      = clint_araddr_q        ;
        plic_arvalid_d      = plic_arvalid_q        ;
        plic_araddr_d       = plic_araddr_q         ;
        uart_arvalid_d      = uart_arvalid_q        ;
        uart_araddr_d       = uart_araddr_q         ;
        ether_arvalid_d     = ether_arvalid_q       ;
        ether_araddr_d      = ether_araddr_q        ;
        dram_arvalid_d      = dram_arvalid_q        ;
        dram_araddr_d       = dram_araddr_q         ;
`ifdef NEXYS
        sdcram_arvalid_d    = sdcram_arvalid_q      ;
        sdcram_araddr_d     = sdcram_araddr_q       ;
        camera_arvalid_d    = camera_arvalid_q      ;
        camera_araddr_d     = camera_araddr_q       ;
`endif
        cpu_rdata_d         = cpu_rdata_q           ;
        cpu_rresp_d         = cpu_rresp_q           ;
        rd_state_d          = rd_state_q            ;
        case (rd_state_q)
            RD_IDLE    : begin
                if (cpu_arvalid_i) begin
                    case (cpu_araddr_i[`PLEN-1:28])
                        'h0     : begin
                            case (cpu_araddr_i[27:24])
                                4'h0    : begin
                                    case (cpu_araddr_i[23:16])
                                        8'h01   : begin // bootrom (0x00010000-0x00012000)
                                            bootrom_arvalid_d   = 1'b1                                  ;
                                            bootrom_araddr_d    = cpu_araddr_i[`BOOTROM_ADDR_WIDTH-1:0] ;
                                            rd_state_d          = RD_BOOTROM                            ;
                                        end
                                        default : begin
                                            cpu_rresp_d         = `RRESP_DECERR                         ;
                                            rd_state_d          = RD_RET                                ;
                                        end
                                    endcase
                                end
                                4'h2    : begin // clint (0x02000000-0x020c0000)
                                    clint_arvalid_d     = 1'b1                                  ;
                                    clint_araddr_d      = cpu_araddr_i[`CLINT_ADDR_WIDTH-1:0]   ;
                                    rd_state_d          = RD_CLINT                              ;
                                end
                                4'hc    : begin // plic  (0x0c000000-0x0d000000)
                                    plic_arvalid_d      = 1'b1                                  ;
                                    plic_araddr_d       = cpu_araddr_i[`PLIC_ADDR_WIDTH-1:0]    ;
                                    rd_state_d          = RD_PLIC                               ;
                                end
                                default : begin
                                    cpu_rresp_d         = `RRESP_DECERR                         ;
                                    rd_state_d          = RD_RET                                ;
                                end
                            endcase
                        end
                        'h1     : begin
                            case (cpu_araddr_i[27:26])
                                2'd1: begin // ether CSR (0x14000000-0x14003fff)
                                    if (cpu_araddr_i<(`ETHER_CSR_BASE+`ETHER_CSR_SIZE)) begin
                                        ether_arvalid_d     = 1'b1                                  ;
                                        ether_araddr_d      = cpu_araddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        rd_state_d          = RD_ETHER                              ;
                                    end else begin
                                        cpu_rresp_d         = `RRESP_DECERR                         ;
                                        rd_state_d          = RD_RET                                ;
                                    end
                                end
                                2'd2: begin // ether RX buffer (0x18000000-...)
                                    if (cpu_araddr_i<(`ETHER_RXBUF_BASE+`ETHER_RXBUF_SIZE)) begin
                                        ether_arvalid_d     = 1'b1                                  ;
                                        ether_araddr_d      = cpu_araddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        rd_state_d          = RD_ETHER                              ;
                                    end else begin
                                        cpu_rresp_d         = `RRESP_DECERR                         ;
                                        rd_state_d          = RD_RET                                ;
                                    end
                                end
                                2'd3: begin // ether TX buffer (0x1c000000-...)
                                    if (cpu_araddr_i<(`ETHER_TXBUF_BASE+`ETHER_TXBUF_SIZE)) begin
                                        ether_arvalid_d     = 1'b1                                  ;
                                        ether_araddr_d      = cpu_araddr_i[`ETHER_ADDR_WIDTH-1:0]   ;
                                        rd_state_d          = RD_ETHER                              ;
                                    end else begin
                                        cpu_rresp_d         = `RRESP_DECERR                         ;
                                        rd_state_d          = RD_RET                                ;
                                    end
                                end
                                2'd0    : begin
                                    case (cpu_araddr_i[14:4])
                                        8'h0    : begin // uart (0x10000000-0x1000000f)
                                            uart_arvalid_d      = 1'b1                                  ;
                                            uart_araddr_d       = cpu_araddr_i[`UART_ADDR_WIDTH-1:0]    ;
                                            rd_state_d          = RD_UART                               ;
                                        end
                                        11'h10 : begin // sw reset ctrl (0x10000100)
                                            cpu_rdata_d         = 'h0                                   ;
                                            cpu_rresp_d         = `RRESP_OKAY                           ;
                                            rd_state_d          = RD_RET                                ;
                                        end
                                        default : begin
                                            cpu_rresp_d         = `RRESP_DECERR                         ;
                                            rd_state_d          = RD_RET                                ;
                                        end
                                    endcase
                                end
                            endcase
                        end
                        'h8     : begin // dram (0x80000000-0x90000000)
                            dram_arvalid_d      = 1'b1                                  ;
                            dram_araddr_d       = cpu_araddr_i[`DRAM_ADDR_WIDTH-1:0]    ;
                            rd_state_d          = RD_DRAM                               ;
                        end
`ifdef NEXYS
                        'ha     : begin // sdcram (0xa0000000-0xafffffff)
                            sdcram_arvalid_d    = 1'b1                                  ;
                            sdcram_araddr_d     = cpu_araddr_i[`SDCRAM_ADDR_WIDTH-1:0]  ;
                            rd_state_d          = RD_SDCRAM                             ;
                        end
                        'hb     : begin // camera (0xb0000000-0xbfffffff, sparse)
                            camera_arvalid_d    = 1'b1                                  ;
                            camera_araddr_d     = cpu_araddr_i[`CAMERA_ADDR_WIDTH-1:0]  ;
                            rd_state_d          = RD_CAMERA                             ;
                        end
`endif
                        default : begin
                            cpu_rresp_d         = `RRESP_DECERR                         ;
                            rd_state_d          = RD_RET                                ;
                        end
                    endcase
                end
            end
            RD_BOOTROM : begin
                if (bootrom_arready_i) begin
                    bootrom_arvalid_d   = 1'b0              ;
                end
                if (bootrom_rvalid_i) begin
                    cpu_rdata_d         = bootrom_rdata_i   ;
                    cpu_rresp_d         = bootrom_rresp_i   ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_CLINT   : begin
                if (clint_arready_i) begin
                    clint_arvalid_d     = 1'b0              ;
                end
                if (clint_rvalid_i) begin
                    cpu_rdata_d         = clint_rdata_i     ;
                    cpu_rresp_d         = clint_rresp_i     ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_PLIC   : begin
                if (plic_arready_i) begin
                    plic_arvalid_d      = 1'b0              ;
                end
                if (plic_rvalid_i) begin
                    cpu_rdata_d         = plic_rdata_i      ;
                    cpu_rresp_d         = plic_rresp_i      ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_UART   : begin
                if (uart_arready_i) begin
                    uart_arvalid_d      = 1'b0              ;
                end
                if (uart_rvalid_i) begin
                    cpu_rdata_d         = uart_rdata_i      ;
                    cpu_rresp_d         = uart_rresp_i      ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_ETHER  : begin
                if (ether_arready_i) begin
                    ether_arvalid_d     = 1'b0              ;
                end
                if (ether_rvalid_i) begin
                    cpu_rdata_d         = ether_rdata_i     ;
                    cpu_rresp_d         = ether_rresp_i     ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_DRAM    : begin
                if (dram_arready_i) begin
                    dram_arvalid_d      = 1'b0              ;
                end
                if (dram_rvalid_i) begin
                    cpu_rdata_d         = dram_rdata_i      ;
                    cpu_rresp_d         = dram_rresp_i      ;
                    rd_state_d          = RD_RET            ;
                end
            end
`ifdef NEXYS
            RD_SDCRAM  : begin
                if (sdcram_arready_i) begin
                    sdcram_arvalid_d    = 1'b0              ;
                end
                if (sdcram_rvalid_i) begin
                    cpu_rdata_d         = sdcram_rdata_i    ;
                    cpu_rresp_d         = sdcram_rresp_i    ;
                    rd_state_d          = RD_RET            ;
                end
            end
            RD_CAMERA  : begin
                if (camera_arready_i) begin
                    camera_arvalid_d    = 1'b0              ;
                end
                if (camera_rvalid_i) begin
                    cpu_rdata_d         = camera_rdata_i    ;
                    cpu_rresp_d         = camera_rresp_i    ;
                    rd_state_d          = RD_RET            ;
                end
            end
`endif
            RD_RET     : begin
                if (cpu_rready_i) begin
                    rd_state_d          = RD_IDLE           ;
                end
            end
            default         : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            bootrom_arvalid_q   <= 1'b0                 ;
            clint_arvalid_q     <= 1'b0                 ;
            plic_arvalid_q      <= 1'b0                 ;
            uart_arvalid_q      <= 1'b0                 ;
            ether_arvalid_q     <= 1'b0                 ;
            dram_arvalid_q      <= 1'b0                 ;
`ifdef NEXYS
            sdcram_arvalid_q    <= 1'b0                 ;
            camera_arvalid_q    <= 1'b0                 ;
`endif
            rd_state_q          <= RD_IDLE              ;
        end else begin
            bootrom_arvalid_q   <= bootrom_arvalid_d    ;
            bootrom_araddr_q    <= bootrom_araddr_d     ;
            clint_arvalid_q     <= clint_arvalid_d      ;
            clint_araddr_q      <= clint_araddr_d       ;
            plic_arvalid_q      <= plic_arvalid_d       ;
            plic_araddr_q       <= plic_araddr_d        ;
            uart_arvalid_q      <= uart_arvalid_d       ;
            uart_araddr_q       <= uart_araddr_d        ;
            ether_arvalid_q     <= ether_arvalid_d      ;
            ether_araddr_q      <= ether_araddr_d       ;
            dram_arvalid_q      <= dram_arvalid_d       ;
            dram_araddr_q       <= dram_araddr_d        ;
`ifdef NEXYS
            sdcram_arvalid_q    <= sdcram_arvalid_d     ;
            sdcram_araddr_q     <= sdcram_araddr_d      ;
            camera_arvalid_q    <= camera_arvalid_d     ;
            camera_araddr_q     <= camera_araddr_d      ;
`endif
            cpu_rdata_q         <= cpu_rdata_d          ;
            cpu_rresp_q         <= cpu_rresp_d          ;
            rd_state_q          <= rd_state_d           ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
