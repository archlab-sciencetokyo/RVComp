/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* Asynchronous FIFO */
/******************************************************************************************/
module async_fifo #(
    parameter  ADDR_WIDTH       = 0         , // address width
    parameter  DATA_WIDTH       = 0           // data width
) (
    input  wire                  wclk_i     , // write clock
    input  wire                  rclk_i     , // read clock
    input  wire                  wrst_i     , // write reset
    input  wire                  rrst_i     , // read reset
    input  wire                  wvalid_i   , // write valid
    output wire                  wready_o   , // write ready
    input  wire [DATA_WIDTH-1:0] wdata_i    , // write data
    output wire                  rvalid_o   , // read valid
    input  wire                  rready_i   , // read ready
    output reg  [DATA_WIDTH-1:0] rdata_o      // read data
);

    ///// DRC: design rule check
    initial begin
        if (ADDR_WIDTH==0) $fatal(1, "specify a async_fifo ADDR_WIDTH");
        if (DATA_WIDTH==0) $fatal(1, "specify a async_fifo DATA_WIDTH");
    end

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1];
    reg  [ADDR_WIDTH:0] waddr_q, waddr_d, gray_waddr1, gray_waddr2;
    reg  [ADDR_WIDTH:0] raddr_q, raddr_d, gray_raddr1, gray_raddr2;
    wire [ADDR_WIDTH:0] gray_waddr = waddr_q ^ {1'b0, waddr_q[ADDR_WIDTH:1]};
    wire [ADDR_WIDTH:0] gray_raddr = raddr_q ^ {1'b0, raddr_q[ADDR_WIDTH:1]};

    always @(posedge rclk_i) begin
        gray_waddr1 <= gray_waddr   ;
        gray_waddr2 <= gray_waddr1  ;
    end

    always @(posedge wclk_i) begin
        gray_raddr1 <= gray_raddr   ;
        gray_raddr2 <= gray_raddr1  ;
    end

    wire empty_n    = (gray_raddr!=gray_waddr2);
    wire full_n     = (gray_waddr!={~gray_raddr2[ADDR_WIDTH:ADDR_WIDTH-1], gray_raddr2[ADDR_WIDTH-2:0]});

    // write
    assign wready_o = full_n;

    always @(*) begin
        waddr_d     = waddr_q       ;
        if (wvalid_i && wready_o) begin
            waddr_d     = waddr_q+'h1   ;
        end
    end

    always @(posedge wclk_i) begin
        if (wvalid_i && wready_o) begin
            ram[waddr_q[ADDR_WIDTH-1:0]]    <= wdata_i  ;
        end
        if (wrst_i) begin
            waddr_q     <= 'h0      ;
        end else begin
            waddr_q     <= waddr_d  ;
        end
    end

    // read
    reg  rvalid_q   , rvalid_d  ;

    assign rvalid_o = rvalid_q  ;

    always @(*) begin
        rvalid_d    = empty_n       ;
        raddr_d     = raddr_q       ;
        if (rvalid_o && rready_i) begin
            rvalid_d    = 1'b0          ;
            raddr_d     = raddr_q+'h1   ;
        end
    end

    always @(posedge rclk_i) begin
        rdata_o <= ram[raddr_q[ADDR_WIDTH-1:0]] ;
        if (rrst_i) begin
            rvalid_q    <= 1'b0     ;
            raddr_q     <= 'h0      ;
        end else begin
            rvalid_q    <= rvalid_d ;
            raddr_q     <= raddr_d  ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
