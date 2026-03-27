/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* Card RAM core */
/* Cache-backed RAM using card storage as backing store */
/******************************************************************************************/
module sdcram #(
    parameter CACHE_DEPTH    = 8   , // number of cache lines
    parameter BLOCK_NUM      = 1   , // number of 512-byte blocks per cache line
    parameter POLLING_CYCLES = 1024  // cycles between dirty line write-back checks
) (
    input  wire        sys_clk_i      , // system clock
    input  wire        sys_rst_i      , // system reset
    input  wire        sd_clk_i       , // SD card clock (typically 50 MHz)
    input  wire        sd_rst_i       , // SD card reset
    // user interface
    input  wire [40:0] sdcram_addr_i  , // byte address
    input  wire        sdcram_ren_i   , // read enable
    input  wire [ 3:0] sdcram_wen_i   , // write enable (byte-wise)
    input  wire [31:0] sdcram_wdata_i , // write data
    output wire [31:0] sdcram_rdata_o , // read data
    output wire        sdcram_busy_o  , // busy (operation in progress)
    // debug
    output wire [ 3:0] sdcram_state_o , // main state machine state
    output wire [ 2:0] sdi_state_o    , // interface state
    output wire [ 4:0] sdc_state_o    , // protocol state
    // flush interface
    input  wire        flush_i        , // flush request (level signal)
    output wire        flush_busy_o   , // flush in progress
    // SD card interface
    input  wire        sd_cd          , // card detect
    output wire        sd_rst         , // card reset
    output wire        sd_sclk        , // SD clock
    inout  wire        sd_cmd         , // command line
    inout  wire [ 3:0] sd_dat           // data lines
);

//==============================================================================
// State machine encoding
//------------------------------------------------------------------------------
    localparam INIT        = 4'd0;
    localparam IDLE        = 4'd1;
    localparam WRITE_BLOCK = 4'd2;
    localparam READ_BLOCK  = 4'd3;
    localparam SET_TAG     = 4'd4;
    localparam WAIT        = 4'd5;
    localparam POLLING     = 4'd6;
    localparam CLEAN_TAG   = 4'd7;
    localparam FLUSH       = 4'd8;

//==============================================================================
// Interface signals
//------------------------------------------------------------------------------
    wire        sdi_req_en   ;
    wire        sdi_req_rw   ;
    wire [40:0] sdi_req_adr  ;
    wire        sdi_req_ack  ;
    wire        sdi_rep_ready;
    wire        sdi_rep_en   ;
    wire        sdi_rep_rw   ;
    wire [40:0] sdi_rep_adr  ;
    wire [40:0] sdi_cache_adr;
    wire [31:0] sdi_cache_din;
    wire [ 3:0] sdi_cache_wen;
    wire        sdi_cache_en ;
    wire [31:0] sdi_cache_dout;

//==============================================================================
// Cache controller signals
//------------------------------------------------------------------------------
    wire [40:0] cc_cache_adr ;
    wire [ 3:0] cc_cache_wen ;
    wire [31:0] cc_cache_din ;
    wire [31:0] cc_cache_dout;
    wire        cc_cache_en  ;

//==============================================================================
// Request/reply FIFO signals
//------------------------------------------------------------------------------
    wire        req_wen     ;
    wire [41:0] req_wdata   ;
    wire        req_ren     ;
    wire [41:0] req_rdata   ;
    wire        req_empty   ;
    wire        req_full    ;
    wire        req_empty_n ;
    wire        req_full_n  ;

    wire        ack_wen     ;
    wire [41:0] ack_wdata   ;
    wire        ack_ren     ;
    wire [41:0] ack_rdata   ;
    wire        ack_empty   ;
    wire        ack_full    ;
    wire        ack_empty_n ;
    wire        ack_full_n  ;

    assign req_empty   = !req_empty_n;
    assign req_full    = !req_full_n ;
    assign ack_empty   = !ack_empty_n;
    assign ack_full    = !ack_full_n ;

//==============================================================================
// Cache tag interface signals
//------------------------------------------------------------------------------
    wire [40:0] ct_addr_i ;
    wire        ct_dirty_i;
    wire        ct_wen_i  ;
    wire        ct_valid_o;
    wire        ct_hit_o  ;
    wire        ct_dirty_o;
    wire [40:0] ct_addr_o ;
    wire        ct_ready_o;

