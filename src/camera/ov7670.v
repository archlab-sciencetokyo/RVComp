/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */
module ov7670(
    input  wire        CLK,
    input  wire        RST,
    output reg  [15:0] cap_dout,
    output reg  [ 9:0] cap_addr_x,
    output reg  [ 9:0] cap_addr_y,
    output reg         cap_en,
    input  wire [ 7:0] w_gain,
    input  wire        clk_cam_i2c,       // 25MHz
    input  wire        clk_cam_pix,   // 48Mhz
    input  wire        pclk,          // OV7670 camera PCLK
    input  wire        camera_v_sync, // OV7670 camera VSYNC
    input  wire        camera_h_ref,  // OV7670 camera HREF
    input  wire [ 7:0] din,           // OV7670 camera D0 to D7
    output wire        sioc,          // OV7670 camera SIO_C
    output wire        siod,          // OV7670 camera SIO_D
    output wire        reset,        // OV7670 camera RESET#
    output wire        power_down,    // OV7670 camera PWDN
    output wire        xclk,         // OV7670 camera XCLK
    output wire        sccb_done     // diagnostic: SCCB register init complete
);
    assign reset       = 1;       // Normal mode
    assign power_down  = 0;       // Normal mode
    //assign xclk        = clk_cam_i2c; //
    assign xclk        = clk_cam_pix; //

    /***** reset the camera configuration when the gain parameter of camera is changed                      *****/
    /************************************************************************************************************/
    reg       r_resend = 0;
    reg [7:0] r_gain = 0;
    reg [31:0] r_c = 0;
    always @(posedge clk_cam_i2c) begin
        if(r_c[19:0]==0) r_gain <= w_gain;
        r_resend <= (r_c[19:0]==0 && r_gain!=w_gain);
        r_c <= r_c + 1;
    end
    /************************************************************************************************************/
    wire [15:0] command;
    wire        taken, done;

    // SW reset delay: after first taken (COM7=0x80 sent), hold address counter for 2ms
    // so OV7670 completes its internal reset before receiving real register writes.
    reg  [16:0] sw_rst_delay_q  = 17'd0;
    reg         sw_rst_sent_q   = 1'b0;
    wire        sw_rst_delay_done = (sw_rst_delay_q >= 17'd48000); // 2ms at 24MHz
    wire        advance_gated = taken && (!sw_rst_sent_q || sw_rst_delay_done);

    always @(posedge clk_cam_i2c) begin
        if (r_resend) begin
            sw_rst_delay_q <= 17'd0;
            sw_rst_sent_q  <= 1'b0;
        end else begin
            if (!sw_rst_sent_q && taken)             sw_rst_sent_q  <= 1'b1;
            if (sw_rst_sent_q && !sw_rst_delay_done) sw_rst_delay_q <= sw_rst_delay_q + 17'd1;
        end
    end

    m_camera_reg cregs0 (clk_cam_i2c, r_resend, advance_gated, command, done, w_gain);
    m_i2c_camera i2ccamera0 (clk_cam_i2c, siod, sioc, taken, ~done, 8'h42, command);
    assign sccb_done = done;

    reg [15:0] r_cam_dout    = 0; // 12bit-color, RGB444
    reg        r_cam_we      = 0;
    reg [1:0]  r_write_state = 0;
    reg [15:0] r_cam_data    = 0;

    always @(posedge pclk) begin
        if(camera_v_sync == 1'b1) r_write_state <= 0;
        else begin
            r_cam_dout <= r_cam_data;
            r_write_state <= {r_write_state[0], (camera_h_ref & ~r_write_state[0])};
            r_cam_data <= {r_cam_data[7:0], din};
            r_cam_we <= r_write_state[1];
        end
    end
    
    /************************************************************************************************************/
    reg [9:0] r_x = 0;
    reg [9:0] r_y = 0;
    always @(posedge pclk) if(camera_v_sync) begin r_x<=0; r_y<=0; end
        else if(r_cam_we) begin
            r_x  <= (r_x==319) ? 0 : r_x + 1;
            r_y  <= (r_x!=319) ? r_y : (r_y==239) ? 0 : r_y + 1;
        end
    
    wire afifo_empty, afifo_full;
    wire [15:0] w_cap_dout;
    wire [ 9:0] w_cap_addr_x, w_cap_addr_y;
    wire        w_cap_en;
    AsyncFIFO #(
        .DATA_WIDTH(10+10+16),
        .ADDR_WIDTH(6))
    afifo(
         .wclk(pclk),
    	 .rclk(CLK),
         .i_wrst_x(!RST),
         .i_rrst_x(!RST),
    	 .i_wen(r_cam_we & !afifo_full),
    	 .i_data({r_y, r_x, r_cam_dout}),
         .i_ren(!afifo_empty),
    	 .o_data({w_cap_addr_y, w_cap_addr_x, w_cap_dout}),
    	 .o_empty(afifo_empty),
    	 .o_full(afifo_full)
    );
    assign w_cap_en = !afifo_empty;
    
    always @(posedge CLK) begin
        cap_dout   <= w_cap_dout;
        cap_addr_x <= w_cap_addr_x;
        cap_addr_y <= w_cap_addr_y;
        cap_en     <= w_cap_en;
    end
    

endmodule

///////////////////////////////////////////////////////////////////////////////
module AsyncFIFO #(
    parameter DATA_WIDTH  = 512,
	parameter ADDR_WIDTH  = 8) // FIFO_DEPTH = 2^ADDR_WIDTH
(
    input  wire                    wclk,
	input  wire                    rclk,
    input  wire                    i_wrst_x,
    input  wire                    i_rrst_x,
	input  wire                    i_wen,
	input  wire [DATA_WIDTH-1 : 0] i_data,
    input  wire                    i_ren,
	output wire [DATA_WIDTH-1 : 0] o_data,
	output wire                    o_empty,
	output wire                    o_full);

    reg  [DATA_WIDTH-1 : 0] afifo[(2**ADDR_WIDTH)-1 : 0];
    reg  [ADDR_WIDTH : 0]   waddr;
    reg  [ADDR_WIDTH : 0]   raddr;

    reg  [ADDR_WIDTH : 0]   raddr_gray1;
    reg  [ADDR_WIDTH : 0]   raddr_gray2;

    reg  [ADDR_WIDTH : 0]   waddr_gray1;
    reg  [ADDR_WIDTH : 0]   waddr_gray2;

    wire [DATA_WIDTH-1 : 0] data;

    wire [ADDR_WIDTH : 0]   raddr_gray;
    wire [ADDR_WIDTH : 0]   waddr_gray;

    wire [ADDR_WIDTH : 0]   raddr2;
    wire [ADDR_WIDTH : 0]   waddr2;

    genvar genvar_i;

    // output signals
    assign o_data  = data;
    assign o_empty = (raddr == waddr2);
    assign o_full  = (waddr[ADDR_WIDTH] != raddr2[ADDR_WIDTH]) &&
                     (waddr[ADDR_WIDTH-1 : 0] == raddr2[ADDR_WIDTH-1 : 0]);

    // binary code to gray code
    assign raddr_gray = raddr[ADDR_WIDTH : 0] ^ {1'b0, raddr[ADDR_WIDTH : 1]};
    assign waddr_gray = waddr[ADDR_WIDTH : 0] ^ {1'b0, waddr[ADDR_WIDTH : 1]};

    // gray code to binary code
    generate
	    for (genvar_i = 0; genvar_i <= ADDR_WIDTH; genvar_i = genvar_i + 1) begin
		    assign raddr2[genvar_i] = ^raddr_gray2[ADDR_WIDTH : genvar_i];
		    assign waddr2[genvar_i] = ^waddr_gray2[ADDR_WIDTH : genvar_i];
	    end
    endgenerate

    // double flopping read address before using it in write clock domain
    always @(posedge wclk) begin
	    if (!i_wrst_x) begin
		    raddr_gray1 <= 0;
		    raddr_gray2 <= 0;
	    end else begin
		    raddr_gray1 <= raddr_gray;
		    raddr_gray2 <= raddr_gray1;
	    end
    end

    // double flopping write address before using it in read clock domain
    always @(posedge rclk) begin
	    if (!i_rrst_x) begin
		    waddr_gray1 <= 0;
		    waddr_gray2 <= 0;
	    end else begin
		    waddr_gray1 <= waddr_gray;
		    waddr_gray2 <= waddr_gray1;
	    end
    end

    // read
    assign data = afifo[raddr[ADDR_WIDTH-1 : 0]];
    always @(posedge rclk) begin
	    if (!i_rrst_x) begin
		    raddr <= 0;
	    end else if (i_ren) begin
		    raddr <= raddr + 1;
	    end
    end

    // write
    always @(posedge wclk) begin
	    if (!i_wrst_x) begin
		    waddr <= 0;
	    end else if (i_wen) begin
		    afifo[waddr[ADDR_WIDTH-1 : 0]] <= i_data;
		    waddr <= waddr + 1;
	    end
    end

endmodule
/***** initialize date for ov7670 camera (320x240 pixel) *****/
/****************************************************************************************************************/
module m_camera_reg (w_clk, resend, advance, send_reg, done, w_gain);
    input  wire        w_clk;
    input  wire        resend;
    input  wire        advance;
    output reg [15:0]  send_reg = 0;
    output reg         done = 0;
    input  wire [7:0]  w_gain;

    reg [7:0]  address;
    always @(posedge w_clk) address <= (resend) ? 0 : (advance) ? address + 1 : address;

    always @(posedge w_clk) begin
        case (address)
            16'h00 :  send_reg <= 16'h1280;  // reset
            16'h03 :  send_reg <= 16'h030A;
            16'h04 :  send_reg <= 16'h0C00;
            16'h05 :  send_reg <= 16'h0E61;
            16'h06 :  send_reg <= 16'h0F4B;
            16'h07 :  send_reg <= 16'h1500;
            16'h08 :  send_reg <= 16'h1602;
            16'h09 :  send_reg <= 16'h1713;
            16'h0A :  send_reg <= 16'h1801;
            16'h0B :  send_reg <= 16'h1902;
            16'h0C :  send_reg <= 16'h1A7A;
            16'h0D :  send_reg <= 16'h1E07;
            16'h0E :  send_reg <= 16'h2102;
            16'h0F :  send_reg <= 16'h2291;
            16'h10 :  send_reg <= 16'h2907;
            16'h11 :  send_reg <= 16'h32B6;
            16'h12 :  send_reg <= 16'h330B;
            16'h13 :  send_reg <= 16'h3411;
            16'h14 :  send_reg <= 16'h350B;
            16'h15 :  send_reg <= 16'h371D;
            16'h16 :  send_reg <= 16'h3871;
            16'h17 :  send_reg <= 16'h392A;
            16'h18 :  send_reg <= 16'h3B12;
            16'h19 :  send_reg <= 16'h3C78;
            16'h1A :  send_reg <= 16'h3DC3;
            16'h1B :  send_reg <= 16'h3E00;
            16'h1C :  send_reg <= 16'h3F00;
            16'h1D :  send_reg <= 16'h4108;
            16'h1E :  send_reg <= 16'h4138;
            16'h1F :  send_reg <= 16'h430A;
            16'h20 :  send_reg <= 16'h44F0;

            16'h21 :  send_reg <= 16'h4534;
            16'h22 :  send_reg <= 16'h4658;
            16'h23 :  send_reg <= 16'h4728;
            16'h24 :  send_reg <= 16'h483A;
            16'h25 :  send_reg <= 16'h4B09;
            16'h26 :  send_reg <= 16'h4C00;
            16'h27 :  send_reg <= 16'h4D40;
            16'h28 :  send_reg <= 16'h4E20;
            16'h29 :  send_reg <= 16'h4F80;
            16'h2A :  send_reg <= 16'h5080;
            16'h2B :  send_reg <= 16'h5100;
            16'h2C :  send_reg <= 16'h5222;
            16'h2D :  send_reg <= 16'h535E;
            16'h2E :  send_reg <= 16'h5480;
            16'h2F :  send_reg <= 16'h5640;
            16'h30 :  send_reg <= 16'h589E;
            16'h31 :  send_reg <= 16'h5988;
            16'h32 :  send_reg <= 16'h5A88;
            16'h33 :  send_reg <= 16'h5B44;
            16'h34 :  send_reg <= 16'h5C67;
            16'h35 :  send_reg <= 16'h5D49;
            16'h36 :  send_reg <= 16'h5E0E;
            16'h37 :  send_reg <= 16'h6900;
            16'h39 :  send_reg <= 16'h6B0A;
            16'h3A :  send_reg <= 16'h6C0A;
            16'h3B :  send_reg <= 16'h6D55;
            16'h3C :  send_reg <= 16'h6E11;
            16'h3D :  send_reg <= 16'h6F9F;
            16'h3E :  send_reg <= 16'h703A;
            16'h3F :  send_reg <= 16'h7135;
            16'h40 :  send_reg <= 16'h7211;

            16'h41 :  send_reg <= 16'h73F0;
            16'h42 :  send_reg <= 16'h7410;
            16'h43 :  send_reg <= 16'h7505;
            16'h44 :  send_reg <= 16'h76E1;
            16'h45 :  send_reg <= 16'h7701;
            16'h46 :  send_reg <= 16'h7804;
            16'h47 :  send_reg <= 16'h7901;
            16'h48 :  send_reg <= 16'h8D4F;
            16'h49 :  send_reg <= 16'h8E00;
            16'h4A :  send_reg <= 16'h8F00;
            16'h4B :  send_reg <= 16'h9000;
            16'h4C :  send_reg <= 16'h9100;
            16'h4D :  send_reg <= 16'h9600;
            16'h4E :  send_reg <= 16'h9600;
            16'h4F :  send_reg <= 16'h9730;
            16'h50 :  send_reg <= 16'h9820;
            16'h51 :  send_reg <= 16'h9930;
            16'h52 :  send_reg <= 16'h9A00;
            16'h53 :  send_reg <= 16'h9A84;
            16'h54 :  send_reg <= 16'h9B29;
            16'h55 :  send_reg <= 16'h9C03;
            16'h56 :  send_reg <= 16'h9D4C;
            16'h57 :  send_reg <= 16'h9E3F;
            16'h58 :  send_reg <= 16'hA202;
            16'h59 :  send_reg <= 16'hA488;
            16'h5A :  send_reg <= 16'hB084;
            16'h5B :  send_reg <= 16'hB10C;
            16'h5C :  send_reg <= 16'hB20E;
            16'h5D :  send_reg <= 16'hB382;
            16'h5E :  send_reg <= 16'hB80A;
            16'h5F :  send_reg <= 16'hC8F0;
            16'h60 :  send_reg <= 16'hC960;
            16'h64 :  send_reg <= 16'h1100;  // set input clock divide to 1
            16'h65 :  send_reg <= 16'h0400;  // reset COM1
            16'h67 :  send_reg <= 16'h3A04;  // set TSLB from ORG (not auto-reset window)
            16'h68 :  send_reg <= 16'h1438;  // set COM9 from ORG about AGC

            16'h69 :  send_reg <= 16'h1E07;  // set no flip and no mirror
            16'h6A :  send_reg <= 16'h6B0A;  // set input clock multiple to 1

            16'h6B :  send_reg <= 16'h1214;  // set size to QVGA
            16'h6C :  send_reg <= 16'h1716;  // set HSTART
            16'h6D :  send_reg <= 16'h1804;  // set HSTOP
            16'h6E :  send_reg <= 16'h3280;  // set HREF
            16'h6F :  send_reg <= 16'h1902;  // set VSTRT
            16'h70 :  send_reg <= 16'h1A7A;  // set VSTOP
            16'h71 :  send_reg <= 16'h030A;  // set VREF
            16'h72 :  send_reg <= 16'h0C04;  // set DCW to enable
            16'h73 :  send_reg <= 16'h3E19;  // set COM14
            16'h74 :  send_reg <= 16'h703A;  // set SCALING_XSC
            16'h75 :  send_reg <= 16'h7135;  // set SCALING_YSC
            16'h76 :  send_reg <= 16'h7211;  // set SCALING_DCWCTR
            16'h77 :  send_reg <= 16'h73F1;  // set SCALING_PCLK_DIV
            16'h78 :  send_reg <= 16'hA202;  // set SCALING_PCLK_DELAY
            16'h79 :  send_reg <= {8'h40, 8'b11010000};  // set RGB565
            16'h7A :  send_reg <= {8'h13, 8'b00000000};  // disable AGC AWB AEC
            16'h7B :  send_reg <= 16'h00_00; // GAIN
            16'h7C :  send_reg <= {8'h01, w_gain}; // BLUE
            16'h7D :  send_reg <= {8'h02, w_gain}; // RED
            16'h7E :  send_reg <= {8'h6A, w_gain}; // GGAIN 
            default : send_reg <= 16'h_0000;
        endcase
    end
    always @(posedge w_clk) done <= (resend) ? 0 : (address==16'h7F) ? 1 : done;
endmodule

/***** i2c controller for video camera                                                                      *****/
/****************************************************************************************************************/
module m_i2c_camera (w_clk, SDA, SCL, taken, send, id, value);
    input  wire        w_clk;
    inout  wire        SDA;
    output reg         SCL;
    output reg         taken;
    input  wire        send;
    input  wire [7:0]  id;
    input  wire [15:0] value;

    wire [7:0] div_out;
    reg  [7:0] divider = 8'b_1111_1100;
    reg [31:0] busy_sr = 32'h0;
    reg [31:0] data_sr = 32'h_FFFF_FFFF;

    assign div_out = divider;
    assign SDA = (busy_sr[11:10]==2'b10 || busy_sr[20:19]==2'b10 || busy_sr[29:28]==2'b10) ? 1'bz : data_sr[31];

    always @(posedge w_clk) taken <= (busy_sr[31]==0 && divider==0 && send) ? 1 : 0;
    
    always @(posedge w_clk) begin
        if(busy_sr[31] == 0) begin
            SCL <= 1;
            if(send == 1) begin
                if(divider == 8'b_0000_0000) begin
                    data_sr <= {3'b100, id, 1'b0, value[15:8], 1'b0, value[7:0], 1'b0, 2'b01};
                    busy_sr <= 32'h_FFFF_FFFF;
                end else begin
                    divider <= divider + 1;
                end
            end
        end else begin
            case ( {busy_sr[31:29], busy_sr[2:0]} )
                6'b_111111 : SCL <= 1;                                   // start seq #1
                6'b_111110 : SCL <= 1;                                   // start seq #2
                6'b_111100 : SCL <= 0;                                   // start seq #3
                6'b_110000 : SCL <= (divider[7:6]==2'b00) ? 0 : 1;       // end seq #1
                6'b_100000 : SCL <= 1;                                   // end seq #2
                6'b_000000 : SCL <= 1;                                   // Idle
                default : SCL <= (divider[7:6]==2'b00 || divider[7:6]==2'b11) ? 0 : 1;
            endcase
            if(divider == 8'b_1111_1111) begin
                 busy_sr <= {busy_sr[30:0], 1'b0};
                 data_sr <= {data_sr[30:0], 1'b1};
            end
            divider <= divider + 1;
        end
    end
endmodule
