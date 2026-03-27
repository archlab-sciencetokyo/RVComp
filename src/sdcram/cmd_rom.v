/*
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2021 takuto kanamori
 * Copyright (c) 2026 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

/* command ROM */
/******************************************************************************************/
module cmd_rom(
    input  wire [ 5:0] cmd_no,
    input  wire [31:0] arg,
    output reg  [47:0] cmd_dat,
    output reg  [ 7:0] rsp_bit,
    output reg         rsp_bsy
);

    always @(*) begin
        case (cmd_no)
            6'd00  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd00, 32'h00_00_00_00}, 8'd000, 1'b0};
            6'd02  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd02, 32'h00_00_00_00}, 8'd135, 1'b0};
            6'd03  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd03, 32'h00_00_00_00}, 8'd047, 1'b0};
            6'd06  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd06, 32'h00_00_00_02}, 8'd047, 1'b0};
            6'd07  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd07, arg            }, 8'd047, 1'b1};
            6'd08  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd08, 32'h00_00_01_AA}, 8'd047, 1'b0};
            6'd12  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd12, 32'h00_00_00_00}, 8'd047, 1'b0};
            6'd17  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd17, arg            }, 8'd047, 1'b0};
            6'd18  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd18, arg            }, 8'd047, 1'b0};
            6'd24  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd24, arg            }, 8'd047, 1'b0};
            6'd25  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd25, arg            }, 8'd047, 1'b0};
            6'd41  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd41, 32'h50_FF_80_00}, 8'd047, 1'b0};
            6'd55  : {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b01, 6'd55, arg            }, 8'd047, 1'b0};
            default: {cmd_dat, rsp_bit, rsp_bsy} = {{8'hFF, 2'b11, 6'd63, 32'hFF_FF_FF_FF}, 8'd000, 1'b0};
        endcase
    end

endmodule
/******************************************************************************************/

`resetall
