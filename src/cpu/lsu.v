/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* load/store unit */
/******************************************************************************************/
module lsu (
    input  wire                         clk_i          , // clock
    input  wire                         rst_i          , // reset
    input  wire                         valid_i        , // instruction valid
    output wire                         stall_o        , // stall while executing
    input  wire                         ready_i        , // ready to accept new instruction 
    output wire                         ready_o        , // ready of this module
    output wire                         exc_valid_o    , // exception valid
    output wire             [`XLEN-1:0] cause_o        , // exception cause
    output wire             [`XLEN-1:0] tval_o         , // exception address
    input  wire   [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_i     , // load store ctrl
    input  wire                   [5:0] awatop_i       , // amo operation
    input  wire             [`XLEN-1:0] src1_i         , // rs1 value
    input  wire             [`XLEN-1:0] src2_i         , // rs2 value
    input  wire             [`XLEN-1:0] imm_i          , // immediate value
    output wire  [`DBUS_ADDR_WIDTH-1:0] dbus_axaddr_o  , // load/store address
    output wire                         dbus_arvalid_o , // load request valid
    input  wire                         dbus_arready_i , // load request ready
    output wire                         dbus_arlock_o  , // load lock (lr)
    output wire                         dbus_aramo_o   , // AMO load request
    input  wire                         dbus_rvalid_i  , // load response valid
    output wire                         dbus_rready_o  , // load response ready 
    input  wire  [`DBUS_DATA_WIDTH-1:0] dbus_rdata_i   , // load response data
    input  wire      [`RRESP_WIDTH-1:0] dbus_rresp_i   , // load response status
    output wire                         dbus_wvalid_o  , // store request valid
    input  wire                         dbus_wready_i  , // store request ready
    output wire                         dbus_awlock_o  , // store lock (sc)
    output wire  [`DBUS_DATA_WIDTH-1:0] dbus_wdata_o   , // store request data
    output wire  [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_o   , // store request strobe
    input  wire                         dbus_bvalid_i  , // store response valid
    output wire                         dbus_bready_o  , // store response ready
    input  wire      [`BRESP_WIDTH-1:0] dbus_bresp_i   , // store response status
    output wire             [`XLEN-1:0] rslt_o           // result of lsu
);

    localparam IDLE='d0, LOAD='d1, STORE='d2, AMO='d3, RET='d4;
    wire                         stall                              ;
    reg                          stall_q                            ;
    reg                    [2:0] state_q        , state_d           ;

    reg                          exc_valid_q    , exc_valid_d       ;
    reg              [`XLEN-1:0] cause_q        , cause_d           ;
    reg              [`XLEN-1:0] tval_q         , tval_d            ;

    reg    [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_q     , lsu_ctrl_d        ;
    reg                    [5:0] awatop_q       , awatop_d          ;
    reg              [`XLEN-1:0] dbus_addr_q    , dbus_addr_d       ;
    reg                          dbus_arvalid_q , dbus_arvalid_d    ;
    reg              [`XLEN-1:0] dbus_rdata_q   , dbus_rdata_d      ;
    reg                          dbus_wvalid_q  , dbus_wvalid_d     ;
    reg              [`XLEN-1:0] dbus_wdata_q   , dbus_wdata_d      ;
    reg            [`XBYTES-1:0] dbus_wstrb_q   , dbus_wstrb_d      ;
    reg              [`XLEN-1:0] rslt_q         , rslt_d            ;

    assign stall    = (state_d!=IDLE);
    assign stall_o  = stall_q;
    assign ready_o  = (state_q==IDLE) || ((state_q==LOAD) && dbus_rvalid_i && !is_amoq) || 
                      ((state_q==STORE) && dbus_bvalid_i) || (state_q==RET);

    assign exc_valid_o      = exc_valid_q; // exception valid
    assign cause_o          = cause_q;     // exception cause
    assign tval_o           = tval_q;

    assign dbus_axaddr_o    = dbus_addr_q; // Note

    assign dbus_arvalid_o   = dbus_arvalid_q;
    assign dbus_arlock_o    = lsu_ctrl_q[`LSU_CTRL_IS_LRSC];
    assign dbus_aramo_o     = is_amoq       ;
    assign dbus_rready_o    = (state_q==LOAD);

    assign dbus_wvalid_o    = dbus_wvalid_q;
    assign dbus_awlock_o    = lsu_ctrl_q[`LSU_CTRL_IS_LRSC];
    //awatop_q;
    assign dbus_wdata_o     = dbus_wdata_q;
    assign dbus_wstrb_o     = dbus_wstrb_q;
    assign dbus_bready_o    = (state_q==STORE);

    assign rslt_o           = rslt_d;

    wire is_byte   = lsu_ctrl_i[`LSU_CTRL_IS_BYTE];     // set if byte access
    wire is_half   = lsu_ctrl_i[`LSU_CTRL_IS_HALFWORD]; // set if halfword access
    wire is_word   = lsu_ctrl_i[`LSU_CTRL_IS_WORD];     // set if word access
    wire is_load   = lsu_ctrl_i[`LSU_CTRL_IS_LOAD];
    wire is_store  = lsu_ctrl_i[`LSU_CTRL_IS_STORE];
    wire is_amo    = lsu_ctrl_i[`LSU_CTRL_IS_AMO];

    wire is_byteq = lsu_ctrl_q[`LSU_CTRL_IS_BYTE];
    wire is_halfq = lsu_ctrl_q[`LSU_CTRL_IS_HALFWORD];
    wire is_wordq = lsu_ctrl_q[`LSU_CTRL_IS_WORD];
    wire is_signq = lsu_ctrl_q[`LSU_CTRL_IS_SIGNED] | lsu_ctrl_q[`LSU_CTRL_IS_AMO];
    wire is_amoq   = lsu_ctrl_q[`LSU_CTRL_IS_AMO];
    wire is_mis_align = (is_half && dbus_addr[0]) || (is_word && |dbus_addr[1:0]);

    ///// address
    wire   [`XLEN-1:0] dbus_addr   = src1_i + imm_i;

    ///// store write data
    wire   [`XLEN-1:0] sb_data     = (is_byte) ? {`XBYTES  {src2_i[ 7:0]}} : 0;
    wire   [`XLEN-1:0] sh_data     = (is_half) ? {`XBYTES/2{src2_i[15:0]}} : 0;
    wire   [`XLEN-1:0] sw_data     = (is_word) ? {`XBYTES/4{src2_i[31:0]}} : 0;
    wire   [`XLEN-1:0] store_wdata = sb_data | sh_data | sw_data;

    ///// store write strobe
    wire [`XBYTES-1:0] sb_strb     = (is_byte) ? ('b0001 <<  dbus_addr[`DBUS_OFFSET_WIDTH-1:0]       ) : 0;
    wire [`XBYTES-1:0] sh_strb     = (is_half) ? ('b0011 << {dbus_addr[`DBUS_OFFSET_WIDTH-1:1], 1'b0}) : 0;
    wire [`XBYTES-1:0] sw_strb     = (is_word) ? ('b1111                                             ) : 0;
    wire [`XBYTES-1:0] store_wstrb = sb_strb | sh_strb | sw_strb;

    ///// load result
    wire        [31:0] lw_data_t   = dbus_rdata_i;
    wire        [15:0] lh_data_t   = (dbus_addr_q[1]) ? dbus_rdata_i[31:16] : dbus_rdata_i[15:0];
    wire         [7:0] lb_data_t   = (dbus_addr_q[1:0]==3) ? dbus_rdata_i[31:24] :
                                     (dbus_addr_q[1:0]==2) ? dbus_rdata_i[23:16] :
                                     (dbus_addr_q[1:0]==1) ? dbus_rdata_i[15: 8] : dbus_rdata_i[ 7: 0];
    wire   [`XLEN-1:0] lb_data     = (is_byteq) ? {{24{is_signq && lb_data_t[ 7]}}, lb_data_t} : 0;
    wire   [`XLEN-1:0] lh_data     = (is_halfq) ? {{16{is_signq && lh_data_t[15]}}, lh_data_t} : 0;
    wire   [`XLEN-1:0] lw_data     = (is_wordq) ?                                 lw_data_t  : 0;
    wire   [`XLEN-1:0] load_rslt   = lb_data | lh_data | lw_data;

    ///// amo
    wire [`AMO_CTRL_WIDTH-1:0] amo_ctrl  ;
    reg  [`AMO_CTRL_WIDTH-1:0] amo_ctrl_q;
    reg  [`XLEN-1:0]           amo_src1_q  , amo_src1_d  ;
    reg  [`XLEN-1:0]           amo_src2_q  , amo_src2_d  ;
    wire           [`XLEN-1:0] amo_rslt   ;

    amo_decoder amo_decoder (
        .awatop_i      (awatop_q      ),  // input  wire                 [5:0]
        .amo_ctrl_o    (amo_ctrl      )   // output reg  [`AMO_CTRL_WIDTH-1:0]
    );
    amoalu amoalu (
        .amo_ctrl_i    (amo_ctrl_q    ),  // input  wire [`AMO_CTRL_WIDTH-1:0]
        .src1_i        (amo_src1_q    ),  // input  wire [`XLEN-1:0] src1_i
        .src2_i        (amo_src2_q    ),  // input  wire [`XLEN-1:0] src2_i
        .rslt_o        (amo_rslt      )   // output wire [`XLEN-1:0] rslt_o
    );

    always @(*) begin
        exc_valid_d     = exc_valid_q       ;
        cause_d         = cause_q           ;
        tval_d          = tval_q            ;
        lsu_ctrl_d      = lsu_ctrl_q        ;
        awatop_d        = awatop_q          ;
        dbus_addr_d     = dbus_addr_q       ;
        dbus_arvalid_d  = dbus_arvalid_q    ;
        dbus_rdata_d    = dbus_rdata_q      ;
        dbus_wvalid_d   = dbus_wvalid_q     ;
        dbus_wdata_d    = dbus_wdata_q      ;
        dbus_wstrb_d    = dbus_wstrb_q      ;
        rslt_d          = rslt_q            ;
        state_d         = state_q           ;
        amo_src1_d      = amo_src1_q        ;
        amo_src2_d      = amo_src2_q        ;
        case (state_q)
            IDLE: begin
                exc_valid_d = 0;
                rslt_d      = 0;
                if (valid_i && is_mis_align) begin ///// alignment miss exception
                    exc_valid_d = 1; // exception valid
                    cause_d = (is_load) ? `CAUSE_LD_ADDR_MISALIGNED : `CAUSE_ST_ADDR_MISALIGNED;
                    tval_d  = dbus_addr;
                    state_d = RET;
                end
                if (valid_i && !is_mis_align) begin ///// load and store enable, no exception
                    lsu_ctrl_d    = lsu_ctrl_i;
                    awatop_d      = awatop_i;
                    dbus_addr_d   = dbus_addr;
                    if (is_amo || is_load) begin
                        dbus_arvalid_d  = 1  ;
                        state_d         = LOAD;
                    end else if (is_store) begin ///// store or amo instruction
                        dbus_wvalid_d = 1;
                        // dbus_wdata_d = (awatop_d==`AWATOP_CLR) ? ~store_wdata : store_wdata;
                        dbus_wdata_d = store_wdata;
                        dbus_wstrb_d = store_wstrb;
                        state_d = STORE;
                    end
                    if (is_amo) begin // amo src2
                        amo_src2_d      = (awatop_d==`AWATOP_CLR) ? ~store_wdata : store_wdata;
                    end
                end
            end
            LOAD: begin
                if (dbus_arready_i) dbus_arvalid_d = 0; // handshake
                if (dbus_rvalid_i) begin ///// load data is ready or exception
                    state_d = (ready_i) ? IDLE : RET;
                    if (dbus_rresp_i==`RRESP_TRANSFAULT || dbus_rresp_i==`RRESP_DECERR ||
                        dbus_rresp_i==`RRESP_SLVERR) begin
                        exc_valid_d = 1; // exception valid
                        tval_d  = dbus_addr_q;
                        cause_d = (dbus_rresp_i==`RRESP_TRANSFAULT) ?  ((is_amoq) ? `CAUSE_STORE_PAGE_FAULT :
                                                                                    `CAUSE_LOAD_PAGE_FAULT )
                                                                    :  `CAUSE_LD_ACCESS_FAULT;
                    end else if (is_amoq) begin
                        state_d = AMO;
                    end
                    amo_src1_d = lw_data_t ;
                    rslt_d  = load_rslt;
                end
            end
            STORE: begin
                if (dbus_wready_i) dbus_wvalid_d = 0; // handshake
                if (dbus_bvalid_i) begin
                    if (dbus_bresp_i==`BRESP_TRANSFAULT || dbus_bresp_i==`BRESP_DECERR ||
                        dbus_bresp_i==`BRESP_SLVERR) begin
                        exc_valid_d = 1; // exception valid
                        tval_d  = dbus_addr_q;
                        cause_d = (dbus_bresp_i==`BRESP_TRANSFAULT) ? `CAUSE_STORE_PAGE_FAULT :
                                                                      `CAUSE_ST_ACCESS_FAULT;
                    end
                    rslt_d = (is_amoq) ? rslt_q:
                             (dbus_bresp_i!=`BRESP_EXOKAY) ? 1 : 0;
                    state_d = (ready_i) ? IDLE : RET;
                end
            end
            AMO: begin
                dbus_wvalid_d = 1;
                dbus_wdata_d  = amo_rslt   ;
                dbus_wstrb_d  = 'b1111;
                state_d = STORE            ;
            end
            RET: begin
                if (ready_i) state_d = IDLE; // wait until ibus is ready
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            exc_valid_q     <= 0                ;
            dbus_arvalid_q  <= 0                ;
            dbus_wvalid_q   <= 0                ;
            state_q         <= IDLE             ;
            stall_q         <= 0                ;
        end else begin
            exc_valid_q     <= exc_valid_d      ;
            cause_q         <= cause_d          ;
            tval_q          <= tval_d           ;
            lsu_ctrl_q      <= lsu_ctrl_d       ;
            awatop_q        <= awatop_d         ;
            dbus_addr_q     <= dbus_addr_d      ;
            dbus_arvalid_q  <= dbus_arvalid_d   ;
            dbus_rdata_q    <= dbus_rdata_d     ;
            dbus_wvalid_q   <= dbus_wvalid_d    ;
            dbus_wdata_q    <= dbus_wdata_d     ;
            dbus_wstrb_q    <= dbus_wstrb_d     ;
            rslt_q          <= rslt_d           ;
            state_q         <= state_d          ;
            stall_q         <= stall            ;
            amo_ctrl_q      <= amo_ctrl         ;
            amo_src1_q      <= amo_src1_d       ;
            amo_src2_q      <= amo_src2_d       ;
        end
    end

endmodule
/******************************************************************************************/

`resetall
