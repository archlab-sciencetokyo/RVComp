/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"
`include "axi.vh"

/* SD Card RAM Controller — MMIO Window Interface */
/******************************************************************************************/
module sdcram_controller (
    // system
    input  wire                          clk_i          , // system clock
    input  wire                          clk_50mhz_i    , // 50 MHz clock for SD card
    input  wire                          rst_ni         , // active-low reset
    // AXI write address channel
    input  wire [`SDCRAM_ADDR_WIDTH-1:0] awaddr_i       , // write address
    // AXI write data channel
    input  wire                          wvalid_i       , // write valid
    output wire                          wready_o       , // write ready
    input  wire [`SDCRAM_DATA_WIDTH-1:0] wdata_i        , // write data
    input  wire [`SDCRAM_STRB_WIDTH-1:0] wstrb_i        , // write strobe
    // AXI write response channel
    output wire                          bvalid_o       , // write response valid
    input  wire                          bready_i       , // write response ready
    output wire [`BRESP_WIDTH-1:0]       bresp_o        , // write response
    // AXI read address channel
    input  wire                          arvalid_i      , // read address valid
    output wire                          arready_o      , // read address ready
    input  wire [`SDCRAM_ADDR_WIDTH-1:0] araddr_i       , // read address
    // AXI read data channel
    output wire                          rvalid_o       , // read data valid
    input  wire                          rready_i       , // read data ready
    output wire [`SDCRAM_DATA_WIDTH-1:0] rdata_o        , // read data
    output wire [`RRESP_WIDTH-1:0]       rresp_o        , // read response
    // card I/O pins
    input  wire                          sd_cd          , // card detect
    output wire                          sd_rst         , // card reset
    output wire                          sd_sclk        , // SPI clock
    inout  wire                          sd_cmd         , // command/MOSI
    inout  wire [3:0]                    sd_dat           // data lines (DAT0=MISO, DAT3=CS)
);

//==============================================================================
// MMIO map
//------------------------------------------------------------------------------
    localparam [11:0] CSR_ADDR29        = 12'h000;  // 0xA0000000: upper 29 bits of byte address
    localparam [11:0] CSR_FLUSH         = 12'h018;  // 0xA0000018: flush trigger
    localparam [11:0] CSR_FLUSH_DONE    = 12'h01C;  // 0xA000001C: flush done (sticky)
    localparam [11:0] CSR_FLUSH_DONE_CLR= 12'h020;  // 0xA0000020: flush done clear (W1C)

    localparam [19:0] CTRL_REGION       = 20'hA0000; // 0xA0000xxx
    localparam [19:0] WINDOW_REGION     = 20'hA0001; // 0xA0001xxx (4 KiB window)

//==============================================================================
// AXI write FSM
//------------------------------------------------------------------------------
    localparam [2:0] WR_IDLE          = 3'd0;
    localparam [2:0] WR_WAIT_SDCRAM   = 3'd1;
    localparam [2:0] WR_TX          = 3'd2;
    localparam [2:0] WR_WAIT_COMPLETE = 3'd3;
    localparam [2:0] WR_RET           = 3'd4;

//==============================================================================
// AXI read FSM
//------------------------------------------------------------------------------
    localparam [2:0] RD_IDLE          = 3'd0;
    localparam [2:0] RD_WAIT_SDCRAM   = 3'd1;
    localparam [2:0] RD_TX          = 3'd2;
    localparam [2:0] RD_WAIT_COMPLETE = 3'd3;
    localparam [2:0] RD_RET           = 3'd4;

