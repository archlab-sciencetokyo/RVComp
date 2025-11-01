/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`resetall
`default_nettype none

/* universal asynchronous receiver/transmitter (UART) receiver */
/******************************************************************************************/
module uart_tx #(
    parameter  CLK_FREQ_MHZ     = 0             , // clock frequency [MHz]
    parameter  BAUD_RATE        = 0             , // baud rate [bps]
    localparam WAIT_COUNT       = (CLK_FREQ_MHZ*1000*1000)/BAUD_RATE // wait count
) (
    input  wire                  clk_i          , // clock
    input  wire                  rst_i          , // reset
    output wire                  txd_o          , // transmit data (uart pin)
    input  wire                  wvalid_i       , // transmit request valid
    output wire                  wready_o       , // transmit request ready
    input  wire            [7:0] wdata_i          // transmit data
);

    // DRC: design rule check
    initial begin
        if (CLK_FREQ_MHZ==0) $fatal(1, "specify a uart_tx CLK_FREQ_MHZ");
        if (BAUD_RATE   ==0) $fatal(1, "specify a uart_tx BAUD_RATE");
    end

    // FSM
    localparam IDLE = 1'b0, RUN = 1'b1;
    reg  [0:0] state_q  , state_d   ;

    reg                           wready_q      , wready_d      ;
    reg                     [8:0] buf_q = 9'h1  , buf_d         ;
    reg                     [3:0] bit_cntr_q    , bit_cntr_d    ;
    reg  [$clog2(WAIT_COUNT)-1:0] wait_cntr_q   , wait_cntr_d   ;

    assign txd_o    = buf_q[0]          ;
    assign wready_o = wready_q          ;

    always @(*) begin
        wready_d    = wready_q          ;
        buf_d       = buf_q             ;
        bit_cntr_d  = bit_cntr_q        ;
        wait_cntr_d = wait_cntr_q-'h1   ;
        state_d     = state_q           ;
        case (state_q)
            IDLE    : begin
                if (wvalid_i) begin // (wvalid_i && wready_o)
                    wready_d        = 1'b0              ;
                    buf_d           = {wdata_i, 1'b0}   ;
                    bit_cntr_d      = 4'd9              ;
                    wait_cntr_d     = WAIT_COUNT-'h1    ;
                    state_d         = RUN               ;
                end
            end
            RUN     : begin
                if (~|wait_cntr_q) begin // (wait_cntr_q==0)
                    buf_d           = {1'b1, buf_q[8:1]};
                    bit_cntr_d      = bit_cntr_q-4'd1   ;
                    wait_cntr_d     = WAIT_COUNT-'h1    ;
                end
                if (wait_cntr_q==((WAIT_COUNT-1)/2)) begin
                    if (~|bit_cntr_q) begin // (bit_cntr_q==0)
                        wready_d    = 1'b1              ;
                        state_d     = IDLE              ;
                    end
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            wready_q    <= 1'b1         ;
            buf_q       <= 9'h1         ; // txd_o <= 1'b1;
            state_q     <= IDLE         ;
        end else begin
            wready_q    <= wready_d     ;
            buf_q       <= buf_d        ;
            bit_cntr_q  <= bit_cntr_d   ;
            wait_cntr_q <= wait_cntr_d  ;
            state_q     <= state_d      ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