//==============================================================================
// State machine registers
//------------------------------------------------------------------------------
    reg [11:0] states_q;
    reg [11:0] states_d;

    wire [3:0] state_q = states_q[3:0];
    wire [3:0] state_d = states_d[3:0];

//==============================================================================
// Tag geometry
//------------------------------------------------------------------------------
    localparam TAG_WIDTH      = 41 - $clog2(CACHE_DEPTH) - 9 - $clog2(BLOCK_NUM);

//==============================================================================
// Data path registers
//------------------------------------------------------------------------------
    reg         req_wen_q      ;
    reg         req_wen_d      ;
    reg  [41:0] req_data_q     ;
    reg  [41:0] req_data_d     ;
    reg  [41:0] rep_data_q     ;
    reg  [41:0] rep_data_d     ;
    reg         ct_dirty_q     ;
    reg         ct_dirty_d     ;
    reg  [40:0] sdcram_addr_q  ;
    reg  [40:0] sdcram_addr_d  ;
    reg  [31:0] sdcram_wdata_q ;
    reg  [31:0] sdcram_wdata_d ;
    reg  [ 3:0] sdcram_wen_q   ;
    reg  [ 3:0] sdcram_wen_d   ;

//==============================================================================
// Polling registers
//------------------------------------------------------------------------------
    localparam PCNT_WIDTH = $clog2(POLLING_CYCLES);
    localparam PBLK_WIDTH = $clog2(CACHE_DEPTH)   ;
    localparam PTAG_WIDTH = TAG_WIDTH;

    reg [PCNT_WIDTH-1:0] pcnt_q;
    reg [PCNT_WIDTH-1:0] pcnt_d;
    reg [PBLK_WIDTH-1:0] pblk_q;
    reg [PBLK_WIDTH-1:0] pblk_d;
    reg [PTAG_WIDTH-1:0] ptag_q;
    reg [PTAG_WIDTH-1:0] ptag_d;

//==============================================================================
// Flush registers
//------------------------------------------------------------------------------
    reg [PBLK_WIDTH:0]   flush_line_q;  // 0..CACHE_DEPTH
    reg [PBLK_WIDTH:0]   flush_line_d;

//==============================================================================
// Interface instance
//------------------------------------------------------------------------------
    sdcram_interface #(
        .BLOCK_NUM(BLOCK_NUM)
    ) sdcram_interface_0 (
        .clk_i          (sd_clk_i       ), // input  wire
        .rst_i          (sd_rst_i       ), // input  wire
        // request interface
        .req_en_i       (sdi_req_en     ), // input  wire
        .req_rw_i       (sdi_req_rw     ), // input  wire
        .req_adr_i      (sdi_req_adr    ), // input  wire                  [40:0]
        .req_ack_o      (sdi_req_ack    ), // output wire
        // reply interface
        .rep_ready_i    (sdi_rep_ready  ), // input  wire
        .rep_en_o       (sdi_rep_en     ), // output wire
        .rep_rw_o       (sdi_rep_rw     ), // output wire
        .rep_adr_o      (sdi_rep_adr    ), // output wire                  [40:0]
        // debug
        .sdi_state_o    (sdi_state_o    ), // output wire                   [2:0]
        .sdc_state_o    (sdc_state_o    ), // output wire                   [4:0]
        // cache interface
        .cache_adr_o    (sdi_cache_adr  ), // output wire                  [40:0]
        .cache_din_o    (sdi_cache_din  ), // output wire                  [31:0]
        .cache_wen_o    (sdi_cache_wen  ), // output wire                   [3:0]
        .cache_en_o     (sdi_cache_en   ), // output wire
        .cache_dout_i   (sdi_cache_dout ), // input  wire                  [31:0]
        // SD card interface
        .sd_cd          (sd_cd          ), // input  wire
        .sd_rst         (sd_rst         ), // output wire
        .sd_sclk        (sd_sclk        ), // output wire
        .sd_cmd         (sd_cmd         ), // inout  wire
        .sd_dat         (sd_dat         )  // inout  wire                   [3:0]
    );

