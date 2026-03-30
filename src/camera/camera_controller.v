/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

module camera #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                     clk_i,
    input  wire                     clk_cam_xclk_i,
    input  wire                     clk_cam_i2c_i,
    input  wire                     rst_i,

    input  wire                     wvalid_i,
    output wire                     wready_o,
    input  wire [ADDR_WIDTH-1:0]    awaddr_i,
    input  wire [DATA_WIDTH-1:0]    wdata_i,
    input  wire [DATA_WIDTH/8-1:0]  wstrb_i,
    output wire                     bvalid_o,
    input  wire                     bready_i,
    output wire [`BRESP_WIDTH-1:0]  bresp_o,

    input  wire                     arvalid_i,
    output wire                     arready_o,
    input  wire [ADDR_WIDTH-1:0]    araddr_i,
    output wire                     rvalid_o,
    input  wire                     rready_i,
    output wire [DATA_WIDTH-1:0]    rdata_o,
    output wire [`RRESP_WIDTH-1:0]  rresp_o,

    input  wire                     pclk,
    input  wire                     camera_v_sync,
    input  wire                     camera_h_ref,
    input  wire [7:0]               din,
    output wire                     sioc,
    output wire                     siod,
    output wire                     reset,
    output wire                     power_down,
    output wire                     xclk
);

    localparam integer STRB_WIDTH           = DATA_WIDTH / 8;
    localparam [31:0] CSR_BASE              = `CAMERA_CSR_BASE;
    localparam [31:0] FRAME_BASE            = `CAMERA_FRAME_BASE;
    localparam [31:0] FRAME_APERTURE_BYTES  = `CAMERA_FRAME_SIZE;

    localparam [31:0] REG_ID         = 32'h00;
    localparam [31:0] REG_CTRL       = 32'h04;
    localparam [31:0] REG_STATUS     = 32'h08;
    localparam [31:0] REG_WIDTH      = 32'h0C;
    localparam [31:0] REG_HEIGHT     = 32'h10;
    localparam [31:0] REG_STRIDE     = 32'h14;
    localparam [31:0] REG_FRAMEBYTES = 32'h18;
    localparam [31:0] REG_SEQ        = 32'h1C;
    localparam [31:0] REG_READY_BANK = 32'h20;
    localparam [31:0] REG_READ_BANK  = 32'h24;
    localparam [31:0] REG_DROP_COUNT = 32'h28;
    localparam [31:0] REG_GAIN       = 32'h2C;

    localparam [31:0] CAMERA_ID      = 32'h5256_4350;

    localparam integer FRAME_WIDTH          = 320;
    localparam integer FRAME_HEIGHT         = 240;
    localparam integer FRAME_STRIDE         = 320;
    localparam integer FRAME_BYTES          = FRAME_WIDTH * FRAME_HEIGHT;
    localparam integer FRAME_WORDS          = FRAME_BYTES / STRB_WIDTH;
    localparam integer FRAME_AW             = $clog2(FRAME_WORDS);
    localparam [9:0]   FRAME_WIDTH_10       = 10'd320;
    localparam [9:0]   FRAME_HEIGHT_10      = 10'd240;
    localparam [9:0]   FRAME_WIDTH_LAST_10  = 10'd319;
    localparam [9:0]   FRAME_HEIGHT_LAST_10 = 10'd239;
    localparam [FRAME_AW:0] FRAME_WORDS_W            = 16'd19200;
    localparam [FRAME_AW:0] FRAME_WORDS_PER_LINE_W   = 16'd80;

    function [31:0] apply_wstrb;
        input [31:0] old_v;
        input [31:0] new_v;
        input [ 3:0] strb;
        begin
            apply_wstrb = {
                strb[3] ? new_v[31:24] : old_v[31:24],
                strb[2] ? new_v[23:16] : old_v[23:16],
                strb[1] ? new_v[15:8]  : old_v[15:8],
                strb[0] ? new_v[7:0]   : old_v[7:0]
            };
        end
    endfunction

    function [7:0] rgb565_to_gray8;
        input [15:0] pixel;
        reg   [7:0]  r8;
        reg   [7:0]  g8;
        reg   [7:0]  b8;
        reg   [15:0] gray_mix;
        begin
            r8  = {pixel[15:11], 3'b000};
            g8  = {pixel[10:5],  2'b00};
            b8  = {pixel[4:0],   3'b000};
            gray_mix = (r8 * 8'd77) + (g8 * 8'd150) + (b8 * 8'd29);
            rgb565_to_gray8 = gray_mix[15:8];
        end
    endfunction

    function [31:0] gray_word_at_lane;
        input [1:0] lane;
        input [7:0] gray;
        begin
            case (lane)
                2'd0: gray_word_at_lane = {24'h0, gray};
                2'd1: gray_word_at_lane = {16'h0, gray, 8'h0};
                2'd2: gray_word_at_lane = {8'h0, gray, 16'h0};
                default: gray_word_at_lane = {gray, 24'h0};
            endcase
        end
    endfunction

    function [3:0] gray_strobe_at_lane;
        input [1:0] lane;
        begin
            case (lane)
                2'd0: gray_strobe_at_lane = 4'b0001;
                2'd1: gray_strobe_at_lane = 4'b0010;
                2'd2: gray_strobe_at_lane = 4'b0100;
                default: gray_strobe_at_lane = 4'b1000;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // CSR state
    // -------------------------------------------------------------------------
    reg [31:0] ctrl_q;
    reg [31:0] read_bank_q;
    reg [31:0] gain_q;
    reg [31:0] seq_q;
    reg [31:0] ready_bank_q;
    reg [31:0] drop_count_q;
    reg        write_bank_q;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sccb_done_ff1_q;
`ifdef CAMERA_DEBUG_ILA
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO", MARK_DEBUG = "true" *) reg sccb_done_q;
    (* MARK_DEBUG = "true" *) reg pix_ever_q;