//==============================================================================
// Internal signals
//------------------------------------------------------------------------------
    // SDCRAM interface wires
    wire [40:0] sdcram_addr      ;
    wire        sdcram_ren       ;
    wire [ 3:0] sdcram_wen       ;
    wire [31:0] sdcram_wdata     ;
    wire [31:0] sdcram_rdata     ;
    wire        sdcram_busy      ;
    wire [ 3:0] sdcram_state     ;
    wire [ 2:0] sdi_state        ;
    wire [ 4:0] sdc_state        ;

    // Flush interface
    wire        sdcram_flush_busy;
    reg         flush_pending_q  , flush_pending_d  ;
    reg         prev_flush_busy_q, prev_flush_busy_d;
    reg         flush_done_q     , flush_done_d     ;
    wire        flush_done = prev_flush_busy_q & !sdcram_flush_busy;

    // AXI write FSM
    reg  [ 2:0] wr_state_q, wr_state_d;
    reg         bvalid_q,   bvalid_d  ;
    reg  [40:0] wr_addr_q,  wr_addr_d ;
    reg  [31:0] wr_data_q,  wr_data_d ;
    reg  [ 3:0] wr_strb_q,  wr_strb_d ;

    // AXI read FSM
    reg  [ 2:0] rd_state_q,  rd_state_d ;
    reg         rvalid_q,    rvalid_d   ;
    reg  [31:0] rdata_out_q, rdata_out_d;
    reg  [40:0] rd_addr_q,   rd_addr_d  ;

    // CSR registers
    reg  [28:0] addr29_q, addr29_d;

    // SD request staging registers (timing cut between controller FSM and sdcram core)
    reg  [40:0] sd_req_addr_q,    sd_req_addr_d   ;
    reg  [31:0] sd_req_wdata_q,   sd_req_wdata_d  ;
    reg  [ 3:0] sd_req_wstrb_q,   sd_req_wstrb_d  ;
    reg         sd_req_ren_q,     sd_req_ren_d    ;
    reg         sd_req_pending_q, sd_req_pending_d;

//==============================================================================
// AXI response assignments
//------------------------------------------------------------------------------
    assign bresp_o = `BRESP_OKAY;
    assign rresp_o = `RRESP_OKAY;

//==============================================================================
// AXI interface outputs
//------------------------------------------------------------------------------
    assign wready_o  = (wr_state_q == WR_IDLE) && (rd_state_q == RD_IDLE) && !sd_req_pending_q;
    assign arready_o = (rd_state_q == RD_IDLE) && (wr_state_q == WR_IDLE) && !sd_req_pending_q && !wvalid_i;
    assign bvalid_o  = bvalid_q;
    assign rvalid_o  = rvalid_q;
    assign rdata_o   = rdata_out_q;

//==============================================================================
// AXI request fire (valid & ready)
//------------------------------------------------------------------------------
    wire wr_fire = wvalid_i  & wready_o;
    wire rd_fire = arvalid_i & arready_o;

//==============================================================================
// Address decode
//------------------------------------------------------------------------------
    wire [11:0] wr_off = awaddr_i[11:0];
    wire [11:0] rd_off = araddr_i[11:0];

    wire wr_is_ctrl   = (awaddr_i[31:12] == CTRL_REGION);
    wire wr_is_window = (awaddr_i[31:12] == WINDOW_REGION);
    wire rd_is_ctrl   = (araddr_i[31:12] == CTRL_REGION);
    wire rd_is_window = (araddr_i[31:12] == WINDOW_REGION);

    wire wr_is_csr_addr29         = wr_is_ctrl && (wr_off == CSR_ADDR29);
    wire wr_is_csr_flush          = wr_is_ctrl && (wr_off == CSR_FLUSH);
    wire wr_is_csr_flush_done_clr = wr_is_ctrl && (wr_off == CSR_FLUSH_DONE_CLR);

    wire rd_is_csr_addr29      = rd_is_ctrl && (rd_off == CSR_ADDR29);
    wire rd_is_csr_flush_done  = rd_is_ctrl && (rd_off == CSR_FLUSH_DONE);

//==============================================================================
// SDCRAM interface outputs
//------------------------------------------------------------------------------
    assign sdcram_addr  = sd_req_addr_q;
    assign sdcram_ren   = sd_req_pending_q && sd_req_ren_q;
    assign sdcram_wen   = (sd_req_pending_q && !sd_req_ren_q) ? sd_req_wstrb_q : 4'b0;
    assign sdcram_wdata = sd_req_wdata_q;

//==============================================================================
// SD request staging logic (single-cycle issue pulse)
//------------------------------------------------------------------------------
    always @(*) begin
        sd_req_addr_d    = sd_req_addr_q;
        sd_req_wdata_d   = sd_req_wdata_q;
        sd_req_wstrb_d   = sd_req_wstrb_q;
        sd_req_ren_d     = 1'b0;
        sd_req_pending_d = 1'b0;

        if (wr_state_q == WR_TX) begin
            sd_req_addr_d    = wr_addr_q;
            sd_req_wdata_d   = wr_data_q;
            sd_req_wstrb_d   = wr_strb_q;
            sd_req_ren_d     = 1'b0;
            sd_req_pending_d = 1'b1;
        end else if (rd_state_q == RD_TX) begin
            sd_req_addr_d    = rd_addr_q;
            sd_req_wdata_d   = 32'b0;
            sd_req_wstrb_d   = 4'b0;
            sd_req_ren_d     = 1'b1;
            sd_req_pending_d = 1'b1;
        end
    end

