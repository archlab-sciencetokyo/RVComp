/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* CRC7 */
/******************************************************************************************/
module sdcram_crc_7(
   input  wire       DAT,
   input  wire       EN,
   input  wire       CLK,
   input  wire       RST,
   output wire [6:0] CRC
);

    reg [6:0] crc_q, crc_d;
    wire inv = DAT ^ crc_q[6];

    assign CRC = crc_q;

    always @(*) begin
        crc_d = crc_q;
        if (RST) begin
            crc_d = 7'd0;
        end else if (EN) begin
            crc_d[6] = crc_q[5];
            crc_d[5] = crc_q[4];
            crc_d[4] = crc_q[3];
            crc_d[3] = crc_q[2] ^ inv;
            crc_d[2] = crc_q[1];
            crc_d[1] = crc_q[0];
            crc_d[0] = inv;
        end
    end

    always @(posedge CLK) begin
        crc_q <= crc_d;
    end

endmodule
/******************************************************************************************/

`resetall