`else
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg sccb_done_q;
    reg pix_ever_q;
`endif

    wire [31:0] status_r = {
        26'h0,
        pix_ever_q,
        sccb_done_q,
        ready_bank_q[0],
        read_bank_q[0],
        (seq_q != 32'h0),
        ctrl_q[0]
    };

    // -------------------------------------------------------------------------
    // Camera frontend
    // -------------------------------------------------------------------------
    wire pclk_ibuf_q;
    wire pclk_bufg_q;
    wire [15:0] cap_dout;
    wire [ 9:0] cap_addr_x;
    wire [ 9:0] cap_addr_y;
    wire        cap_en;
    wire        sccb_done_raw;

    IBUF ibuf_camera_pclk (
        .I (pclk       ),
        .O (pclk_ibuf_q)
    );

    BUFG bufg_camera_pclk (
        .I (pclk_ibuf_q),
        .O (pclk_bufg_q)
    );

    ov7670 ov7670_0 (
        .CLK           (clk_i          ),
        .RST           (rst_i          ),
        .cap_dout      (cap_dout       ),
        .cap_addr_x    (cap_addr_x     ),
        .cap_addr_y    (cap_addr_y     ),
        .cap_en        (cap_en         ),
        .w_gain        (gain_q[7:0]    ),
        .clk_cam_i2c   (clk_cam_i2c_i  ),
        .clk_cam_pix   (clk_cam_xclk_i ),
        .pclk          (pclk_bufg_q    ),
        .camera_v_sync (camera_v_sync  ),
        .camera_h_ref  (camera_h_ref   ),
        .din           (din            ),
        .sioc          (sioc           ),
        .siod          (siod           ),
        .reset         (reset          ),
        .power_down    (power_down     ),
        .xclk          (xclk           ),
        .sccb_done     (sccb_done_raw  )
    );

`ifdef CAMERA_DEBUG_ILA
    // Optional debug taps for manual ILA bring-up.
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_clk_i        = clk_i;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_clk_cam_xclk = clk_cam_xclk_i;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_clk_cam_i2c  = clk_cam_i2c_i;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_pclk_in      = pclk;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_pclk_bufg    = pclk_bufg_q;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_vsync        = camera_v_sync;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_href         = camera_h_ref;
    (* MARK_DEBUG = "true" *) wire [7:0] dbg_ov7670_din          = din;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_sioc         = sioc;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_siod         = siod;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_reset_n      = reset;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_power_down   = power_down;
    (* MARK_DEBUG = "true" *) wire       dbg_ov7670_xclk         = xclk;
`endif

    always @(posedge clk_i) begin
        if (rst_i) begin
            sccb_done_ff1_q <= 1'b0;
            sccb_done_q     <= 1'b0;
            pix_ever_q      <= 1'b0;
        end else begin
            sccb_done_ff1_q <= sccb_done_raw;
            sccb_done_q     <= sccb_done_ff1_q;
            if (cap_en) begin
                pix_ever_q <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Pixel pack pipeline
    // -------------------------------------------------------------------------
    wire pixel_valid = cap_en &&
                       (cap_addr_x < FRAME_WIDTH_10) &&
                       (cap_addr_y < FRAME_HEIGHT_10) &&
                       ctrl_q[0];

    wire frame_done = pixel_valid &&
                      (cap_addr_x == FRAME_WIDTH_LAST_10) &&
                      (cap_addr_y == FRAME_HEIGHT_LAST_10);

    reg               cap_valid_s0_q;
    reg               cap_bank_s0_q;
    reg [9:0]         cap_x_s0_q;
    reg [9:0]         cap_y_s0_q;
    reg [15:0]        cap_pixel_s0_q;

    wire [7:0]        gray_s0             = rgb565_to_gray8(cap_pixel_s0_q);
    wire [FRAME_AW:0] line_word_offset_s0 = {{(FRAME_AW + 1 - 8){1'b0}}, cap_x_s0_q[9:2]};
    wire [FRAME_AW:0] y_words_s0          = cap_y_s0_q * FRAME_WORDS_PER_LINE_W;
    wire [FRAME_AW:0] cap_word_idx_ext_s0 = y_words_s0 + line_word_offset_s0;
    wire              cap_in_range_s0     = (cap_word_idx_ext_s0 < FRAME_WORDS_W);

    reg                  cap_valid_s1_q;
    reg                  cap_bank_s1_q;
    reg [FRAME_AW-1:0]   cap_waddr_s1_q;
    reg [DATA_WIDTH-1:0] cap_wdata_s1_q;
    reg [STRB_WIDTH-1:0] cap_wstrb_s1_q;

    reg                  cap_we0_q;
    reg                  cap_we1_q;
    reg [FRAME_AW-1:0]   cap_waddr_q;
    reg [DATA_WIDTH-1:0] cap_wdata_q;
    reg [STRB_WIDTH-1:0] cap_wstrb_q;

    always @(posedge clk_i) begin
        cap_valid_s0_q <= pixel_valid;
        if (pixel_valid) begin
            cap_bank_s0_q  <= write_bank_q;
            cap_x_s0_q     <= cap_addr_x;
            cap_y_s0_q     <= cap_addr_y;
            cap_pixel_s0_q <= cap_dout;
        end

        cap_valid_s1_q <= cap_valid_s0_q && cap_in_range_s0;
        if (cap_valid_s0_q && cap_in_range_s0) begin
            cap_bank_s1_q  <= cap_bank_s0_q;
            cap_waddr_s1_q <= cap_word_idx_ext_s0[FRAME_AW-1:0];
            cap_wdata_s1_q <= gray_word_at_lane(cap_x_s0_q[1:0], gray_s0);
            cap_wstrb_s1_q <= gray_strobe_at_lane(cap_x_s0_q[1:0]);
        end

        cap_we0_q   <= cap_valid_s1_q && !cap_bank_s1_q;
        cap_we1_q   <= cap_valid_s1_q && cap_bank_s1_q;
        cap_waddr_q <= cap_waddr_s1_q;
        cap_wdata_q <= cap_wdata_s1_q;
        cap_wstrb_q <= cap_wstrb_s1_q;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            seq_q        <= 32'h0000_0000;
            ready_bank_q <= 32'h0000_0000;
            drop_count_q <= 32'h0000_0000;
            write_bank_q <= 1'b0;
        end else if (frame_done) begin
            ready_bank_q <= {31'h0, write_bank_q};
            if ((seq_q != 32'h0) && (read_bank_q[0] == write_bank_q)) begin
                drop_count_q <= drop_count_q + 32'h1;
            end
            seq_q        <= seq_q + 32'h1;
            write_bank_q <= ~write_bank_q;
        end
    end

    // -------------------------------------------------------------------------
    // Frame BRAMs
    // -------------------------------------------------------------------------
    reg [FRAME_AW-1:0] frame_raddr_q;
    reg                frame_rbank_q;
    reg                frame_rinrange_q;
    reg                frame0_ren_q;
    reg                frame1_ren_q;
    wire [31:0]        frame0_rdata;
    wire [31:0]        frame1_rdata;

    sdp_2clk #(
        .NUM_COL         (4),
        .COL_WIDTH       (8),
        .RAM_WIDTH       (32),
        .RAM_DEPTH       (FRAME_WORDS),
        .RAM_PERFORMANCE ("LOW_LATENCY"),
        .INIT_FILE       ("")
    ) frame_bank0 (
        .clka   (clk_i                    ),
        .ena    (cap_we0_q                ),
        .wea    (cap_we0_q ? cap_wstrb_q : 4'b0000),
        .addra  (cap_waddr_q              ),
        .dina   (cap_wdata_q              ),
        .addrb  (frame_raddr_q            ),
        .enb    (frame0_ren_q             ),
        .clkb   (clk_i                    ),
        .rstb   (rst_i                    ),
        .regceb (1'b0                     ),
        .doutb  (frame0_rdata             )
    );

    sdp_2clk #(
        .NUM_COL         (4),
        .COL_WIDTH       (8),
        .RAM_WIDTH       (32),
        .RAM_DEPTH       (FRAME_WORDS),
        .RAM_PERFORMANCE ("LOW_LATENCY"),
        .INIT_FILE       ("")
    ) frame_bank1 (
        .clka   (clk_i                    ),
        .ena    (cap_we1_q                ),
        .wea    (cap_we1_q ? cap_wstrb_q : 4'b0000),
        .addra  (cap_waddr_q              ),
        .dina   (cap_wdata_q              ),
        .addrb  (frame_raddr_q            ),
        .enb    (frame1_ren_q             ),
        .clkb   (clk_i                    ),
        .rstb   (rst_i                    ),
        .regceb (1'b0                     ),
        .doutb  (frame1_rdata             )
    );

    // -------------------------------------------------------------------------
    // Write path
    // -------------------------------------------------------------------------
    reg                    bvalid_q;
    reg [`BRESP_WIDTH-1:0] bresp_q;

    wire        w_is_csr = (awaddr_i >= CSR_BASE) && (awaddr_i < (CSR_BASE + 32'h1000));
    wire [31:0] w_off    = awaddr_i - CSR_BASE;

    assign wready_o = !bvalid_q;
    assign bvalid_o = bvalid_q;
    assign bresp_o  = bresp_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            bvalid_q    <= 1'b0;
            bresp_q     <= `BRESP_OKAY;
            ctrl_q      <= 32'h0000_0001;
            read_bank_q <= 32'h0000_0000;
            gain_q      <= 32'h0000_0040;
        end else begin
            if (bvalid_q && bready_i) begin
                bvalid_q <= 1'b0;
            end

            if (wvalid_i && wready_o) begin
                bvalid_q <= 1'b1;
                bresp_q  <= `BRESP_OKAY;

                if (!w_is_csr || (awaddr_i[1:0] != 2'b00)) begin
                    bresp_q <= `BRESP_DECERR;
                end else begin
                    case (w_off)
                        REG_CTRL: begin
                            ctrl_q <= apply_wstrb(ctrl_q, wdata_i, wstrb_i);
                        end
                        REG_READ_BANK: begin
                            read_bank_q <= apply_wstrb(read_bank_q, wdata_i, wstrb_i) & 32'h0000_0001;
                        end
                        REG_GAIN: begin
                            gain_q <= apply_wstrb(gain_q, wdata_i, wstrb_i) & 32'h0000_00FF;
                        end
                        default: begin
                            bresp_q <= `BRESP_SLVERR;
                        end
                    endcase
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read path
    // -------------------------------------------------------------------------
    localparam [1:0] RD_IDLE = 2'd0;
    localparam [1:0] RD_RAM  = 2'd1;
    localparam [1:0] RD_RESP = 2'd2;

    reg [1:0]              rd_state_q;
    reg                    rvalid_q;
    reg [DATA_WIDTH-1:0]   rdata_q;
    reg [`RRESP_WIDTH-1:0] rresp_q;

    wire        r_is_csr      = (araddr_i >= CSR_BASE) && (araddr_i < (CSR_BASE + 32'h1000));
    wire        r_is_frame    = (araddr_i >= FRAME_BASE) && (araddr_i < (FRAME_BASE + FRAME_APERTURE_BYTES));
    wire [31:0] r_csr_off     = araddr_i - CSR_BASE;
    wire [31:0] r_frame_off   = araddr_i - FRAME_BASE;
    wire [FRAME_AW:0] r_word_idx_ext = r_frame_off[FRAME_AW+2:2];

    assign arready_o = (rd_state_q == RD_IDLE);
    assign rvalid_o  = rvalid_q;
    assign rdata_o   = rdata_q;
    assign rresp_o   = rresp_q;

    always @(posedge clk_i) begin
        if (rst_i) begin
            rd_state_q      <= RD_IDLE;
            rvalid_q        <= 1'b0;
            rdata_q         <= 32'h0000_0000;
            rresp_q         <= `RRESP_OKAY;
            frame_raddr_q   <= {FRAME_AW{1'b0}};
            frame_rbank_q   <= 1'b0;
            frame_rinrange_q <= 1'b0;
            frame0_ren_q    <= 1'b0;
            frame1_ren_q    <= 1'b0;
        end else begin
            frame0_ren_q <= 1'b0;
            frame1_ren_q <= 1'b0;

            case (rd_state_q)
                RD_IDLE: begin
                    if (arvalid_i) begin
                        if (araddr_i[1:0] != 2'b00) begin
                            rvalid_q   <= 1'b1;
                            rresp_q    <= `RRESP_SLVERR;
                            rdata_q    <= 32'h0000_0000;
                            rd_state_q <= RD_RESP;
                        end else if (r_is_csr) begin
                            rvalid_q   <= 1'b1;
                            rresp_q    <= `RRESP_OKAY;
                            rd_state_q <= RD_RESP;
                            case (r_csr_off)
                                REG_ID        : rdata_q <= CAMERA_ID;
                                REG_CTRL      : rdata_q <= ctrl_q;
                                REG_STATUS    : rdata_q <= status_r;
                                REG_WIDTH     : rdata_q <= FRAME_WIDTH;
                                REG_HEIGHT    : rdata_q <= FRAME_HEIGHT;
                                REG_STRIDE    : rdata_q <= FRAME_STRIDE;
                                REG_FRAMEBYTES: rdata_q <= FRAME_BYTES;
                                REG_SEQ       : rdata_q <= seq_q;
                                REG_READY_BANK: rdata_q <= ready_bank_q;
                                REG_READ_BANK : rdata_q <= read_bank_q;
                                REG_DROP_COUNT: rdata_q <= drop_count_q;
                                REG_GAIN      : rdata_q <= gain_q;
                                default: begin
                                    rresp_q <= `RRESP_DECERR;
                                    rdata_q <= 32'h0000_0000;
                                end
                            endcase
                        end else if (r_is_frame) begin
                            frame_raddr_q    <= r_word_idx_ext[FRAME_AW-1:0];
                            frame_rbank_q    <= read_bank_q[0];
                            frame_rinrange_q <= (r_word_idx_ext < FRAME_WORDS_W);
                            if (read_bank_q[0]) begin
                                frame1_ren_q <= (r_word_idx_ext < FRAME_WORDS_W);
                            end else begin
                                frame0_ren_q <= (r_word_idx_ext < FRAME_WORDS_W);
                            end
                            rd_state_q <= RD_RAM;
                        end else begin
                            rvalid_q   <= 1'b1;
                            rresp_q    <= `RRESP_DECERR;
                            rdata_q    <= 32'h0000_0000;
                            rd_state_q <= RD_RESP;
                        end
                    end
                end
                RD_RAM: begin
                    rvalid_q   <= 1'b1;
                    rresp_q    <= `RRESP_OKAY;
                    rd_state_q <= RD_RESP;
                    if (frame_rinrange_q) begin
                        rdata_q <= frame_rbank_q ? frame1_rdata : frame0_rdata;
                    end else begin
                        rdata_q <= 32'h0000_0000;
                    end
                end
                RD_RESP: begin
                    if (rvalid_q && rready_i) begin
                        rvalid_q   <= 1'b0;
                        rd_state_q <= RD_IDLE;
                    end
                end
                default: begin
                    rd_state_q <= RD_IDLE;
                end
            endcase
        end
    end

endmodule

`resetall
