/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* ethernet transmitter (RMII, TX ring buffer) */
/******************************************************************************************/
module ether_tx_rmii #(
    parameter  DATA_WIDTH        = 32  , // data width
    parameter  BUFFER_ADDR_WIDTH = 12    // TX buffer address width (word)
) (
    input  wire                            clk_50mhz_i      , // clock
    input  wire                            rst_50mhz_i      , // reset
    input  wire                            tx_end_valid_i    , // new END pointer valid
    input  wire [BUFFER_ADDR_WIDTH+1:0]    tx_end_i          , // END pointer (byte offset)
    output wire                            tx_end_ready_o    , // END pointer ready
    input  wire                            e2s_wready_i      , // status FIFO ready
    output wire                            tx_update_o       , // start pointer update pulse
    output wire                            tx_busy_o         , // TX busy (data pending or active)
    output wire [BUFFER_ADDR_WIDTH+1:0]    tx_start_o        , // START pointer (byte offset)
    // transmit buffer
    output wire                            tx_rvalid_o       , // TX buffer read enable
    output wire [BUFFER_ADDR_WIDTH-1:0]    tx_addr_o         , // TX buffer read address (word)
    input  wire [DATA_WIDTH-1:0]           tx_data_i         , // TX buffer read data
    // Ethernet PHY (RMII)
    input  wire                            crs_dv_i          , // carrier sense / data valid
    output wire                            txen_o            , // TX enable
    output wire                            tx_err_o          , // TX error pulse
    output wire [1:0]                      txd_o               // TX data
);

    localparam PTR_WIDTH = BUFFER_ADDR_WIDTH + 2;

    // DRC: design rule check
    initial begin
        if (DATA_WIDTH!=32) $fatal(1, "ether_tx supports only DATA_WIDTH=32");
        if (BUFFER_ADDR_WIDTH==0) $fatal(1, "specify ether_tx BUFFER_ADDR_WIDTH");
    end

    localparam IDLE            = 3'd0;
    localparam FETCH_HDR       = 3'd1;
    localparam PREPARE         = 3'd2;
    localparam TRANSMIT        = 3'd3;
    localparam COLLISION_WAIT  = 3'd4;
    localparam DONE            = 3'd5;

    localparam TXNUMS                  = 15;
    localparam COLLISION_WAIT_CYCLES   = 255;
    localparam MAX_RETRY               = 15;
    localparam FRAME_WAIT_CYCLES       = 48;

    localparam REV_POLY                = 32'hEDB88320;
    localparam REV_POLY_S1             = 32'h76DC4190;

    localparam LOAD_PREAMBLE2          = 2'b00;
    localparam LOAD_FIN                = 2'b01;
    localparam LOAD_BUF_READ           = 2'b10;
    localparam LOAD_FCS                = 2'b11;

    reg [2:0]                      state_q, state_d;
    reg [PTR_WIDTH-1:0]            tx_start_ptr_q, tx_start_ptr_d;
    reg [PTR_WIDTH-1:0]            tx_end_ptr_q, tx_end_ptr_d;
    reg [PTR_WIDTH-1:0]            frame_record_size_q, frame_record_size_d;
    reg [BUFFER_ADDR_WIDTH-1:0]    frame_payload_addr_q, frame_payload_addr_d;

    reg [DATA_WIDTH-1:0]           packet_len_q, packet_len_d;
    reg [DATA_WIDTH-1:0]           origin_packet_len_q, origin_packet_len_d;
    reg [DATA_WIDTH-1:0]           tx_data_q, tx_data_d;
    reg [$clog2(TXNUMS)-1:0]       tx_rem_q, tx_rem_d;
    reg                            data_prepare_q, data_prepare_d;
    reg                            next_crc_valid_q, next_crc_valid_d;
    reg [DATA_WIDTH-1:0]           next_tx_data_q, next_tx_data_d;
    reg [$clog2(TXNUMS)-1:0]       next_tx_rem_q, next_tx_rem_d;
    reg [5:0]                      frame_wait_cnt_q, frame_wait_cnt_d;
    reg [$clog2(COLLISION_WAIT_CYCLES)-1:0] collision_wait_cnt_q, collision_wait_cnt_d;
    reg [$clog2(MAX_RETRY)-1:0]    retry_cnt_q, retry_cnt_d;
    reg [1:0]                      next_load_frame_type_q, next_load_frame_type_d;
    reg [1:0]                      load_frame_type_q, load_frame_type_d;
    reg [31:0]                     crc_frame_q, crc_frame_d;
    reg                            crc_valid_q, crc_valid_d;
    reg                            tx_err_q, tx_err_d;
    reg                            tx_update_q, tx_update_d;
    reg [BUFFER_ADDR_WIDTH-1:0]    tx_addr_q, tx_addr_d;

    reg                            tx_rvalid_d;
    reg                            txen_d;
    reg [1:0]                      txd_d;

    wire [1:0]  feedback    = crc_frame_q[1:0] ^ tx_data_q[1:0];
    wire [PTR_WIDTH-1:0] aligned_len = (tx_data_i[PTR_WIDTH-1:0] + {{(PTR_WIDTH-2){1'b0}}, 2'b11})
                                      & {{(PTR_WIDTH-2){1'b1}}, 2'b00};
    wire [PTR_WIDTH-1:0] record_size_from_hdr = aligned_len + {{(PTR_WIDTH-3){1'b0}}, 3'b100};
    wire tx_ring_pending = (tx_start_ptr_q!=tx_end_ptr_q);
    wire tx_state_active = ((state_q!=IDLE) && (state_q!=DONE));

    assign tx_end_ready_o = 1'b1;
    assign tx_update_o    = tx_update_q;
    assign tx_start_o     = tx_start_ptr_q;
    assign tx_busy_o      = tx_ring_pending || tx_state_active;
    assign tx_rvalid_o    = tx_rvalid_d;
    assign tx_addr_o      = tx_addr_d;
    assign tx_err_o       = tx_err_q;
    assign txen_o         = txen_d;
    assign txd_o          = txd_d;

    always @(*) begin
        state_d                = state_q;
        tx_start_ptr_d         = tx_start_ptr_q;
        tx_end_ptr_d           = tx_end_ptr_q;
        frame_record_size_d    = frame_record_size_q;
        frame_payload_addr_d   = frame_payload_addr_q;

        packet_len_d           = packet_len_q;
        origin_packet_len_d    = origin_packet_len_q;
        tx_data_d              = tx_data_q;
        tx_rem_d               = tx_rem_q;
        data_prepare_d         = data_prepare_q;
        next_crc_valid_d       = next_crc_valid_q;
        next_tx_data_d         = next_tx_data_q;
        next_tx_rem_d          = next_tx_rem_q;
        frame_wait_cnt_d       = frame_wait_cnt_q;
        collision_wait_cnt_d   = collision_wait_cnt_q;
        retry_cnt_d            = retry_cnt_q;
        next_load_frame_type_d = next_load_frame_type_q;
        load_frame_type_d      = load_frame_type_q;
        crc_frame_d            = crc_frame_q;
        crc_valid_d            = crc_valid_q;
        tx_err_d               = tx_err_q;
        tx_update_d            = tx_update_q;
        tx_addr_d              = tx_addr_q;

        tx_rvalid_d            = 1'b0;
        txen_d                 = 1'b0;
        txd_d                  = 2'b00;

        if (tx_end_valid_i) begin
            tx_end_ptr_d = tx_end_i;
        end

        if (data_prepare_q) begin
            data_prepare_d = 1'b0;
            case (load_frame_type_q)
                LOAD_PREAMBLE2: begin
                    next_tx_data_d         = {2'b11, {15{2'b01}}};
                    next_tx_rem_d          = TXNUMS;
                    next_load_frame_type_d = LOAD_BUF_READ;
                end
                LOAD_BUF_READ: begin
                    next_crc_valid_d       = 1'b1;
                    tx_addr_d              = tx_addr_q + 'h1;
                    next_tx_data_d         = tx_data_i;
                    if (packet_len_q<=4) begin
                        next_load_frame_type_d = LOAD_FCS;
                        case (packet_len_q[1:0])
                            2'b01  : next_tx_rem_d = TXNUMS-12;
                            2'b10  : next_tx_rem_d = TXNUMS-8;
                            2'b11  : next_tx_rem_d = TXNUMS-4;
                            default: next_tx_rem_d = TXNUMS;
                        endcase
                        packet_len_d = 'h0;
                    end else begin
                        next_load_frame_type_d = LOAD_BUF_READ;
                        next_tx_rem_d          = TXNUMS;
                        packet_len_d           = packet_len_q - 'h4;
                    end
                end
                LOAD_FCS: begin
                    next_load_frame_type_d = LOAD_FIN;
                    next_tx_rem_d          = TXNUMS;
                    next_crc_valid_d       = 1'b0;
                end
                default: ;
            endcase
        end

        case (state_q)
            IDLE: begin
                tx_err_d = 1'b0;
                if (tx_ring_pending) begin
                    tx_addr_d   = tx_start_ptr_q[PTR_WIDTH-1:2];
                    tx_rvalid_d = 1'b1;
                    state_d     = FETCH_HDR;
                end
            end

            FETCH_HDR: begin
                if (tx_data_i==32'h0 || tx_data_i>`ETHER_MTU) begin
                    tx_start_ptr_d      = tx_start_ptr_q + {{(PTR_WIDTH-3){1'b0}}, 3'b100};
                    tx_update_d         = 1'b1;
                    tx_err_d            = 1'b1;
                    frame_wait_cnt_d    = FRAME_WAIT_CYCLES;
                    state_d             = DONE;
                end else begin
                    packet_len_d         = tx_data_i;
                    origin_packet_len_d  = tx_data_i;
                    frame_payload_addr_d = tx_start_ptr_q[PTR_WIDTH-1:2] + 'h1;
                    frame_record_size_d  = record_size_from_hdr;
                    state_d              = PREPARE;
                end
            end

            PREPARE: begin
                if (frame_wait_cnt_q!=0) begin
                    frame_wait_cnt_d = frame_wait_cnt_q - 'h1;
                end else begin
                    crc_frame_d            = 32'hFFFF_FFFF;
                    crc_valid_d            = 1'b0;
                    tx_addr_d              = frame_payload_addr_q;
                    tx_data_d              = {16{2'b01}};
                    tx_rem_d               = TXNUMS;
                    retry_cnt_d            = MAX_RETRY;
                    load_frame_type_d      = LOAD_PREAMBLE2;
                    data_prepare_d         = 1'b1;
                    state_d                = TRANSMIT;
                end
            end

            TRANSMIT: begin
                if (!crs_dv_i) begin
                    txen_d = 1'b1;
                    txd_d  = (load_frame_type_q==LOAD_FIN) ? ~crc_frame_q[1:0] : tx_data_q[1:0];

                    if (load_frame_type_q==LOAD_FIN) begin
                        crc_frame_d = {2'b00, crc_frame_q[31:2]};
                    end else if (crc_valid_q) begin
                        crc_frame_d = (crc_frame_q>>2)
                                    ^ (feedback[0] ? REV_POLY_S1 : 32'h0)
                                    ^ (feedback[1] ? REV_POLY    : 32'h0);
                    end

                    if (tx_rem_q!=0) begin
                        tx_rem_d   = tx_rem_q-'h1;
                        tx_data_d  = {2'b00, tx_data_q[DATA_WIDTH-1:2]};
                    end else begin
                        data_prepare_d      = 1'b1;
                        tx_data_d           = next_tx_data_q;
                        tx_rem_d            = next_tx_rem_q;
                        crc_valid_d         = next_crc_valid_q;
                        load_frame_type_d   = next_load_frame_type_q;
                        if (load_frame_type_q==LOAD_FIN) begin
                            tx_start_ptr_d   = tx_start_ptr_q + frame_record_size_q;
                            tx_update_d      = 1'b1;
                            frame_wait_cnt_d = FRAME_WAIT_CYCLES;
                            state_d          = DONE;
                        end else begin
                            tx_rvalid_d = (next_load_frame_type_q==LOAD_BUF_READ);
                        end
                    end
                end else begin
                    if (retry_cnt_q==0) begin
                        tx_start_ptr_d      = tx_start_ptr_q + frame_record_size_q;
                        tx_update_d         = 1'b1;
                        tx_err_d            = 1'b1;
                        frame_wait_cnt_d    = FRAME_WAIT_CYCLES;
                        state_d             = DONE;
                    end else begin
                        collision_wait_cnt_d = COLLISION_WAIT_CYCLES;
                        retry_cnt_d          = retry_cnt_q - 'h1;
                        state_d              = COLLISION_WAIT;
                    end
                end
            end

            COLLISION_WAIT: begin
                if (collision_wait_cnt_q==0) begin
                    packet_len_d         = origin_packet_len_q;
                    crc_frame_d          = 32'hFFFF_FFFF;
                    crc_valid_d          = 1'b0;
                    tx_addr_d            = frame_payload_addr_q;
                    tx_data_d            = {16{2'b01}};
                    tx_rem_d             = TXNUMS;
                    load_frame_type_d    = LOAD_PREAMBLE2;
                    data_prepare_d       = 1'b1;
                    state_d              = TRANSMIT;
                end else begin
                    collision_wait_cnt_d = collision_wait_cnt_q - 'h1;
                end
            end

            DONE: begin
                if (e2s_wready_i) begin
                    tx_update_d = 1'b0;
                    tx_err_d    = 1'b0;
                    state_d     = IDLE;
                end
            end

            default: ;
        endcase
    end

    always @(posedge clk_50mhz_i) begin
        if (rst_50mhz_i) begin
            state_q                <= IDLE;
            tx_start_ptr_q         <= {PTR_WIDTH{1'b0}};
            tx_end_ptr_q           <= {PTR_WIDTH{1'b0}};
            frame_record_size_q    <= {PTR_WIDTH{1'b0}};
            frame_payload_addr_q   <= {BUFFER_ADDR_WIDTH{1'b0}};

            packet_len_q           <= 'h0;
            origin_packet_len_q    <= 'h0;
            tx_data_q              <= {DATA_WIDTH{1'b0}};
            tx_rem_q               <= 'h0;
            data_prepare_q         <= 1'b0;
            next_crc_valid_q       <= 1'b0;
            next_tx_data_q         <= {DATA_WIDTH{1'b0}};
            next_tx_rem_q          <= 'h0;
            frame_wait_cnt_q       <= 'h0;
            collision_wait_cnt_q   <= 'h0;
            retry_cnt_q            <= 'h0;
            next_load_frame_type_q <= LOAD_PREAMBLE2;
            load_frame_type_q      <= LOAD_PREAMBLE2;
            crc_frame_q            <= 32'hFFFF_FFFF;
            crc_valid_q            <= 1'b0;
            tx_err_q               <= 1'b0;
            tx_update_q            <= 1'b0;
            tx_addr_q              <= {BUFFER_ADDR_WIDTH{1'b0}};
        end else begin
            state_q                <= state_d;
            tx_start_ptr_q         <= tx_start_ptr_d;
            tx_end_ptr_q           <= tx_end_ptr_d;
            frame_record_size_q    <= frame_record_size_d;
            frame_payload_addr_q   <= frame_payload_addr_d;

            packet_len_q           <= packet_len_d;
            origin_packet_len_q    <= origin_packet_len_d;
            tx_data_q              <= tx_data_d;
            tx_rem_q               <= tx_rem_d;
            data_prepare_q         <= data_prepare_d;
            next_crc_valid_q       <= next_crc_valid_d;
            next_tx_data_q         <= next_tx_data_d;
            next_tx_rem_q          <= next_tx_rem_d;
            frame_wait_cnt_q       <= frame_wait_cnt_d;
            collision_wait_cnt_q   <= collision_wait_cnt_d;
            retry_cnt_q            <= retry_cnt_d;
            next_load_frame_type_q <= next_load_frame_type_d;
            load_frame_type_q      <= load_frame_type_d;
            crc_frame_q            <= crc_frame_d;
            crc_valid_q            <= crc_valid_d;
            tx_err_q               <= tx_err_d;
            tx_update_q            <= tx_update_d;
            tx_addr_q              <= tx_addr_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
