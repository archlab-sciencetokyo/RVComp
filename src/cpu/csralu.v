/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* control status register arithmetic logic unit */
/******************************************************************************************/
module csralu (
    input  wire [`CSR_CTRL_WIDTH-1:0] csr_ctrl_i    , // csr control
    input  wire           [`XLEN-1:0] src1_i        , // rs1 value
    input  wire           [`XLEN-1:0] src2_i        , // rs2 value
    output wire           [`XLEN-1:0] rslt_o          // result of csralu
);

    wire [`XLEN-1:0] csrrw_rslt = (csr_ctrl_i[`CSR_CTRL_IS_WRITE]) ?  src1_i          : 0;
    wire [`XLEN-1:0] csrrs_rslt = (csr_ctrl_i[`CSR_CTRL_IS_SET])   ?  src1_i | src2_i : 0;
    wire [`XLEN-1:0] csrrc_rslt = (csr_ctrl_i[`CSR_CTRL_IS_CLEAR]) ? ~src1_i & src2_i : 0;

    assign rslt_o   = csrrw_rslt | csrrs_rslt | csrrc_rslt  ;

endmodule
/******************************************************************************************/

`resetall