//==============================================================================
// Request FIFO (system clock → SD clock)
//------------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(42),
        .ADDR_WIDTH(2 )
    ) req_fifo (
        .wclk_i   (sys_clk_i   ), // input  wire
        .rclk_i   (sd_clk_i    ), // input  wire
        .wrst_i   (sys_rst_i   ), // input  wire
        .rrst_i   (sd_rst_i    ), // input  wire
        .wvalid_i (req_wen     ), // input  wire
        .wready_o (req_full_n  ), // output wire
        .wdata_i  (req_wdata   ), // input  wire                  [41:0]
        .rvalid_o (req_empty_n ), // output wire
        .rready_i (req_ren     ), // input  wire
        .rdata_o  (req_rdata   )  // output wire                  [41:0]
    );

    assign sdi_req_en  = !req_empty      ;
    assign sdi_req_rw  = req_rdata[41]   ;
    assign sdi_req_adr = req_rdata[40:0] ;
    assign req_ren     = sdi_req_ack     ;

//==============================================================================
// Acknowledge FIFO (SD clock → system clock)
//------------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(42),
        .ADDR_WIDTH(2 )
    ) ack_fifo (
        .wclk_i   (sd_clk_i    ), // input  wire
        .rclk_i   (sys_clk_i   ), // input  wire
        .wrst_i   (sd_rst_i    ), // input  wire
        .rrst_i   (sys_rst_i   ), // input  wire
        .wvalid_i (ack_wen     ), // input  wire
        .wready_o (ack_full_n  ), // output wire
        .wdata_i  (ack_wdata   ), // input  wire                  [41:0]
        .rvalid_o (ack_empty_n ), // output wire
        .rready_i (ack_ren     ), // input  wire
        .rdata_o  (ack_rdata   )  // output wire                  [41:0]
    );

    assign sdi_rep_ready = !ack_full             ;
    assign ack_wen       = sdi_rep_en            ;
    assign ack_wdata     = {sdi_rep_rw, sdi_rep_adr};

//==============================================================================
// Cache RAM (dual-port, two clock domains)
//------------------------------------------------------------------------------
    tdp_rf_bw2clk #(
        .NB_COL         (4                             ),
        .COL_WIDTH      (8                             ),
        .RAM_DEPTH      (128 * CACHE_DEPTH * BLOCK_NUM ),
        .RAM_PERFORMANCE("LOW_LATENCY"                 ),
        .INIT_FILE      (""                            )
    ) cache_ram (
        .clka_i  (sys_clk_i                                                         ), // input  wire
        .clkb_i  (sd_clk_i                                                          ), // input  wire
        .rsta_i  (sys_rst_i                                                         ), // input  wire
        .rstb_i  (sd_rst_i                                                          ), // input  wire
        .ena_i   (cc_cache_en                                                       ), // input  wire
        .enb_i   (sdi_cache_en                                                      ), // input  wire
        .wea_i   (cc_cache_wen                                                      ), // input  wire                   [3:0]
        .web_i   (sdi_cache_wen                                                     ), // input  wire                   [3:0]
        .addra_i (cc_cache_adr[8+$clog2(CACHE_DEPTH)+$clog2(BLOCK_NUM):2]          ), // input  wire   [ADDR_WIDTH-1:0]
        .addrb_i (sdi_cache_adr[8+$clog2(CACHE_DEPTH)+$clog2(BLOCK_NUM):2]         ), // input  wire   [ADDR_WIDTH-1:0]
        .dina_i  (cc_cache_din                                                      ), // input  wire   [DATA_WIDTH-1:0]
        .dinb_i  (sdi_cache_din                                                     ), // input  wire   [DATA_WIDTH-1:0]
        .douta_o (cc_cache_dout                                                     ), // output wire   [DATA_WIDTH-1:0]
        .doutb_o (sdi_cache_dout                                                    )  // output wire   [DATA_WIDTH-1:0]
    );

//==============================================================================
// Cache tags instance
//------------------------------------------------------------------------------
    cache_tags #(
        .DEPTH    (CACHE_DEPTH),
        .BLOCK_NUM(BLOCK_NUM  )
    ) cache_tags_0 (
        .clk_i   (sys_clk_i ), // input  wire
        .rst_i   (sys_rst_i ), // input  wire
        .addr_i  (ct_addr_i ), // input  wire                  [40:0]
        .dirty_i (ct_dirty_i), // input  wire
        .wen_i   (ct_wen_i  ), // input  wire
        .valid_o (ct_valid_o), // output wire
        .hit_o   (ct_hit_o  ), // output wire
        .dirty_o (ct_dirty_o), // output wire
        .addr_o  (ct_addr_o ), // output wire                  [40:0]
        .ready_o (ct_ready_o)  // output wire
    );

