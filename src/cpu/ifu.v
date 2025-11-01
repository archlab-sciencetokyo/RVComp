/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"
/* instruction fetch unit */
/******************************************************************************************/
module ifu #(
    parameter  CACHE_SIZE           = 0                                                         ,
    localparam DATA_WIDTH           = 32                                                        ,
    localparam BLOCK_WIDTH          = 128                                                       ,
    localparam BYTE_OFFSET_WIDTH    = $clog2(DATA_WIDTH/8)                                      ,
    localparam BLOCK_OFFSET_WIDTH   = $clog2(BLOCK_WIDTH/DATA_WIDTH)                            ,
    localparam INDEX_WIDTH          = $clog2(CACHE_SIZE)-(BLOCK_OFFSET_WIDTH+BYTE_OFFSET_WIDTH) ,
    localparam TAG_WIDTH            = `XLEN-(INDEX_WIDTH+BLOCK_OFFSET_WIDTH+BYTE_OFFSET_WIDTH)  ,
    localparam BYTE_OFFSET_LSB      = 0                                                         ,
    localparam BYTE_OFFSET_MSB      = BYTE_OFFSET_LSB+BYTE_OFFSET_WIDTH-1                       ,
    localparam BLOCK_OFFSET_LSB     = BYTE_OFFSET_MSB+1                                         ,
    localparam BLOCK_OFFSET_MSB     = BLOCK_OFFSET_LSB+BLOCK_OFFSET_WIDTH-1                     ,
    localparam INDEX_LSB            = BLOCK_OFFSET_MSB+1                                        ,
    localparam INDEX_MSB            = INDEX_LSB+INDEX_WIDTH-1                                   ,
    localparam TAG_LSB              = INDEX_MSB+1                                               ,
    localparam TAG_MSB              = TAG_LSB+TAG_WIDTH-1
) (
    input  wire                         clk_i               , // clock
    input  wire                         rst_i               , // reset
    input  wire                         flush_i             , // flush L0i$ 
    input  wire                         stall_i             , // stall ifu
    output wire                         stall_o             , // stall while executing
    input  wire                         ready_i             , // ready to accept fetch request
    output wire                         ready_o             , // ready of the fetch unit
    input  wire             [`XLEN-1:0] pc_i                , // program counter
    output wire                         ibus_arvalid_o      , // fetch request valid
    input  wire                         ibus_arready_i      , // fetch request ready
    output wire  [`IBUS_ADDR_WIDTH-1:0] ibus_araddr_o       , // fetch request address
    input  wire                         ibus_rvalid_i       , // fetch response valid
    output wire                         ibus_rready_o       , // fetch response ready
    input  wire  [`IBUS_DATA_WIDTH-1:0] ibus_rdata_i        , // fetch response data
    input  wire      [`RRESP_WIDTH-1:0] ibus_rresp_i        , // fetch response status
    output wire                  [31:0] ir_o                , // instruction
    output wire                         instr_page_fault_o  , // instruction page fault
    output wire                         instr_access_fault_o  // instruction access fault
);

    // DRC: design rule check
    initial begin
        if (CACHE_SIZE==0) $fatal(1, "specify a ifu CACHE_SIZE");
    end

    // L0 instruction cache
    reg     [2**INDEX_WIDTH-1:0] valid_ram                                      ;
    reg          [TAG_WIDTH-1:0] tag_ram   [0:2**INDEX_WIDTH-1]                 ;
    reg        [BLOCK_WIDTH-1:0] data_ram  [0:2**INDEX_WIDTH-1]                 ;

    wire             [`XLEN-1:0] raddr                                          ;
    wire       [INDEX_WIDTH-1:0] ridx                                           ;
    wire       [INDEX_WIDTH-1:0] widx                                           ;

    wire                         valid                                          ;
    wire         [TAG_WIDTH-1:0] tag                                            ;
    wire                         hit                                            ;
    reg              [`XLEN-1:0] pc_q                   , pc_d                  ;
    reg         [DATA_WIDTH-1:0] ir_q                   , ir_d                  ;

    // fetch unit
    localparam IDLE = 'd0, FETCH = 'd1, RET = 'd2   ;
    wire                         stall                                          ;
    reg                    [1:0] state_q                , state_d               ;
    reg                          stall_q                                        ;
    reg                          ibus_arvalid_q         , ibus_arvalid_d        ;
    reg   [`IBUS_ADDR_WIDTH-1:0] ibus_araddr_q          , ibus_araddr_d         ;
    reg                          page_fault_q           , page_fault_d          ;
    reg                          access_fault_q         , access_fault_d        ;
    reg                          instr_page_fault_q     , instr_page_fault_d    ;
    reg                          instr_access_fault_q   , instr_access_fault_d  ;
    
    assign stall                = (state_d!=IDLE)                               ;
    assign stall_o              = stall_q                                       ;
    assign ready_o              = (state_q!=FETCH || ibus_rvalid_i)             ;
    assign ibus_arvalid_o       = ibus_arvalid_q                                ;
    assign ibus_araddr_o        = ibus_araddr_q                                 ;
    assign ibus_rready_o        = (state_q==FETCH)                              ;
    assign ir_o                 = ir_q                                          ;
    assign instr_page_fault_o   = instr_page_fault_q                            ;
    assign instr_access_fault_o = instr_access_fault_q                          ;

    assign raddr            = (stall_i) ? pc_q : pc_i                           ;
    assign ridx             =         raddr[INDEX_MSB:INDEX_LSB]                ;
    assign widx             = ibus_araddr_q[INDEX_MSB:INDEX_LSB]                ;

    assign valid            = valid_ram[ridx]                                   ;
    assign tag              = tag_ram[ridx]                                     ;
    assign hit              = valid && (raddr[TAG_MSB:TAG_LSB]==tag) && !flush_i;

    always @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            valid_ram       <= 'h0  ;
        end else if (ibus_rvalid_i && ibus_rready_o && (ibus_rresp_i==`RRESP_OKAY)) begin
            valid_ram[widx] <= 1'b1 ;
        end
        if (ibus_rvalid_i && ibus_rready_o && (ibus_rresp_i==`RRESP_OKAY)) begin
            tag_ram[widx]   <= ibus_araddr_q[TAG_MSB:TAG_LSB]   ;
            data_ram[widx]  <= ibus_rdata_i                     ;
        end
    end

    always @(*) begin
        ibus_arvalid_d          = ibus_arvalid_q                    ;
        ibus_araddr_d           = ibus_araddr_q                     ;
        pc_d                    = pc_q                              ;
        ir_d                    = ir_q                              ;
        page_fault_d            = page_fault_q                      ;
        access_fault_d          = access_fault_q                    ;
        instr_page_fault_d      = 1'b0                              ;
        instr_access_fault_d    = 1'b0                              ;
        state_d                 = state_q                           ;
        case (state_q)
            IDLE    : begin
                if (!stall_i) begin
                    pc_d    = pc_i      ;
                    case (raddr[3:2])
                        'b11    : ir_d  = data_ram[ridx][127:96]    ;
                        'b10    : ir_d  = data_ram[ridx][ 95:64]    ;
                        'b01    : ir_d  = data_ram[ridx][ 63:32]    ;
                        default : ir_d  = data_ram[ridx][ 31: 0]    ;
                    endcase
                end
                ibus_araddr_d   = pc_i                              ;
                if (!hit) begin
                    ibus_arvalid_d  = 1'b1                              ;
                    state_d         = FETCH                             ;
                end
            end
            FETCH   : begin
                if (ibus_arready_i) begin
                    ibus_arvalid_d  = 1'b0                              ;
                end
                if (ibus_rvalid_i) begin
                    case (ibus_araddr_q[3:2])
                        'b11    : ir_d  = ibus_rdata_i[127:96]          ;
                        'b10    : ir_d  = ibus_rdata_i[ 95:64]          ;
                        'b01    : ir_d  = ibus_rdata_i[ 63:32]          ;
                        default : ir_d  = ibus_rdata_i[ 31: 0]          ;
                    endcase
                    page_fault_d    = (ibus_rresp_i==`RRESP_TRANSFAULT)                             ;
                    access_fault_d  = (ibus_rresp_i==`RRESP_DECERR) || (ibus_rresp_i==`RRESP_SLVERR);
                    if (ready_i) begin
                        instr_page_fault_d      = page_fault_d          ;
                        instr_access_fault_d    = access_fault_d        ;
                        state_d                 = IDLE                  ;
                    end else begin
                        state_d                 = RET                   ;
                    end
                end
            end
            RET     : begin
                if (ready_i) begin
                    instr_page_fault_d      = page_fault_q      ;
                    instr_access_fault_d    = access_fault_q    ;
                    state_d                 = IDLE              ;
                end
            end
            default : ;
        endcase
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            ibus_arvalid_q          <= 1'b0                 ;
            state_q                 <= IDLE                 ;
            stall_q                 <= 1'b0                 ;
        end else begin
            ibus_arvalid_q          <= ibus_arvalid_d       ;
            ibus_araddr_q           <= ibus_araddr_d        ;
            pc_q                    <= pc_d                 ;
            ir_q                    <= ir_d                 ;
            page_fault_q            <= page_fault_d         ;
            access_fault_q          <= access_fault_d       ;
            instr_page_fault_q      <= instr_page_fault_d   ;
            instr_access_fault_q    <= instr_access_fault_d ;
            state_q                 <= state_d              ;
            stall_q                 <= stall                ;
        end
    end
    
endmodule
/******************************************************************************************/

`resetall
