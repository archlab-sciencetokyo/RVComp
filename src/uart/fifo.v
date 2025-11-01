/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* fifo: first in first out (FIFO) buffer */
/******************************************************************************************/
module fifo #(
    parameter  DATA_WIDTH       = 0             , // data width
    parameter  FIFO_DEPTH       = 0               // fifo depth
) (
    input  wire                  clk_i          , // clock
    input  wire                  rst_i          , // reset
    output wire                  full_o         , // is full
    output wire                  empty_o        , // is empty
    input  wire                  wvalid_i       , // write request valid
    output wire                  wready_o       , // write request ready
    input  wire [DATA_WIDTH-1:0] wdata_i        , // write data
    input  wire                  rvalid_i       , // read request valid
    output wire                  rready_o       , // read request ready
    output reg  [DATA_WIDTH-1:0] rdata_o          // read data
);

    (* ram_style = "block" *) reg  [DATA_WIDTH-1:0] ram [0:FIFO_DEPTH-1];

    reg                             full_nq     , full_nd   ;
    reg                             empty_nq    , empty_nd  ;
    reg    [$clog2(FIFO_DEPTH)-1:0] waddr_q     , waddr_d   ;
    reg    [$clog2(FIFO_DEPTH)-1:0] raddr_q     , raddr_d   ;
    reg  [$clog2(FIFO_DEPTH+1)-1:0] count_q     , count_d   ;
    reg                             rready_q    , rready_d  ;

    assign full_o   = !full_nq  ;
    assign empty_o  = !empty_nq ;
    assign wready_o = full_nq   ;
    assign rready_o = rready_q  ;

    always @(*) begin
        full_nd     = full_nq   ;
        empty_nd    = empty_nq  ;
        waddr_d     = waddr_q   ;
        raddr_d     = raddr_q   ;
        count_d     = count_q   ;
        rready_d    = empty_nq  ;
        if (rvalid_i && rready_o) begin
            raddr_d     = raddr_q+'h1   ;
            rready_d    = 1'b0          ;
        end
        if (wvalid_i && wready_o) begin
            waddr_d     = waddr_q+'h1   ;
        end
        case ({wvalid_i && wready_o, rvalid_i && rready_o}) // {fifo_write, fifo_read}
            2'b10  : begin
                if (count_q==FIFO_DEPTH-1) full_nd  = 1'b0  ;
                empty_nd    = 1'b1          ;
                count_d     = count_q+'h1   ;
            end
            2'b01  : begin
                full_nd     = 1'b1          ;
                if (count_q=='h1         ) empty_nd = 1'b0  ;
                count_d     = count_q-'h1   ;
            end
            default: ;
        endcase
    end

    // fifo read/write
    always @(posedge clk_i) begin
        rdata_o <= ram[raddr_q];
        if (wvalid_i && wready_o) begin
            ram[waddr_q] <= wdata_i;
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            full_nq     <= 1'b1     ;
            empty_nq    <= 1'b0     ;
            waddr_q     <= 'h0      ;
            raddr_q     <= 'h0      ;
            count_q     <= 'h0      ;
            rready_q    <= 1'b0     ;
        end else begin
            full_nq     <= full_nd  ;
            empty_nq    <= empty_nd ;
            waddr_q     <= waddr_d  ;
            raddr_q     <= raddr_d  ;
            count_q     <= count_d  ;
            rready_q    <= rready_d ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