//==============================================================================
// Cache tag interface logic
//------------------------------------------------------------------------------
    localparam BLK_ZERO_WIDTH = 9 + $clog2(BLOCK_NUM);
    wire [BLK_ZERO_WIDTH-1:0] blk_zeros = {BLK_ZERO_WIDTH{1'b0}};

    assign ct_addr_i  = ((state_q == POLLING) || (state_q == CLEAN_TAG)) ? {ptag_q, pblk_q, blk_zeros} :
                        (state_q == SET_TAG) ? sdcram_addr_q : sdcram_addr_i;
    assign ct_dirty_i = (state_q == CLEAN_TAG) ? 1'b0 : ct_dirty_q;
    assign ct_wen_i   = (state_q == SET_TAG) || (state_q == CLEAN_TAG);

//==============================================================================
// Cache RAM interface logic
//------------------------------------------------------------------------------
    assign cc_cache_adr = sdcram_addr_q;
    assign cc_cache_wen = ((state_q == SET_TAG) && ct_hit_o && ct_valid_o) ? sdcram_wen_q : 4'h0;
    assign cc_cache_din = sdcram_wdata_q;
    assign cc_cache_en  = (state_q != WAIT);

//==============================================================================
// Output assignments
//------------------------------------------------------------------------------
    assign sdcram_rdata_o = cc_cache_dout    ;
    assign sdcram_busy_o  = (state_q != IDLE);
    assign sdcram_state_o = state_q          ;
    assign flush_busy_o   = (states_q[3:0] == FLUSH) || (states_q[7:4] == FLUSH) || (states_q[11:8] == FLUSH);

//==============================================================================
// Request FIFO interface
//------------------------------------------------------------------------------
    assign req_wdata = req_data_q;
    assign req_wen   = req_wen_q ;

//==============================================================================
// Address generation for SD operations
//------------------------------------------------------------------------------
    wire [40:0] new_sd_addr = {ct_addr_i[40:9+$clog2(BLOCK_NUM)], blk_zeros};
    wire [40:0] old_sd_addr = {ct_addr_o[40:9+$clog2(BLOCK_NUM)], blk_zeros};

//==============================================================================
// Control signals
//------------------------------------------------------------------------------
    wire sdi_ready = !req_full ;
    wire sdi_ack   = !ack_empty;

    assign ack_ren = sdi_ack && (state_q == WAIT);

//==============================================================================
// Combinational next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        // Default assignments
        states_d       = states_q      ;
        req_wen_d      = req_wen_q     ;
        req_data_d     = req_data_q    ;
        rep_data_d     = rep_data_q    ;
        ct_dirty_d     = ct_dirty_q    ;
        sdcram_addr_d  = sdcram_addr_q ;
        sdcram_wdata_d = sdcram_wdata_q;
        sdcram_wen_d   = sdcram_wen_q  ;
        pcnt_d         = pcnt_q        ;
        pblk_d         = pblk_q        ;
        ptag_d         = ptag_q        ;
        flush_line_d   = flush_line_q  ;

        case (state_q)
            INIT: begin
                if (sdi_ready && ct_ready_o) begin
                    states_d = {3{IDLE}};
                end
                req_wen_d      = 1'b0;
                req_data_d     = 42'h0;
                rep_data_d     = 42'h0;
                ct_dirty_d     = 1'b0;
                sdcram_addr_d  = 41'h0;
                sdcram_wdata_d = 32'h0;
                sdcram_wen_d   = 4'h0;
                flush_line_d   = {(PBLK_WIDTH+1){1'b0}};
            end

            IDLE: begin
                ct_dirty_d     = (sdcram_wen_i != 4'h0) ? 1'b1 : 1'b0;
                sdcram_addr_d  = sdcram_addr_i ;
                sdcram_wdata_d = sdcram_wdata_i;
                sdcram_wen_d   = sdcram_wen_i  ;

                if (sdcram_ren_i || (sdcram_wen_i != 4'h0)) begin
                    case ({ct_valid_o, ct_hit_o, ct_dirty_o})
                        3'b000, 3'b001, 3'b010, 3'b011, 3'b100: begin
                            states_d = {IDLE, SET_TAG, READ_BLOCK};
                        end
                        3'b101: begin
                            states_d = {SET_TAG, READ_BLOCK, WRITE_BLOCK};
                        end
                        3'b110, 3'b111: begin
                            states_d = {{2{IDLE}}, SET_TAG};
                        end
                        default: begin
                            states_d = {IDLE, SET_TAG, READ_BLOCK};
                        end
                    endcase
                    pcnt_d = {PCNT_WIDTH{1'b0}};
                end
                // Flush request: transition to FLUSH state
                else if (flush_i) begin
                    flush_line_d = {(PBLK_WIDTH+1){1'b0}};
                    states_d     = {{2{IDLE}}, FLUSH};
                end
                // Polling for write-back
                else if (pcnt_q == (POLLING_CYCLES - 1)) begin
                    pcnt_d   = {PCNT_WIDTH{1'b0}};
                    pblk_d   = pblk_q + 1'b1      ;
                    ptag_d   = {PTAG_WIDTH{1'b0}} ;
                    states_d = {IDLE, CLEAN_TAG, POLLING};
                end else begin
                    pcnt_d = pcnt_q + 1'b1;
                end
            end

            WRITE_BLOCK: begin
                if (sdi_ready) begin
                    states_d[3:0] = WAIT;
                    req_wen_d     = 1'b1;
                    req_data_d    = {1'b1, old_sd_addr};
                end
            end

            READ_BLOCK: begin
                if (sdi_ready) begin
                    states_d[3:0] = WAIT;
                    req_wen_d     = 1'b1;
                    req_data_d    = {1'b0, new_sd_addr};
                end
            end

            WAIT: begin
                req_wen_d  = 1'b0  ;
                req_data_d = 42'h0 ;
                if (sdi_ack) begin
                    states_d   = {IDLE, states_q[11:4]};
                    rep_data_d = ack_rdata;
                end
            end

            SET_TAG: begin
                states_d = {IDLE, states_q[11:4]};
            end

            POLLING: begin
                if (!(ct_valid_o && ct_dirty_o)) begin
                    // Not dirty: skip write-back, return to caller
                    if (states_q[11:8] == FLUSH)
                        states_d = {{2{IDLE}}, FLUSH};
                    else
                        states_d = {3{IDLE}};
                end else if (sdi_ready) begin
                    states_d[3:0] = WAIT;
                    ptag_d        = old_sd_addr[40:9+$clog2(CACHE_DEPTH)+$clog2(BLOCK_NUM)];
                    req_wen_d     = 1'b1;
                    req_data_d    = {1'b1, old_sd_addr};
                end
            end

            FLUSH: begin
                if (flush_line_q >= CACHE_DEPTH) begin
                    states_d = {3{IDLE}};
                end else begin
                    pblk_d   = flush_line_q[PBLK_WIDTH-1:0];
                    ptag_d   = {PTAG_WIDTH{1'b0}};
                    pcnt_d   = {PCNT_WIDTH{1'b0}};
                    states_d = {FLUSH, CLEAN_TAG, POLLING};
                    flush_line_d = flush_line_q + 1;
                end
            end

            CLEAN_TAG: begin
                states_d = {IDLE, states_q[11:4]};
            end

            default: begin
                states_d = {3{IDLE}};
            end
        endcase
    end

//==============================================================================
// Sequential state update
//------------------------------------------------------------------------------
    always @(posedge sys_clk_i) begin
        if (sys_rst_i) begin
            states_q       <= {3{INIT}}         ;
            req_wen_q      <= 1'b0              ;
            req_data_q     <= 42'h0             ;
            rep_data_q     <= 42'h0             ;
            ct_dirty_q     <= 1'b0              ;
            sdcram_addr_q  <= 41'h0             ;
            sdcram_wdata_q <= 32'h0             ;
            sdcram_wen_q   <= 4'h0              ;
            pcnt_q         <= {PCNT_WIDTH{1'b0}};
            pblk_q         <= {PBLK_WIDTH{1'b0}};
            ptag_q         <= {PTAG_WIDTH{1'b0}};
            flush_line_q   <= {(PBLK_WIDTH+1){1'b0}};
        end else begin
            states_q       <= states_d      ;
            req_wen_q      <= req_wen_d     ;
            req_data_q     <= req_data_d    ;
            rep_data_q     <= rep_data_d    ;
            ct_dirty_q     <= ct_dirty_d    ;
            sdcram_addr_q  <= sdcram_addr_d ;
            sdcram_wdata_q <= sdcram_wdata_d;
            sdcram_wen_q   <= sdcram_wen_d  ;
            pcnt_q         <= pcnt_d        ;
            pblk_q         <= pblk_d        ;
            ptag_q         <= ptag_d        ;
            flush_line_q   <= flush_line_d  ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
