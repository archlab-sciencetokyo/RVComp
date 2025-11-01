/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`resetall
`default_nettype none

/* universal asynchronous receiver/transmitter (UART) receiver */
/******************************************************************************************/
module uart_rx #(
    parameter  CLK_FREQ_MHZ     = 0             , // clock frequency [MHz]
    parameter  BAUD_RATE        = 0             , // baud rate [bps]
    parameter  DETECT_COUNT     = 0             , // detect count + 1 (start bit detect)
    localparam WAIT_COUNT       = (CLK_FREQ_MHZ*1000*1000)/BAUD_RATE // wait count
) (
    input  wire                  clk_i          , // clock
    input  wire                  rst_i          , // reset
    input  wire                  rxd_i          , // receive data (uart pin)
    output wire                  rvalid_o       , // receive data valid
    input  wire                  rready_i       , // receive data ready
    output wire            [7:0] rdata_o          // receive data
);

    // DRC: design rule check
    initial begin
        if (CLK_FREQ_MHZ==0) $fatal(1, "specify a uart_rx CLK_FREQ_MHZ");
        if (BAUD_RATE   ==0) $fatal(1, "specify a uart_rx BAUD_RATE");
        if (DETECT_COUNT==0) $fatal(1, "specify a uart_rx DETECT_COUNT (>0)");
    end

    // 2-FF synchronizer
    wire rxd;
    synchronizer sync_rxd (
        .clk_i   (clk_i     ),
        .d_i     (rxd_i     ),
        .q_o     (rxd       )
    );

    // FSM
    localparam IDLE = 1'b0, RUN = 1'b1;
    reg  [0:0] state_q  , state_d   ;

    reg  [$clog2(DETECT_COUNT+1)-1:0] detect_cntr_q , detect_cntr_d ;
    reg                               rvalid_q      , rvalid_d      ;
    reg                         [7:0] rx_data_q     , rx_data_d     ;
    reg                         [7:0] buf_q         , buf_d         ;
    reg                         [3:0] bit_cntr_q    , bit_cntr_d    ;
    reg      [$clog2(WAIT_COUNT)-1:0] wait_cntr_q   , wait_cntr_d   ;

    assign rvalid_o = rvalid_q  ;
    assign rdata_o  = rx_data_q ;

    always @(*) begin
        detect_cntr_d   = (rxd) ? 'h0 : detect_cntr_q+'h1;
        rvalid_d        = rvalid_q          ;
        rx_data_d       = rx_data_q         ;
        buf_d           = buf_q             ;
        bit_cntr_d      = bit_cntr_q        ;
        wait_cntr_d     = wait_cntr_q-'h1   ;
        state_d         = state_q           ;
        if (rvalid_o && rready_i) begin
            rvalid_d = 1'b0;
        end
        case (state_q)
            IDLE    : begin
                if (detect_cntr_q>=DETECT_COUNT-1) begin
                    bit_cntr_d      = 4'd9                          ;
                    wait_cntr_d     = WAIT_COUNT-DETECT_COUNT-'h3   ;
                    state_d         = RUN                           ;
                end
            end
            RUN     : begin
                if (wait_cntr_q==(WAIT_COUNT/2)) begin
                    if (~|bit_cntr_q) begin // bit_cntr_q==0
                        rvalid_d    = 1'b1                          ;
                        rx_data_d   = buf_q                         ;
                        state_d     = IDLE                          ;
                    end
                    buf_d           = {rxd, buf_q[7:1]}             ;
                    bit_cntr_d      = bit_cntr_q-4'd1               ;
                end
                if (~|wait_cntr_q) begin // wait_cntr_q==0
                    wait_cntr_d     = WAIT_COUNT-'h1                ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            detect_cntr_q   <= 'h0          ;
            rvalid_q        <= 1'b0         ;
            state_q         <= IDLE         ;
        end else begin
            detect_cntr_q   <= detect_cntr_d;
            rvalid_q        <= rvalid_d     ;
            rx_data_q       <= rx_data_d    ;
            buf_q           <= buf_d        ;
            bit_cntr_q      <= bit_cntr_d   ;
            wait_cntr_q     <= wait_cntr_d  ;
            state_q         <= state_d      ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