//==============================================================================
// SDCRAM instance
//------------------------------------------------------------------------------
    // Keep polling interval equivalent to 1024 cycles at 100 MHz.
    localparam integer SDCRAM_POLLING_CYCLES_RAW = ((`CLK_FREQ_MHZ * 1024) + 99) / 100;
    localparam integer SDCRAM_POLLING_CYCLES     = (SDCRAM_POLLING_CYCLES_RAW > 0) ?
                                                    SDCRAM_POLLING_CYCLES_RAW : 1;

    sdcram #(
        .CACHE_DEPTH   (2   ),
        .BLOCK_NUM     (8   ),
        .POLLING_CYCLES(SDCRAM_POLLING_CYCLES)
    ) sdcram_0 (
        .sys_clk_i      (clk_i       ),
        .sys_rst_i      (!rst_ni     ),
        .sd_clk_i       (clk_50mhz_i ),
        .sd_rst_i       (!rst_ni     ),
        // user interface
        .sdcram_addr_i  (sdcram_addr ),
        .sdcram_ren_i   (sdcram_ren  ),
        .sdcram_wen_i   (sdcram_wen  ),
        .sdcram_wdata_i (sdcram_wdata),
        .sdcram_rdata_o (sdcram_rdata),
        .sdcram_busy_o  (sdcram_busy ),
        // flush
        .flush_i        (flush_pending_q ),
        .flush_busy_o   (sdcram_flush_busy),
        // debug
        .sdcram_state_o (sdcram_state),
        .sdi_state_o    (sdi_state   ),
        .sdc_state_o    (sdc_state   ),
        // SD card interface
        .sd_cd          (sd_cd       ),
        .sd_rst         (sd_rst      ),
        .sd_sclk        (sd_sclk     ),
        .sd_cmd         (sd_cmd      ),
        .sd_dat         (sd_dat      )
    );

//==============================================================================
// AXI write FSM
//------------------------------------------------------------------------------
    always @(*) begin
        wr_state_d = wr_state_q;
        bvalid_d   = bvalid_q;
        wr_addr_d  = wr_addr_q;
        wr_data_d  = wr_data_q;
        wr_strb_d  = wr_strb_q;
        addr29_d   = addr29_q;

        case (wr_state_q)
            WR_IDLE: begin
                if (wr_fire) begin
                    if (wr_is_csr_addr29) begin
                        addr29_d   = wdata_i[28:0];
                        bvalid_d   = 1'b1;
                        wr_state_d = WR_RET;
                    end else if (wr_is_csr_flush || wr_is_csr_flush_done_clr) begin
                        bvalid_d   = 1'b1;
                        wr_state_d = WR_RET;
                    end else if (wr_is_window) begin
                        wr_addr_d = {addr29_q, wr_off};
                        wr_data_d = wdata_i;
                        wr_strb_d = wstrb_i;

                        if (wstrb_i == 4'b0000) begin
                            bvalid_d   = 1'b1;
                            wr_state_d = WR_RET;
                        end else begin
                            wr_state_d = WR_WAIT_SDCRAM;
                        end
                    end else begin
                        bvalid_d   = 1'b1;
                        wr_state_d = WR_RET;
                    end
                end
            end

            WR_WAIT_SDCRAM: begin
                if (!sdcram_busy) begin
                    wr_state_d = WR_TX;
                end
            end

            WR_TX: begin
                wr_state_d = WR_WAIT_COMPLETE;
            end

            WR_WAIT_COMPLETE: begin
                if (!sd_req_pending_q && !sdcram_busy) begin
                    bvalid_d   = 1'b1;
                    wr_state_d = WR_RET;
                end
            end

            WR_RET: begin
                if (bready_i) begin
                    bvalid_d   = 1'b0;
                    wr_state_d = WR_IDLE;
                end
            end

            default: begin
                wr_state_d = WR_IDLE;
                bvalid_d   = 1'b0;
            end
        endcase
    end

//==============================================================================
// AXI read FSM
//------------------------------------------------------------------------------
    always @(*) begin
        rd_state_d   = rd_state_q;
        rvalid_d     = rvalid_q;
        rdata_out_d  = rdata_out_q;
        rd_addr_d    = rd_addr_q;

        case (rd_state_q)
            RD_IDLE: begin
                if (rd_fire) begin
                    if (rd_is_csr_addr29) begin
                        rdata_out_d = {3'b000, addr29_q};
                        rvalid_d    = 1'b1;
                        rd_state_d  = RD_RET;
                    end else if (rd_is_csr_flush_done) begin
                        rdata_out_d = {31'b0, flush_done_q};
                        rvalid_d    = 1'b1;
                        rd_state_d  = RD_RET;
                    end else if (rd_is_window) begin
                        rd_addr_d   = {addr29_q, rd_off};
                        rd_state_d  = sdcram_busy ? RD_WAIT_SDCRAM : RD_TX;
                    end else begin
                        rdata_out_d = 32'b0;
                        rvalid_d    = 1'b1;
                        rd_state_d  = RD_RET;
                    end
                end
            end

            RD_WAIT_SDCRAM: begin
                if (!sdcram_busy) begin
                    rd_state_d = RD_TX;
                end
            end

            RD_TX: begin
                rd_state_d = RD_WAIT_COMPLETE;
            end

            RD_WAIT_COMPLETE: begin
                if (!sd_req_pending_q && !sdcram_busy) begin
                    rdata_out_d = sdcram_rdata;
                    rvalid_d    = 1'b1;
                    rd_state_d  = RD_RET;
                end
            end

            RD_RET: begin
                if (rready_i) begin
                    rvalid_d   = 1'b0;
                    rd_state_d = RD_IDLE;
                end
            end

            default: begin
                rd_state_d  = RD_IDLE;
                rvalid_d    = 1'b0;
                rdata_out_d = 32'b0;
            end
        endcase
    end

//==============================================================================
// Flush next-state logic
//------------------------------------------------------------------------------
    always @(*) begin
        flush_done_d      = flush_done_q;
        flush_pending_d   = flush_pending_q;
        prev_flush_busy_d = prev_flush_busy_q;

        // flush_done_q: sticky until explicit clear by software
        if (wr_fire && wr_is_csr_flush_done_clr && wdata_i[0])
            flush_done_d = 1'b0;
        else if (flush_done)
            flush_done_d = 1'b1;

        // flush_pending_q: set on CSR write, cleared when sdcram accepts
        if (wr_fire && wr_is_csr_flush)
            flush_pending_d = 1'b1;
        else if (sdcram_flush_busy)
            flush_pending_d = 1'b0;

        prev_flush_busy_d = sdcram_flush_busy;
    end

//==============================================================================
// Sequential state update
//------------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            wr_state_q        <= WR_IDLE;
            bvalid_q          <= 1'b0;
            wr_addr_q         <= 41'b0;
            wr_data_q         <= 32'b0;
            wr_strb_q         <= 4'b0;

            rd_state_q        <= RD_IDLE;
            rvalid_q          <= 1'b0;
            rdata_out_q       <= 32'b0;
            rd_addr_q         <= 41'b0;

            addr29_q          <= 29'b0;

            flush_done_q      <= 1'b0;
            flush_pending_q   <= 1'b0;
            prev_flush_busy_q <= 1'b0;

            sd_req_addr_q     <= 41'b0;
            sd_req_wdata_q    <= 32'b0;
            sd_req_wstrb_q    <= 4'b0;
            sd_req_ren_q      <= 1'b0;
            sd_req_pending_q  <= 1'b0;
        end else begin
            wr_state_q  <= wr_state_d;
            bvalid_q    <= bvalid_d;
            wr_addr_q   <= wr_addr_d;
            wr_data_q   <= wr_data_d;
            wr_strb_q   <= wr_strb_d;

            rd_state_q  <= rd_state_d;
            rvalid_q    <= rvalid_d;
            rdata_out_q <= rdata_out_d;
            rd_addr_q   <= rd_addr_d;

            addr29_q    <= addr29_d;

            flush_done_q      <= flush_done_d;
            flush_pending_q   <= flush_pending_d;
            prev_flush_busy_q <= prev_flush_busy_d;

            sd_req_addr_q     <= sd_req_addr_d;
            sd_req_wdata_q    <= sd_req_wdata_d;
            sd_req_wstrb_q    <= sd_req_wstrb_d;
            sd_req_ren_q      <= sd_req_ren_d;
            sd_req_pending_q  <= sd_req_pending_d;
        end
    end

endmodule
/******************************************************************************************/

`resetall
