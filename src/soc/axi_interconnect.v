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
);

//==============================================================================
// data bus control
//------------------------------------------------------------------------------
    localparam WR_IDLE     = 3'd0  ;
    localparam WR_CLINT    = 3'd1  ;
    localparam WR_PLIC     = 3'd2  ;
    localparam WR_UART     = 3'd3  ;
    localparam WR_DRAM     = 3'd4  ;
    localparam WR_RET      = 3'd5  ;
    reg  [2:0] wr_state_q   , wr_state_d    ;

    localparam RD_IDLE     = 3'd0  ;
    localparam RD_BOOTROM  = 3'd1  ;
    localparam RD_CLINT    = 3'd2  ;
    localparam RD_PLIC     = 3'd3  ;
    localparam RD_UART     = 3'd4  ;
    localparam RD_DRAM     = 3'd5  ;
    localparam RD_RET      = 3'd6  ;
    reg  [2:0] rd_state_q   , rd_state_d    ;

    assign cpu_wready_o     = (wr_state_q==WR_IDLE)   ;
    assign clint_bready_o   = (wr_state_q==WR_CLINT)  ;
    assign plic_bready_o    = (wr_state_q==WR_PLIC)   ;
    assign uart_bready_o    = (wr_state_q==WR_UART)   ;
    assign dram_bready_o    = (wr_state_q==WR_DRAM)   ;
    assign cpu_bvalid_o     = (wr_state_q==WR_RET)    ;

    assign cpu_arready_o    = (rd_state_q==RD_IDLE)   ;
    assign bootrom_rready_o = (rd_state_q==RD_BOOTROM);
    assign clint_rready_o   = (rd_state_q==RD_CLINT)  ;
    assign plic_rready_o    = (rd_state_q==RD_PLIC)   ;
    assign uart_rready_o    = (rd_state_q==RD_UART)   ;
    assign dram_rready_o    = (rd_state_q==RD_DRAM)   ;
    assign cpu_rvalid_o     = (rd_state_q==RD_RET)    ;

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
//  0x80000000 +---------------------------------------------------------------+
//             | data memory                                                   |
//  0x90000000 +---------------------------------------------------------------+
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

    reg                          dram_wvalid_q      , dram_wvalid_d     ;
    reg   [`DRAM_ADDR_WIDTH-1:0] dram_awaddr_q      , dram_awaddr_d     ;
    reg   [`DRAM_DATA_WIDTH-1:0] dram_wdata_q       , dram_wdata_d      ;
    reg   [`DRAM_STRB_WIDTH-1:0] dram_wstrb_q       , dram_wstrb_d      ;

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

    assign dram_wvalid_o    = dram_wvalid_q     ;
    assign dram_awaddr_o    = dram_awaddr_q     ;
    assign dram_wdata_o     = dram_wdata_q      ;
    assign dram_wstrb_o     = dram_wstrb_q      ;

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
        dram_wvalid_d       = dram_wvalid_q     ;
        dram_awaddr_d       = dram_awaddr_q     ;
        dram_wdata_d        = dram_wdata_q      ;
        dram_wstrb_d        = dram_wstrb_q      ;
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
                            case (cpu_awaddr_i[27:8]) // uart (0x10000000-0x10000010)
                                20'h0   : begin
                                    uart_wvalid_d   = 1'b1                                  ;
                                    uart_awaddr_d   = cpu_awaddr_i[`UART_ADDR_WIDTH-1:0]    ;
                                    uart_wdata_d    = cpu_wdata_i[`UART_DATA_WIDTH-1:0]     ;
                                    uart_wstrb_d    = cpu_wstrb_i[`UART_STRB_WIDTH-1:0]     ;
                                    wr_state_d      = WR_UART                               ;
                                end
                                default : begin
                                    cpu_bresp_d     = `BRESP_DECERR                         ;
                                    wr_state_d      = WR_RET                                ;
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
            WR_DRAM    : begin
                if (dram_wready_i) begin
                    dram_wvalid_d   = 1'b0          ;
                end
                if (dram_bvalid_i) begin
                    cpu_bresp_d     = dram_bresp_i  ;
                    wr_state_d      = WR_RET        ;
                end
            end
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
            dram_wvalid_q       <= 1'b0                 ;
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
            dram_wvalid_q       <= dram_wvalid_d        ;
            dram_awaddr_q       <= dram_awaddr_d        ;
            dram_wdata_q        <= dram_wdata_d         ;
            dram_wstrb_q        <= dram_wstrb_d         ;
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
    reg     [`PLIC_ADDR_WIDTH-1:0] uart_araddr_q        , uart_araddr_d         ;

    reg                            dram_arvalid_q       , dram_arvalid_d        ;
    reg     [`DRAM_ADDR_WIDTH-1:0] dram_araddr_q        , dram_araddr_d         ;

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

    assign dram_arvalid_o       = dram_arvalid_q        ;
    assign dram_araddr_o        = dram_araddr_q         ;

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
        dram_arvalid_d      = dram_arvalid_q        ;
        dram_araddr_d       = dram_araddr_q         ;
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
                            case (cpu_araddr_i[27:8]) // uart (0x10000000-0x10000010)
                                20'h0   : begin
                                    uart_arvalid_d      = 1'b1                                  ;
                                    uart_araddr_d       = cpu_araddr_i[`UART_ADDR_WIDTH-1:0]    ;
                                    rd_state_d          = RD_UART                               ;
                                end
                                default : begin
                                    cpu_rresp_d         = `RRESP_DECERR                         ;
                                    rd_state_d          = RD_RET                                ;
                                end
                            endcase
                        end
                        'h8     : begin // dram (0x80000000-0x90000000)
                            dram_arvalid_d      = 1'b1                                  ;
                            dram_araddr_d       = cpu_araddr_i[`DRAM_ADDR_WIDTH-1:0]    ;
                            rd_state_d          = RD_DRAM                               ;
                        end
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
            dram_arvalid_q      <= 1'b0                 ;
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
            dram_arvalid_q      <= dram_arvalid_d       ;
            dram_araddr_q       <= dram_araddr_d        ;
            cpu_rdata_q         <= cpu_rdata_d          ;
            cpu_rresp_q         <= cpu_rresp_d          ;
            rd_state_q          <= rd_state_d           ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
