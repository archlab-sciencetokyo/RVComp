/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* CRC16 */
/******************************************************************************************/
module sdcram_crc_16(
    input  wire        DAT,
    input  wire        EN,
    input  wire        CLK,
    input  wire        RST,
    output wire [15:0] CRC
);

    reg [15:0] crc_q, crc_d;
    wire inv = DAT ^ crc_q[15];

    assign CRC = crc_q;

    always @(*) begin
        crc_d = crc_q;
        if (RST) begin
            crc_d = 16'd0;
        end else if (EN) begin
            crc_d[15] = crc_q[14];
            crc_d[14] = crc_q[13];
            crc_d[13] = crc_q[12];
            crc_d[12] = crc_q[11] ^ inv;
            crc_d[11] = crc_q[10];
            crc_d[10] = crc_q[9];
            crc_d[9]  = crc_q[8];
            crc_d[8]  = crc_q[7];
            crc_d[7]  = crc_q[6];
            crc_d[6]  = crc_q[5];
            crc_d[5]  = crc_q[4] ^ inv;
            crc_d[4]  = crc_q[3];
            crc_d[3]  = crc_q[2];
            crc_d[2]  = crc_q[1];
            crc_d[1]  = crc_q[0];
            crc_d[0]  = inv;
        end
    end

    always @(posedge CLK) begin
        crc_q <= crc_d;
    end

endmodule
/******************************************************************************************/

`resetall
