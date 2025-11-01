/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */
 
`ifndef AXI_VH_
`define AXI_VH_

/* AXI response codes */
/******************************************************************************************/
// BRESP encodings
`define BRESP_WIDTH                 3
`define BRESP_OKAY                  3'b000
`define BRESP_EXOKAY                3'b001
`define BRESP_SLVERR                3'b010
`define BRESP_DECERR                3'b011
`define BRESP_TRANSFAULT            3'b101
`define BRESP_UNSUPPORTED           3'b111

// RRESP encodings
`define RRESP_WIDTH                 3
`define RRESP_OKAY                  3'b000
`define RRESP_EXOKAY                3'b001
`define RRESP_SLVERR                3'b010
`define RRESP_DECERR                3'b011
`define RRESP_PREFETCHED            3'b100
`define RRESP_TRANSFAULT            3'b101
`define RRESP_OKAYDIRTY             3'b110

/******************************************************************************************/

`endif // AXI_VH_
