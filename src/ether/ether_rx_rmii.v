/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "config.vh"

/* ethernet receiver (RMII) */
/******************************************************************************************/
module ether_rx_rmii #(
    parameter  DATA_WIDTH        = 32  , // data width
    parameter  BUFFER_ADDR_WIDTH = 14    // RX buffer address width
) (
    input  wire                         clk_50mhz_i          , // clock
    input  wire                         rst_50mhz_i          , // reset
    input  wire                         e2s_wready_i         , // status FIFO ready
    output wire                         rx_done_o            , // receive complete pulse
    output wire                         rx_err_o             , // receive error pulse
    output wire             [DATA_WIDTH-1:0] rx_addr_end_o   , // receive end address
    input  wire                         rx_addr_start_valid_i, // start address update valid
    input  wire      [BUFFER_ADDR_WIDTH-1:0] rx_addr_start_i , // start address from CPU
    // receive buffer
    output wire                         rx_valid_o           , // write valid
    output wire        [DATA_WIDTH/8-1:0] rx_strobe_o        , // write strobe
    output wire      [BUFFER_ADDR_WIDTH-1:0] rx_addr_o       , // write address
    output wire             [DATA_WIDTH-1:0] rx_data_o       , // write data
    // Ethernet PHY (RMII)
    input  wire                         crs_dv_i             , // carrier sense/data valid
    input  wire                         rxerr_i              , // receive error
    input  wire                    [1:0] rxd_i                // receive data
);

    // DRC: design rule check
    initial begin
        if (DATA_WIDTH!=32) $fatal(1, "ether_rx_rmii supports only DATA_WIDTH=32");
        if (BUFFER_ADDR_WIDTH<2) $fatal(1, "specify proper ether_rx_rmii BUFFER_ADDR_WIDTH");
    end

    localparam IDLE              = 2'd0;
    localparam RECEIVE           = 2'd1;
    localparam CRC_CHECK         = 2'd2;
    localparam DONE              = 2'd3;

    localparam ETHER_FIN_CYCLES  = 19; // ~48 cycles (12 bytes * 8 bit / 2 bit)
    localparam WAIT_CYCLES       = 48-ETHER_FIN_CYCLES-1;
    localparam SFD               = 8'hD5;
    localparam REV_POLY          = 32'hEDB88320;
    localparam REV_POLY_S1       = 32'h76DC4190;
    localparam [BUFFER_ADDR_WIDTH+1:0] BUFFER_CEIL = {{BUFFER_ADDR_WIDTH{1'b1}}, 2'b00};

    reg                     [1:0] state_q                , state_d                ;
    reg      [BUFFER_ADDR_WIDTH+1:0] rx_addr_idx_q       , rx_addr_idx_d          ;
    reg      [BUFFER_ADDR_WIDTH+1:0] rx_addr_origin_q    , rx_addr_origin_d       ;
    reg                           rx_addr_add_q          , rx_addr_add_d          ;
    reg                           rx_done_q              , rx_done_d              ;
    reg                     [5:0] preamble_cnt_q         , preamble_cnt_d         ;
    reg                           rx_ready_q           , rx_ready_d           ;
    reg                     [1:0] byte_cnt_q             , byte_cnt_d             ;
    reg                     [1:0] bit_cnt_q              , bit_cnt_d              ;
    reg                     [5:0] fin_cycle_cnt_q        , fin_cycle_cnt_d        ;
    reg                           rx_valid_q             , rx_valid_d             ;
    reg        [DATA_WIDTH/8-1:0] rx_strobe_q            , rx_strobe_d            ;
    reg             [DATA_WIDTH-1:0] rx_data_q           , rx_data_d              ;
    reg                     [6:0] wait_cnt_q             , wait_cnt_d             ;
    reg                           crc_valid_q            , crc_valid_d            ;
    reg                           rx_err_q               , rx_err_d               ;
    reg      [BUFFER_ADDR_WIDTH-1:0] rx_addr_start_q     , rx_addr_start_d        ;
    reg                    [31:0] crc_frame_q            , crc_frame_d            ;
    reg                     [2:0] dst_byte_idx_q         , dst_byte_idx_d         ;
    reg                           dst_cmp_active_q       , dst_cmp_active_d       ;
    reg                           drop_frame_q           , drop_frame_d           ;
    reg                     [7:0] dst_byte_now                                     ;

    wire                    [1:0] feedback = crc_frame_q[1:0] ^ rx_data_q[1:0];

    function [7:0] expected_dst_mac;
        input [2:0] idx;
        begin
            case (idx)
                3'd0   : expected_dst_mac = `ETH_MAC_ADDR_0;
                3'd1   : expected_dst_mac = `ETH_MAC_ADDR_1;
                3'd2   : expected_dst_mac = `ETH_MAC_ADDR_2;
                3'd3   : expected_dst_mac = `ETH_MAC_ADDR_3;
                3'd4   : expected_dst_mac = `ETH_MAC_ADDR_4;
                default: expected_dst_mac = `ETH_MAC_ADDR_5;
            endcase
        end
    endfunction

    assign rx_done_o      = rx_done_q                                  ;
    assign rx_err_o       = rx_err_q                                   ;
    assign rx_addr_end_o  = {{(DATA_WIDTH-(BUFFER_ADDR_WIDTH+2)){1'b0}}, rx_addr_idx_q} - 'h3; // exclude FCS (4 bytes)
    assign rx_valid_o     = rx_valid_q                                 ;
    assign rx_strobe_o    = rx_strobe_q                                ;
    assign rx_addr_o      = rx_addr_idx_q[BUFFER_ADDR_WIDTH+1:2]       ;
    assign rx_data_o      = rx_data_q                                  ;

    always @(*) begin
        state_d          = state_q                     ;
        rx_done_d        = 1'b0                        ;
        rx_err_d         = 1'b0                        ;
        byte_cnt_d       = byte_cnt_q                  ;
        bit_cnt_d        = bit_cnt_q                   ;
        fin_cycle_cnt_d  = fin_cycle_cnt_q             ;
        wait_cnt_d       = wait_cnt_q                  ;
        crc_frame_d      = crc_frame_q                 ;
        rx_addr_origin_d = rx_addr_origin_q            ;
        rx_valid_d       = 1'b0                        ;
        rx_addr_add_d    = 1'b0                        ;
        rx_strobe_d      = rx_strobe_q                 ;
        rx_data_d        = rx_data_q                   ;
        rx_addr_start_d  = rx_addr_start_q             ;
        rx_ready_d     = rx_ready_q                ;
        preamble_cnt_d   = preamble_cnt_q              ;
        crc_valid_d      = crc_valid_q                 ;
        dst_byte_idx_d   = dst_byte_idx_q              ;
        dst_cmp_active_d = dst_cmp_active_q            ;
        drop_frame_d     = drop_frame_q                ;
        dst_byte_now     = 8'h00                       ;

        if (crs_dv_i) begin
            // place each 2-bit RMII chunk to the word shift register
            rx_data_d = {rxd_i, rx_data_d[DATA_WIDTH-1:2]};
        end

        rx_addr_idx_d = rx_addr_idx_q + {{(BUFFER_ADDR_WIDTH+1){1'b0}}, rx_addr_add_q};
        if (rx_addr_start_valid_i) begin
            rx_addr_start_d = rx_addr_start_i;
        end

        case (state_q)
            IDLE: begin
                if (wait_cnt_q!=0) begin
                    wait_cnt_d = wait_cnt_q-'h1;
                end else if (crs_dv_i && !rxerr_i) begin
                    rx_addr_origin_d = rx_addr_idx_q & BUFFER_CEIL;
                    rx_addr_idx_d    = rx_addr_idx_q & BUFFER_CEIL;
                    preamble_cnt_d   = (rxd_i==2'b01) ? preamble_cnt_q+'h1 : 6'h0;
                    if (preamble_cnt_q>=6'd12) begin
                        rx_ready_d = 1'b1;
                    end
                    bit_cnt_d = (bit_cnt_q==2'b11) ? 2'b00 : bit_cnt_q+'h1;
                    if (rx_ready_q && ({rxd_i, rx_data_q[7:2]}==SFD)) begin
                        crc_frame_d     = 32'hFFFF_FFFF;
                        crc_valid_d     = 1'b0;
                        byte_cnt_d      = 2'b00;
                        bit_cnt_d       = 2'b00;
                        rx_data_d       = {DATA_WIDTH{1'b0}};
                        rx_strobe_d     = {(DATA_WIDTH/8){1'b0}};
                        fin_cycle_cnt_d = 6'h0;
                        rx_ready_d    = 1'b0;
                        preamble_cnt_d  = 6'h0;
                        dst_byte_idx_d  = 3'h0;
                        dst_cmp_active_d = 1'b1;
                        drop_frame_d    = 1'b0;
                        state_d         = RECEIVE;
                    end
                end else begin
                    if (rxerr_i || (fin_cycle_cnt_q==ETHER_FIN_CYCLES)) begin
                        fin_cycle_cnt_d = 6'h0;
                        preamble_cnt_d  = 6'h0;
                        rx_ready_d    = 1'b0;
                        bit_cnt_d       = 2'b00;
                    end else begin
                        fin_cycle_cnt_d = fin_cycle_cnt_q+'h1;
                    end
                end
            end
            RECEIVE: begin
                if (crs_dv_i && !rxerr_i) begin
                    fin_cycle_cnt_d = 6'h0;
                    if (crc_valid_q && !drop_frame_q) begin
                        crc_frame_d = (crc_frame_q>>2)
                                    ^ (feedback[0] ? REV_POLY_S1 : 32'h0)
                                    ^ (feedback[1] ? REV_POLY    : 32'h0);
                    end
                    if (bit_cnt_q==2'b11) begin
                        bit_cnt_d       = 2'b00;
                        dst_byte_now    = {rxd_i, rx_data_q[31:26]};

                        if (dst_cmp_active_q) begin
                            if ((dst_byte_idx_q==3'd0) && dst_byte_now[0]) begin
                                dst_cmp_active_d = 1'b0;
                            end else if (dst_byte_now!=expected_dst_mac(dst_byte_idx_q)) begin
                                drop_frame_d = 1'b1;
                                dst_cmp_active_d = 1'b0;
                                crc_valid_d = 1'b0;
                                rx_addr_idx_d = rx_addr_origin_q;
                                rx_addr_add_d = 1'b0;
                                rx_valid_d = 1'b0;
                            end else if (dst_byte_idx_q==3'd5) begin
                                dst_cmp_active_d = 1'b0;
                            end else begin
                                dst_byte_idx_d = dst_byte_idx_q+'h1;
                            end
                        end

                        if (!drop_frame_d) begin
                            byte_cnt_d      = byte_cnt_q+'h1;
                            rx_strobe_d     = {1'b1, rx_strobe_q[DATA_WIDTH/8-1:1]};
                            rx_addr_add_d   = 1'b1;
                            if (byte_cnt_q==2'b11) begin
                                crc_valid_d = 1'b1;
                                byte_cnt_d  = 2'b00;
                                // ring buffer full check: (W+1) != R
                                if (rx_addr_idx_q[BUFFER_ADDR_WIDTH+1:2]+'h1!=rx_addr_start_q) begin
                                    rx_valid_d = 1'b1;
                                end else begin
                                    rx_addr_add_d = 1'b0;
                                    rx_addr_idx_d = rx_addr_origin_q;
                                    rx_err_d      = 1'b1;
                                    state_d       = DONE;
                                end
                            end
                        end
                    end else begin
                        bit_cnt_d = bit_cnt_q+'h1;
                    end
                end else begin
                    if (rxerr_i) begin
                        rx_addr_idx_d = rx_addr_origin_q;
                        rx_valid_d    = 1'b0;
                        rx_err_d      = 1'b1;
                        state_d       = DONE;
                    end else if (fin_cycle_cnt_q==ETHER_FIN_CYCLES) begin
                        if (drop_frame_q) begin
                            rx_addr_idx_d = rx_addr_origin_q;
                            rx_err_d      = 1'b1;
                            state_d       = DONE;
                        end else begin
                            state_d = CRC_CHECK;
                        end
                    end
                    wait_cnt_d      = WAIT_CYCLES;
                    fin_cycle_cnt_d = fin_cycle_cnt_q+'h1;
                end
            end
            CRC_CHECK: begin
                if (~crc_frame_q!=rx_data_q) begin
                    rx_err_d      = 1'b1;
                    rx_addr_idx_d = rx_addr_origin_q;
                end else begin
                    // one word already includes trailing FCS word; drop one slot
                    rx_addr_idx_d = rx_addr_idx_q-'h1;
                end
                state_d = DONE;
            end
            DONE: begin
                if (e2s_wready_i) begin
                    state_d         = IDLE;
                    rx_done_d       = ~rx_err_q;
                    fin_cycle_cnt_d = 6'h0;
                    bit_cnt_d       = 2'b00;
                    byte_cnt_d      = 2'b00;
                    wait_cnt_d      = WAIT_CYCLES;
                end
            end
            default: ;
        endcase
    end

    always @(posedge clk_50mhz_i) begin
        if (rst_50mhz_i) begin
            state_q          <= IDLE                            ;
            rx_addr_idx_q    <= {(BUFFER_ADDR_WIDTH+2){1'b0}}   ;
            rx_addr_origin_q <= {(BUFFER_ADDR_WIDTH+2){1'b0}}   ;
            rx_addr_add_q    <= 1'b0                            ;
            rx_done_q        <= 1'b0                            ;
            preamble_cnt_q   <= 6'h0                            ;
            rx_ready_q     <= 1'b0                            ;
            byte_cnt_q       <= 2'b0                            ;
            bit_cnt_q        <= 2'b0                            ;
            fin_cycle_cnt_q  <= 6'h0                            ;
            rx_valid_q       <= 1'b0                            ;
            rx_strobe_q      <= {(DATA_WIDTH/8){1'b0}}          ;
            rx_data_q        <= {DATA_WIDTH{1'b0}}              ;
            wait_cnt_q       <= 7'h0                            ;
            crc_valid_q      <= 1'b0                            ;
            rx_err_q         <= 1'b0                            ;
            rx_addr_start_q  <= {BUFFER_ADDR_WIDTH{1'b0}}       ;
            crc_frame_q      <= 32'hFFFF_FFFF                   ;
            dst_byte_idx_q   <= 3'h0                            ;
            dst_cmp_active_q <= 1'b0                            ;
            drop_frame_q     <= 1'b0                            ;
        end else begin
            state_q          <= state_d                         ;
            rx_addr_idx_q    <= rx_addr_idx_d                   ;
            rx_addr_origin_q <= rx_addr_origin_d                ;
            rx_addr_add_q    <= rx_addr_add_d                   ;
            rx_done_q        <= rx_done_d                       ;
            preamble_cnt_q   <= preamble_cnt_d                  ;
            rx_ready_q     <= rx_ready_d                    ;
            byte_cnt_q       <= byte_cnt_d                      ;
            bit_cnt_q        <= bit_cnt_d                       ;
            fin_cycle_cnt_q  <= fin_cycle_cnt_d                 ;
            rx_valid_q       <= rx_valid_d                      ;
            rx_strobe_q      <= rx_strobe_d                     ;
            rx_data_q        <= rx_data_d                       ;
            wait_cnt_q       <= wait_cnt_d                      ;
            crc_valid_q      <= crc_valid_d                     ;
            rx_err_q         <= rx_err_d                        ;
            rx_addr_start_q  <= rx_addr_start_d                 ;
            crc_frame_q      <= crc_frame_d                     ;
            dst_byte_idx_q   <= dst_byte_idx_d                  ;
            dst_cmp_active_q <= dst_cmp_active_d                ;
            drop_frame_q     <= drop_frame_d                    ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
