/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "axi.vh"
`include "rvcom.vh"

/* central processing unit */
/******************************************************************************************/
module cpu #(
    parameter  HART_ID  = -1 // hart id
) (
    input  wire                         clk_i               , // clock
    input  wire                         rst_i               , // reset
    output wire                   [1:0] priv_lvl_o          , // privilege level
    output wire             [`XLEN-1:0] satp_o              , // satp register value
    output wire                         mxr_o               , // Make eXecutable Readable 
    output wire                         sum_o               , // permit Supervisor User Memory Access
    output wire                         mprv_o              , // Modify PRiVilege
    output wire                   [1:0] mpp_o               , // Machine Previous Privilege moode
    output wire                         flush_tlb_o         , // tlb flush
    input  wire                  [63:0] mtime_i             , // mtime register value
    input  wire                         timer_irq_i         , // timer interrupt request
    input  wire                         ipi_i               , // inter-processor interrupt
    input  wire                   [1:0] irq_i               , // external interrupt request
    output wire                         ibus_arvalid_o      , // fetch request valid
    input  wire                         ibus_arready_i      , // fetch request ready
    output wire  [`IBUS_ADDR_WIDTH-1:0] ibus_araddr_o       , // fetch request address
    input  wire                         ibus_rvalid_i       , // fetch response valid
    output wire                         ibus_rready_o       , // fetch response ready
    input  wire  [`IBUS_DATA_WIDTH-1:0] ibus_rdata_i        , // fetch response data
    input  wire      [`RRESP_WIDTH-1:0] ibus_rresp_i        , // fetch response status
    output wire  [`DBUS_ADDR_WIDTH-1:0] dbus_axaddr_o       , // load/store request address
    output wire                         dbus_wvalid_o       , // store request valid
    input  wire                         dbus_wready_i       , // store request ready
    output wire                         dbus_awlock_o       , // is store conditional
    output wire  [`DBUS_DATA_WIDTH-1:0] dbus_wdata_o        , // store request data
    output wire  [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_o        , // store request strobe
    input  wire                         dbus_bvalid_i       , // store response valid
    output wire                         dbus_bready_o       , // store response ready
    input  wire      [`BRESP_WIDTH-1:0] dbus_bresp_i        , // store response status
    output wire                         dbus_arvalid_o      , // load request valid
    input  wire                         dbus_arready_i      , // load request ready
    output wire                         dbus_arlock_o       , // is load reserved
    output wire                         dbus_aramo_o        , // is amo
    input  wire                         dbus_rvalid_i       , // load response valid
    output wire                         dbus_rready_o       , // load response ready
    input  wire  [`DBUS_DATA_WIDTH-1:0] dbus_rdata_i        , // load response data
    input  wire      [`RRESP_WIDTH-1:0] dbus_rresp_i          // load response status
);

    // DRC: design rule check
    initial begin
        if (HART_ID==-1) $fatal(1, "set the proper hard id");
    end

    // privilege level
    wire                  [1:0] priv_lvl                    ;

//==============================================================================
// pipeline registers
//------------------------------------------------------------------------------
    reg             [`XLEN-1:0] r_pc                        ;

    // ID: Instruction Decode
    reg                         IfId_v                      ;
    reg             [`XLEN-1:0] IfId_pc                     ;
    reg                   [1:0] IfId_pat_hist               ;
    reg                         IfId_br_pred_tkn            ;

    // OF: Operand Fetch
    reg                         IdOf_v                      ;
    reg             [`XLEN-1:0] IdOf_pc                     ;
    reg                  [31:0] IdOf_ir                     ;
    reg                         IdOf_exc_valid              ;
    reg             [`XLEN-1:0] IdOf_cause                  ;
    reg             [`XLEN-1:0] IdOf_tval                   ;
    reg                   [1:0] IdOf_pat_hist               ;
    reg                         IdOf_br_pred_tkn            ;
    reg                         IdOf_illegal_instr          ;
    reg  [`SRC1_CTRL_WIDTH-1:0] IdOf_src1_ctrl              ;
    reg  [`SRC2_CTRL_WIDTH-1:0] IdOf_src2_ctrl              ;
    reg   [`SYS_CTRL_WIDTH-1:0] IdOf_sys_ctrl               ;
    reg   [`CSR_CTRL_WIDTH-1:0] IdOf_csr_ctrl               ;
    reg   [`ALU_CTRL_WIDTH-1:0] IdOf_alu_ctrl               ;
    reg   [`BRU_CTRL_WIDTH-1:0] IdOf_bru_ctrl               ;
    reg   [`LSU_CTRL_WIDTH-1:0] IdOf_lsu_ctrl               ;
    reg                   [5:0] IdOf_awatop                 ;
    reg   [`MUL_CTRL_WIDTH-1:0] IdOf_mul_ctrl               ;
    reg   [`DIV_CTRL_WIDTH-1:0] IdOf_div_ctrl               ;
    reg                         IdOf_fencei                 ;
    reg                         IdOf_rf_we                  ;
    reg                   [4:0] IdOf_rd                     ;
    reg                   [4:0] IdOf_rs1                    ;
    reg                   [4:0] IdOf_rs2                    ;
    reg             [`XLEN-1:0] IdOf_imm                    ;
    reg                         IdOf_csr_rf_we              ;
    reg                  [11:0] IdOf_csr_addr               ;

    // EX: Execution
    reg                         OfEx_v                      ;
    reg             [`XLEN-1:0] OfEx_pc                     ;
    reg                  [31:0] OfEx_ir                     ;
    reg                         OfEx_exc_valid              ;
    reg             [`XLEN-1:0] OfEx_cause                  ;
    reg             [`XLEN-1:0] OfEx_tval                   ;
    reg                   [1:0] OfEx_pat_hist               ;
    reg                         OfEx_br_pred_tkn            ;
    reg   [`SYS_CTRL_WIDTH-1:0] OfEx_sys_ctrl               ;
    reg   [`CSR_CTRL_WIDTH-1:0] OfEx_csr_ctrl               ;
    reg   [`ALU_CTRL_WIDTH-1:0] OfEx_alu_ctrl               ;
    reg   [`BRU_CTRL_WIDTH-1:0] OfEx_bru_ctrl               ;
    reg   [`LSU_CTRL_WIDTH-1:0] OfEx_lsu_ctrl               ;
    reg                   [5:0] OfEx_awatop                 ;
    reg   [`MUL_CTRL_WIDTH-1:0] OfEx_mul_ctrl               ;
    reg   [`DIV_CTRL_WIDTH-1:0] OfEx_div_ctrl               ;
    reg                         OfEx_fencei                 ;
    reg                         OfEx_rf_we                  ;
    reg                   [4:0] OfEx_rd                     ;
    reg                         OfEx_rs1_fwd_from_Wb_to_Ex  ;
    reg                         OfEx_rs2_fwd_from_Wb_to_Ex  ;
    reg             [`XLEN-1:0] OfEx_src1                   ;
    reg             [`XLEN-1:0] OfEx_src2                   ;
    reg             [`XLEN-1:0] OfEx_imm                    ;
    reg                         OfEx_csr_replay             ;
    reg                         OfEx_csr_rf_we              ;
    reg                  [11:0] OfEx_csr_addr               ;
    reg             [`XLEN-1:0] OfEx_csr_rdata              ;

    // WB: Write Back
    reg                         ExWb_v                      ;
    reg             [`XLEN-1:0] ExWb_pc                     ;
    reg                  [31:0] ExWb_ir                     ;
    reg                         ExWb_exc_valid              ;
    reg             [`XLEN-1:0] ExWb_cause                  ;
    reg             [`XLEN-1:0] ExWb_tval                   ;
    reg                   [1:0] ExWb_pat_hist               ;
    reg                         ExWb_is_ctrl_tsfr           ;
    reg                         ExWb_br_tkn                 ;
    reg                         ExWb_br_misp_rslt1          ;
    reg                         ExWb_br_misp_rslt2          ;
    reg             [`XLEN-1:0] ExWb_br_tkn_pc              ;
    reg                         ExWb_br_misalign            ;
    reg   [`SYS_CTRL_WIDTH-1:0] ExWb_sys_ctrl               ;
    reg                         ExWb_fencei                 ;
    reg                         ExWb_rf_we                  ;
    reg                   [4:0] ExWb_rd                     ;
    reg             [`XLEN-1:0] ExWb_rslt                   ;
    reg                         ExWb_csr_replay             ;
    reg                         ExWb_csr_rf_we              ;
    reg                  [11:0] ExWb_csr_addr               ;
    reg             [`XLEN-1:0] ExWb_csr_rslt               ;

//==============================================================================
// pipeline control
//------------------------------------------------------------------------------
    // reset
    reg rst; always @(posedge clk_i) rst <= rst_i;

    // stall
    wire ifu_stall, lsu_stall, mul_stall, div_stall          ;
    wire ex_stall = lsu_stall || mul_stall || div_stall      ;
    wire stall    = ifu_stall || ex_stall                    ;

    // ready
    wire ibus_ready, dbus_ready, mul_ready, div_ready;

    // exceptions/interrupts
    reg              Wb_exc_valid       ;
    reg  [`XLEN-1:0] Wb_cause           ;
    reg  [`XLEN-1:0] Wb_tval            ;
    wire [`XLEN-1:0] trap_vector_base   ;

    // mret/sret
    wire             eret               ;
    wire [`XLEN-1:0] epc                ;

    // replay
    wire             Wb_csr_replay  = ExWb_v && ExWb_csr_replay                     ;

    // pipeline flush req
    wire             csr_flush                                                      ;
    wire             Wb_sfence_vma  = ExWb_v && ExWb_sys_ctrl[`SYS_CTRL_SFENCE_VMA] ;
    wire             Wb_fencei      = ExWb_v && ExWb_fencei                         ;

    // flush cache/tlb
    reg              flush_l0_icache_q  , flush_l0_icache_d ;
    reg              flush_tlb_q        , flush_tlb_d       ;

    assign flush_tlb_o      = flush_tlb_q       ;

    always @(*) begin
        flush_l0_icache_d   = 1'b0  ;
        flush_tlb_d         = 1'b0  ;
        if (!stall) begin
            if (csr_flush || Wb_fencei || Wb_sfence_vma) flush_l0_icache_d  = 1'b1  ;
            if (                          Wb_sfence_vma) flush_tlb_d        = 1'b1  ;
        end
    end

    always @(posedge clk_i) begin
        if (rst) begin
            flush_l0_icache_q   <= 1'b0                 ;
            flush_tlb_q         <= 1'b0                 ;
        end else begin
            flush_l0_icache_q   <= flush_l0_icache_d    ;
            flush_tlb_q         <= flush_tlb_d          ;
        end
    end

    // branch prediction
    wire             Wb_br_tkn      = ExWb_v && ExWb_br_tkn ;
    wire             Wb_br_misp     = ExWb_v && ExWb_is_ctrl_tsfr && ((Wb_br_tkn) ? ExWb_br_misp_rslt1 : ExWb_br_misp_rslt2);
    wire [`XLEN-1:0] Wb_br_true_pc  = (ExWb_br_tkn) ? ExWb_br_tkn_pc : ExWb_pc+'h4;

    wire If_v   = (Wb_exc_valid || eret || Wb_csr_replay || csr_flush || Wb_sfence_vma || Wb_fencei || Wb_br_misp) ? 1'b0 : 1'b1    ;
    wire Id_v   = (Wb_exc_valid || eret || Wb_csr_replay || csr_flush || Wb_sfence_vma || Wb_fencei || Wb_br_misp) ? 1'b0 : IfId_v  ;
    wire Of_v   = (Wb_exc_valid || eret || Wb_csr_replay || csr_flush || Wb_sfence_vma || Wb_fencei || Wb_br_misp) ? 1'b0 : IdOf_v  ;
    wire Ex_v   = (Wb_exc_valid || eret || Wb_csr_replay || csr_flush || Wb_sfence_vma || Wb_fencei || Wb_br_misp) ? 1'b0 : OfEx_v  ;
    wire Wb_v   = (Wb_exc_valid         || Wb_csr_replay                                                         ) ? 1'b0 : ExWb_v  ;

//==============================================================================
// IF: Instruction Fetch
//------------------------------------------------------------------------------
    wire [`XLEN-1:0] bpu_access_pc  ; // bpu: branch prediction unit
    wire       [1:0] If_pat_hist    ;
    wire             If_br_pred_tkn ;
    wire [`XLEN-1:0] If_br_pred_pc  ;
    assign bpu_access_pc =
        (Wb_br_misp               ) ?    Wb_br_true_pc :
        (If_br_pred_tkn           ) ?    If_br_pred_pc :
                                              r_pc+'h4 ;
    wire             ExWb_vtsfr   = ExWb_v && ExWb_is_ctrl_tsfr;
    bimodal bimodal (
        .clk_i                  (clk_i                                  ), // input  wire
        .rst_i                  (rst                                    ), // input  wire
        .stall_i                (stall                                  ), // input  wire
        .raddr_i                (bpu_access_pc                          ), // input  wire [`XLEN-1:0]
        .pat_hist_o             (  If_pat_hist                          ), // output reg        [1:0]
        .br_pred_tkn_o          (  If_br_pred_tkn                       ), // output wire
        .br_pred_pc_o           (  If_br_pred_pc                        ), // output reg  [`XLEN-1:0]
        .br_tkn_i               (  Wb_br_tkn                            ), // input  wire
        .br_vtsfr_i             (ExWb_vtsfr                             ), // input  wire
        .waddr_i                (ExWb_pc                                ), // input  wire [`XLEN-1:0]
        .pat_hist_i             (ExWb_pat_hist                          ), // input  wire       [1:0]
        .br_tkn_pc_i            (ExWb_br_tkn_pc                         )  // input  wire [`XLEN-1:0]
    );

    wire [`XLEN-1:0] pc             ;
    assign pc =
        (Wb_exc_valid                           ) ? trap_vector_base :
        (eret                                   ) ?              epc :
        (Wb_csr_replay                          ) ?      ExWb_pc     :
        (csr_flush || Wb_sfence_vma || Wb_fencei) ?      ExWb_pc+'h4 :
        (Wb_br_misp                             ) ?    Wb_br_true_pc :
        (If_br_pred_tkn                         ) ?    If_br_pred_pc :
                                                            r_pc+'h4 ;

    always @(posedge clk_i) begin
        if (rst) begin
            r_pc    <= `RESET_VECTOR    ;
        end else if (!stall) begin
            r_pc    <= pc               ;
        end
    end

    always @(posedge clk_i) begin
        if (rst) begin
            IfId_v                      <= 1'b0                         ;
            IfId_pc                     <= 'h0                          ;
        end else if (!stall) begin
            IfId_v                      <=   If_v                       ;
            IfId_pc                     <=    r_pc                      ;
            IfId_br_pred_tkn            <=   If_br_pred_tkn             ;
            IfId_pat_hist               <=   If_pat_hist                ;
        end
    end

    wire [31:0] Id_ir                   ;
    wire        Id_instr_page_fault     ;
    wire        Id_instr_access_fault   ;
    ifu #(
        .CACHE_SIZE             (`L0_ICACHE_SIZE                   )
    ) ifu (
        .clk_i                  (clk_i                                  ), // input  wire
        .rst_i                  (rst_i                                  ), // input  wire
        .flush_i                (flush_l0_icache_q                      ), // input  wire
        .stall_i                (ex_stall                               ), // input  wire
        .stall_o                (ifu_stall                              ), // output wire
        .ready_i                (dbus_ready && mul_ready && div_ready   ), // input  wire
        .ready_o                (ibus_ready                             ), // output wire
        .pc_i                   (r_pc                                   ), // input  wire             [`XLEN-1:0]
        .ibus_arvalid_o         (ibus_arvalid_o                         ), // output wire
        .ibus_arready_i         (ibus_arready_i                         ), // input  wire
        .ibus_araddr_o          (ibus_araddr_o                          ), // output wire  [`IBUS_ADDR_WIDTH-1:0]
        .ibus_rvalid_i          (ibus_rvalid_i                          ), // input  wire
        .ibus_rready_o          (ibus_rready_o                          ), // output wire
        .ibus_rdata_i           (ibus_rdata_i                           ), // input  wire  [`IBUS_DATA_WIDTH-1:0]
        .ibus_rresp_i           (ibus_rresp_i                           ), // input  wire      [`RRESP_WIDTH-1:0]
        .ir_o                   (  Id_ir                                ), // output wire                  [31:0]
        .instr_page_fault_o     (  Id_instr_page_fault                  ), // output wire
        .instr_access_fault_o   (  Id_instr_access_fault                )  // output wire
    );

//==============================================================================
// ID: Instruction Decode
//------------------------------------------------------------------------------
    // instruction decoder
    wire                         tsr                ; // trap sret
    wire                         tw                 ; // timeout wait
    wire                         tvm                ; // trap virtual memory
    wire                         Id_illegal_instr   ;
    wire [`INSTR_TYPE_WIDTH-1:0] Id_instr_type      ; // {J, U, B, S, I, R}
    wire  [`SRC1_CTRL_WIDTH-1:0] Id_src1_ctrl       ;
    wire  [`SRC2_CTRL_WIDTH-1:0] Id_src2_ctrl       ;
    wire   [`SYS_CTRL_WIDTH-1:0] Id_sys_ctrl        ;
    wire   [`CSR_CTRL_WIDTH-1:0] Id_csr_ctrl        ;
    wire   [`ALU_CTRL_WIDTH-1:0] Id_alu_ctrl        ;
    wire   [`BRU_CTRL_WIDTH-1:0] Id_bru_ctrl        ;
    wire   [`LSU_CTRL_WIDTH-1:0] Id_lsu_ctrl        ;
    wire                   [5:0] Id_awatop          ;
    wire   [`MUL_CTRL_WIDTH-1:0] Id_mul_ctrl        ;
    wire   [`DIV_CTRL_WIDTH-1:0] Id_div_ctrl        ;
    wire                         Id_fencei          ;
    wire                         Id_rf_we           ;
    wire                   [4:0] Id_rd              ;
    wire                   [4:0] Id_rs1             ;
    wire                   [4:0] Id_rs2             ;
    wire                         Id_csr_rf_we       ;
    wire                  [11:0] Id_csr_addr        ;
    decoder decoder (
        .ir_i                   (  Id_ir            ), // input  wire                  [31:0]
        .priv_lvl_i             (priv_lvl           ), // input  wire                   [1:0]
        .tsr_i                  (tsr                ), // input  wire
        .tw_i                   (tw                 ), // input  wire
        .tvm_i                  (tvm                ), // input  wire
        .illegal_instr_o        (  Id_illegal_instr ), // output wire
        .instr_type_o           (  Id_instr_type    ), // output wire [`INSTR_TYPE_WIDTH-1:0]
        .src1_ctrl_o            (  Id_src1_ctrl     ), // output wire  [`SRC1_CTRL_WIDTH-1:0]
        .src2_ctrl_o            (  Id_src2_ctrl     ), // output wire  [`SRC2_CTRL_WIDTH-1:0]
        .sys_ctrl_o             (  Id_sys_ctrl      ), // output wire   [`SYS_CTRL_WIDTH-1:0]
        .csr_ctrl_o             (  Id_csr_ctrl      ), // output wire   [`CSR_CTRL_WIDTH-1:0]
        .alu_ctrl_o             (  Id_alu_ctrl      ), // output wire   [`ALU_CTRL_WIDTH-1:0]
        .bru_ctrl_o             (  Id_bru_ctrl      ), // output wire   [`BRU_CTRL_WIDTH-1:0]
        .lsu_ctrl_o             (  Id_lsu_ctrl      ), // output wire   [`LSU_CTRL_WIDTH-1:0]
        .awatop_o               (  Id_awatop        ), // output wire                   [5:0]
        .mul_ctrl_o             (  Id_mul_ctrl      ), // output wire   [`MUL_CTRL_WIDTH-1:0]
        .div_ctrl_o             (  Id_div_ctrl      ), // output wire   [`DIV_CTRL_WIDTH-1:0]
        .fencei_o               (  Id_fencei        ), // output wire
        .rf_we_o                (  Id_rf_we         ), // output wire
        .rd_o                   (  Id_rd            ), // output wire                   [4:0]
        .rs1_o                  (  Id_rs1           ), // output wire                   [4:0]
        .rs2_o                  (  Id_rs2           ), // output wire                   [4:0]
        .csr_rf_we_o            (  Id_csr_rf_we     ), // output wire
        .csr_addr_o             (  Id_csr_addr      )  // output wire                  [11:0]
    );

    // immediate value generator
    wire [`XLEN-1:0] Id_imm ;
    imm_gen imm_gen (
        .ir_i                   (  Id_ir            ), // input  wire                  [31:0]
        .instr_type_i           (  Id_instr_type    ), // input  wire [`INSTR_TYPE_WIDTH-1;0]
        .imm_o                  (  Id_imm           )  // output wire             [`XLEN-1:0]
    );

    // exceptions
    reg             Id_exc_valid    ;
    reg [`XLEN-1:0] Id_cause        ;
    reg [`XLEN-1:0] Id_tval         ;
    always @(*) begin
        Id_exc_valid    = 1'b0                  ;
        Id_cause        = 'h0                   ;
        Id_tval         = 'h0                   ;
        if (Id_instr_access_fault) begin                            // instruction access fault
            Id_exc_valid    = 1'b1                                  ;
            Id_cause        = `CAUSE_INSTR_ACCESS_FAULT             ;
            Id_tval         = IfId_pc                               ;
        end
        if (Id_instr_page_fault) begin                              // instruction page fault
            Id_exc_valid    = 1'b1                                  ;
            Id_cause        = `CAUSE_INSTR_PAGE_FAULT               ;
            Id_tval         = IfId_pc                               ;
        end
    end

    always @(posedge clk_i) begin
        if (rst) begin
            IdOf_v                      <= 1'b0                         ;
            IdOf_pc                     <= 'h0                          ;
            IdOf_ir                     <= `NOP                         ;
        end else if (!stall) begin
            IdOf_v                      <=   Id_v                       ;
            IdOf_pc                     <= IfId_pc                      ;
            IdOf_ir                     <=   Id_ir                      ;
            IdOf_exc_valid              <=   Id_exc_valid               ;
            IdOf_cause                  <=   Id_cause                   ;
            IdOf_tval                   <=   Id_tval                    ;
            IdOf_br_pred_tkn            <= IfId_br_pred_tkn             ;
            IdOf_pat_hist               <= IfId_pat_hist                ;
            IdOf_illegal_instr          <=   Id_illegal_instr           ;
            IdOf_src1_ctrl              <=   Id_src1_ctrl               ;
            IdOf_src2_ctrl              <=   Id_src2_ctrl               ;
            IdOf_sys_ctrl               <=   Id_sys_ctrl                ;
            IdOf_csr_ctrl               <=   Id_csr_ctrl                ;
            IdOf_alu_ctrl               <=   Id_alu_ctrl                ;
            IdOf_bru_ctrl               <=   Id_bru_ctrl                ;
            IdOf_lsu_ctrl               <=   Id_lsu_ctrl                ;
            IdOf_awatop                 <=   Id_awatop                  ;
            IdOf_mul_ctrl               <=   Id_mul_ctrl                ;
            IdOf_div_ctrl               <=   Id_div_ctrl                ;
            IdOf_fencei                 <=   Id_fencei                  ;
            IdOf_rf_we                  <=   Id_rf_we                   ;
            IdOf_rd                     <=   Id_rd                      ;
            IdOf_rs1                    <=   Id_rs1                     ;
            IdOf_rs2                    <=   Id_rs2                     ;
            IdOf_imm                    <=   Id_imm                     ;
            IdOf_csr_rf_we              <=   Id_csr_rf_we               ;
            IdOf_csr_addr               <=   Id_csr_addr                ;
        end
    end

//==============================================================================
// OF: Operand Fetch
//------------------------------------------------------------------------------
    // register file
    wire [`XLEN-1:0] Of_xrs1, Of_xrs2;
    wire             Wb_rf_we   = Wb_v && ExWb_rf_we;
    wire [`XLEN-1:0] Wb_rslt;
    regfile regs (
        .clk_i                  (clk_i              ), // input  wire
        .stall_i                (stall              ), // input  wire
        .rs1_i                  (IdOf_rs1           ), // input  wire       [4:0]
        .rs2_i                  (IdOf_rs2           ), // input  wire       [4:0]
        .xrs1_o                 (  Of_xrs1          ), // output wire [`XLEN-1:0]
        .xrs2_o                 (  Of_xrs2          ), // output wire [`XLEN-1:0]
        .we_i                   (  Wb_rf_we         ), // input  wire
        .rd_i                   (ExWb_rd            ), // input  wire       [4:0]
        .wdata_i                (  Wb_rslt          )  // input  wire [`XLEN-1:0]
    );

    // control and status registers
    wire             Of_global_mie          ;
    wire             Of_global_sie          ;
    wire [`XLEN-1:0] Of_mie                 ;
    wire [`XLEN-1:0] Of_mip                 ;
    wire [`XLEN-1:0] Of_mideleg             ;
    wire [`XLEN-1:0] Of_csr_rdata           ;
    wire             Wb_csr_rf_we   = Wb_v && ExWb_csr_rf_we;
    wire             Of_illegal_csr_instr   ;
    csr_regfile #(
        .HART_ID                (HART_ID                )
    ) csrs (
        .clk_i                  (clk_i                  ), // input  wire
        .rst_i                  (rst                    ), // input  wire
        .priv_lvl_o             (priv_lvl               ), // output wire                 [1:0]
        .satp_o                 (satp_o                 ), // output wire
        .tsr_o                  (tsr                    ), // output wire
        .tw_o                   (tw                     ), // output wire
        .tvm_o                  (tvm                    ), // output wire
        .mxr_o                  (mxr_o                  ), // output wire
        .sum_o                  (sum_o                  ), // output wire
        .mprv_o                 (mprv_o                 ), // output wire                 [1:0]
        .mpp_o                  (mpp_o                  ), // output wire
        .trap_vector_base_o     (trap_vector_base       ), // output reg            [`XLEN-1:0]
        .eret_o                 (eret                   ), // output reg
        .epc_o                  (epc                    ), // output reg            [`XLEN-1:0]
        .mtime_i                (mtime_i                ), // input  wire                [63:0]
        .timer_irq_i            (timer_irq_i            ), // input  wire
        .ipi_i                  (ipi_i                  ), // input  wire
        .irq_i                  (irq_i                  ), // input  wire                 [1:0]
        .global_mie_o           (  Of_global_mie        ), // output wire
        .global_sie_o           (  Of_global_sie        ), // output wire
        .mie_o                  (  Of_mie               ), // output wire           [`XLEN-1:0]
        .mip_o                  (  Of_mip               ), // output wire           [`XLEN-1:0]
        .mideleg_o              (  Of_mideleg           ), // output wire           [`XLEN-1:0]
        .stall_i                (stall                  ), // input  wire
        .csr_ctrl_i             (IdOf_csr_ctrl          ), // input  wire [`CSR_CTRL_WIDTH-1:0]
        .csr_raddr_i            (IdOf_csr_addr          ), // input  wire                [11:0]
        .csr_rdata_o            (  Of_csr_rdata         ), // output wire           [`XLEN-1:0]
        .illegal_csr_instr_o    (  Of_illegal_csr_instr ), // output wire
        .csr_we_i               (  Wb_csr_rf_we         ), // input  wire
        .csr_waddr_i            (ExWb_csr_addr          ), // input  wire                [11:0]
        .csr_wdata_i            (ExWb_csr_rslt          ), // input  wire           [`XLEN-1:0]
        .valid_i                (  Wb_v                 ), // input  wire
        .exc_valid_i            (  Wb_exc_valid         ), // input  wire
        .sys_ctrl_i             (ExWb_sys_ctrl          ), // input  wire [`SYS_CTRL_WIDTH-1:0]
        .pc_i                   (ExWb_pc                ), // input  wire           [`XLEN-1:0]
        .cause_i                (  Wb_cause             ), // input  wire           [`XLEN-1:0]
        .tval_i                 (  Wb_tval              ), // input  wire           [`XLEN-1:0]
        .flush_o                (  csr_flush            )  // output reg
    );
    assign priv_lvl_o   = priv_lvl  ;

    // data forwarding
    wire Of_rs1_fwd_from_Wb_to_Ex = OfEx_v && OfEx_rf_we && (OfEx_rd==IdOf_rs1);
    wire Of_rs2_fwd_from_Wb_to_Ex = OfEx_v && OfEx_rf_we && (OfEx_rd==IdOf_rs2);
    wire Of_rs1_fwd_from_Wb_to_Of = ExWb_v && ExWb_rf_we && (ExWb_rd==IdOf_rs1);
    wire Of_rs2_fwd_from_Wb_to_Of = ExWb_v && ExWb_rf_we && (ExWb_rd==IdOf_rs2);

    // csr replay
    wire Of_csr_replay  = (OfEx_v && OfEx_csr_rf_we && (OfEx_csr_addr==IdOf_csr_addr)) || (ExWb_v && ExWb_csr_rf_we && (ExWb_csr_addr==IdOf_csr_addr));

    // source select
    wire [`XLEN-1:0] Of_uimm        = {{(`XLEN-5){1'b0}}, IdOf_rs1} ;
    wire [`XLEN-1:0] Of_src1        = (IdOf_src1_ctrl[`SRC1_CTRL_USE_UIMM] ) ?           Of_uimm      :
                                      (  Of_rs1_fwd_from_Wb_to_Of          ) ?           Wb_rslt      :
                                                                                         Of_xrs1      ;
    wire [`XLEN-1:0] Of_src2        = (IdOf_src2_ctrl[`SRC2_CTRL_USE_AUIPC]) ? IdOf_pc+IdOf_imm       :
                                      (IdOf_src2_ctrl[`SRC2_CTRL_USE_IMM]  ) ?         IdOf_imm       :
                                      (  Of_rs2_fwd_from_Wb_to_Of          ) ?           Wb_rslt      :
                                                                                         Of_xrs2      ;

    // exceptions/interrupts
    reg             Of_exc_valid    ;
    reg [`XLEN-1:0] Of_cause        ;
    reg [`XLEN-1:0] Of_tval         ;
    reg [`XLEN-1:0] Of_int_cause    ;
    always @(*) begin
        Of_exc_valid    = IdOf_exc_valid        ;
        Of_cause        = IdOf_cause            ;
        Of_tval         = IdOf_tval             ;
        Of_int_cause    = 'h0                   ;

        if (!Of_exc_valid) begin
            // exceptions
            if (IdOf_sys_ctrl[`SYS_CTRL_EBREAK]) begin                  // environment break
                Of_exc_valid    = 1'b1                                  ;
                Of_cause        = `CAUSE_BREAKPOINT                     ;
                Of_tval         = IdOf_pc                               ;
            end
            if (IdOf_sys_ctrl[`SYS_CTRL_ECALL]) begin                   // environment call
                Of_exc_valid    = 1'b1                                  ;
                Of_cause        = `CAUSE_USER_ECALL + {30'h0, priv_lvl} ;
            end
            if (IdOf_illegal_instr || Of_illegal_csr_instr) begin       // illegal instruction
                Of_exc_valid    = 1'b1                                  ;
                Of_cause        = `CAUSE_ILLEGAL_INSTR                  ;
                Of_tval         = IdOf_ir                               ;
            end

            // interrupts
            if (Of_mie[`IRQ_S_TIMER] && Of_mip[`IRQ_S_TIMER]) begin     // supervisor timer interrupt
                Of_int_cause    = `CAUSE_S_TIMER                        ;
            end
            if (Of_mie[`IRQ_S_SOFT] && Of_mip[`IRQ_S_SOFT]) begin       // supervisor software interrupt
                Of_int_cause    = `CAUSE_S_SOFT                         ;
            end
            if (Of_mie[`IRQ_S_EXT] && Of_mip[`IRQ_S_EXT]) begin         // supervisor external interrupt
                Of_int_cause    = `CAUSE_S_EXT                          ;
            end

            if (Of_mie[`IRQ_M_TIMER] && Of_mip[`IRQ_M_TIMER]) begin     // machine timer interrupt
                Of_int_cause    = `CAUSE_M_TIMER                        ;
            end
            if (Of_mie[`IRQ_M_SOFT] && Of_mip[`IRQ_M_SOFT]) begin       // machine software interrupt
                Of_int_cause    = `CAUSE_M_SOFT                         ;
            end
            if (Of_mie[`IRQ_M_EXT] && Of_mip[`IRQ_M_EXT]) begin         // machine external interrupt
                Of_int_cause    = `CAUSE_M_EXT                          ;
            end

            if (Of_int_cause[`XLEN-1] && Of_global_mie) begin
                if (Of_mideleg[Of_int_cause[$clog2(`XLEN)-1:0]]) begin
                    if (Of_global_sie) begin
                        Of_exc_valid    = 1'b1                          ;
                        Of_cause        = Of_int_cause                  ;
                        Of_tval         = 'h0                           ;
                    end
                end else begin
                    Of_exc_valid        = 1'b1                          ;
                    Of_cause            = Of_int_cause                  ;
                    Of_tval             = 'h0                           ;
                end
            end

        end
    end

    always @(posedge clk_i) begin
        if (rst) begin
            OfEx_v                      <= 1'b0                         ;
            OfEx_pc                     <= 'h0                          ;
            OfEx_ir                     <= `NOP                         ;
        end else if (!stall) begin
            OfEx_v                      <=   Of_v                       ;
            OfEx_pc                     <= IdOf_pc                      ;
            OfEx_ir                     <= IdOf_ir                      ;
            OfEx_exc_valid              <=   Of_exc_valid               ;
            OfEx_cause                  <=   Of_cause                   ;
            OfEx_tval                   <=   Of_tval                    ;
            OfEx_br_pred_tkn            <= IdOf_br_pred_tkn             ;
            OfEx_pat_hist               <= IdOf_pat_hist                ;
            OfEx_sys_ctrl               <= IdOf_sys_ctrl                ;
            OfEx_csr_ctrl               <= IdOf_csr_ctrl                ;
            OfEx_alu_ctrl               <= IdOf_alu_ctrl                ;
            OfEx_bru_ctrl               <= IdOf_bru_ctrl                ;
            OfEx_lsu_ctrl               <= IdOf_lsu_ctrl                ;
            OfEx_awatop                 <= IdOf_awatop                  ;
            OfEx_mul_ctrl               <= IdOf_mul_ctrl                ;
            OfEx_div_ctrl               <= IdOf_div_ctrl                ;
            OfEx_fencei                 <= IdOf_fencei                  ;
            OfEx_rf_we                  <= IdOf_rf_we                   ;
            OfEx_rd                     <= IdOf_rd                      ;
            OfEx_rs1_fwd_from_Wb_to_Ex  <=   Of_rs1_fwd_from_Wb_to_Ex   ;
            OfEx_rs2_fwd_from_Wb_to_Ex  <=   Of_rs2_fwd_from_Wb_to_Ex   ;
            OfEx_src1                   <=   Of_src1                    ;
            OfEx_src2                   <=   Of_src2                    ;
            OfEx_imm                    <= IdOf_imm                     ;
            OfEx_csr_replay             <=   Of_csr_replay              ;
            OfEx_csr_rf_we              <= IdOf_csr_rf_we               ;
            OfEx_csr_addr               <= IdOf_csr_addr                ;
            OfEx_csr_rdata              <=   Of_csr_rdata               ;
        end
    end

//==============================================================================
// EX: Execution
//------------------------------------------------------------------------------
    // data forwarding
    wire [`XLEN-1:0] Ex_src1    = (OfEx_rs1_fwd_from_Wb_to_Ex) ? Wb_rslt : OfEx_src1;
    wire [`XLEN-1:0] Ex_src2    = (OfEx_rs2_fwd_from_Wb_to_Ex) ? Wb_rslt : OfEx_src2;

    // arithmetic logic unit
    wire [`XLEN-1:0] Ex_alu_rslt;
    alu alu (
        .alu_ctrl_i             (OfEx_alu_ctrl      ), // input  wire [`ALU_CTRL_WIDTH-1:0]
        .src1_i                 (  Ex_src1          ), // input  wire           [`XLEN-1:0]
        .src2_i                 (  Ex_src2          ), // input  wire           [`XLEN-1:0]
        .rslt_o                 (  Ex_alu_rslt      )  // output wire           [`XLEN-1:0]
    );

    // branch resolution unit
    wire             Ex_is_ctrl_tsfr    ;
    wire             Ex_br_tkn          ;
    wire             Ex_br_misp_rslt1   ;
    wire             Ex_br_misp_rslt2   ;
    wire [`XLEN-1:0] Ex_br_tkn_pc       ;
    wire [`XLEN-1:0] Ex_bru_rslt        ;
    bru bru (
        .bru_ctrl_i             (OfEx_bru_ctrl      ), // input  wire [`BRU_CTRL_WIDTH-1:0]
        .src1_i                 (  Ex_src1          ), // input  wire           [`XLEN-1:0]
        .src2_i                 (  Ex_src2          ), // input  wire           [`XLEN-1:0]
        .pc_i                   (OfEx_pc            ), // input  wire           [`XLEN-1:0]
        .imm_i                  (OfEx_imm           ), // input  wire           [`XLEN-1:0]
        .npc_i                  (IdOf_pc            ), // input  wire           [`XLEN-1:0]
        .br_pred_tkn_i          (OfEx_br_pred_tkn   ), // input  wire
        .is_ctrl_tsfr_o         (  Ex_is_ctrl_tsfr  ), // output wire
        .br_tkn_o               (  Ex_br_tkn        ), // output wire
        .br_misp_rslt1_o        (  Ex_br_misp_rslt1 ), // output wire
        .br_misp_rslt2_o        (  Ex_br_misp_rslt2 ), // output wire
        .br_tkn_pc_o            (  Ex_br_tkn_pc     ), // output wire           [`XLEN-1:0]
        .rslt_o                 (  Ex_bru_rslt      )  // output wire           [`XLEN-1:0]
    );

    // control and status register
    wire [`XLEN-1:0] Ex_csr_rslt    ;
    csralu csralu (
        .csr_ctrl_i             (OfEx_csr_ctrl      ), // input  wire [`CSR_CTRL_WIDTH-1:0]
        .src1_i                 (  Ex_src1          ), // input  wire           [`XLEN-1:0]
        .src2_i                 (OfEx_csr_rdata     ), // input  wire           [`XLEN-1:0]
        .rslt_o                 (  Ex_csr_rslt      )  // output wire           [`XLEN-1:0]
    );

    wire [`XLEN-1:0] Ex_rslt = Ex_alu_rslt | Ex_bru_rslt | OfEx_csr_rdata   ;
    wire             Ex_br_misalign = Ex_br_tkn_pc[1] && Ex_br_tkn          ;

    always @(posedge clk_i) begin
        if (rst) begin
            ExWb_v                      <= 1'b0                         ;
            ExWb_pc                     <= 'h0                          ;
            ExWb_ir                     <= `NOP                         ;
        end else if (!stall) begin
            ExWb_v                      <=   Ex_v                       ;
            ExWb_pc                     <= OfEx_pc                      ;
            ExWb_ir                     <= OfEx_ir                      ;
            ExWb_exc_valid              <= OfEx_exc_valid               ;
            ExWb_cause                  <= OfEx_cause                   ;
            ExWb_tval                   <= OfEx_tval                    ;
            ExWb_pat_hist               <= OfEx_pat_hist                ;
            ExWb_is_ctrl_tsfr           <=   Ex_is_ctrl_tsfr            ;
            ExWb_br_tkn                 <=   Ex_br_tkn                  ;
            ExWb_br_misp_rslt1          <=   Ex_br_misp_rslt1           ;
            ExWb_br_misp_rslt2          <=   Ex_br_misp_rslt2           ;
            ExWb_br_tkn_pc              <=   Ex_br_tkn_pc               ;
            ExWb_br_misalign            <=   Ex_br_misalign             ;
            ExWb_sys_ctrl               <= OfEx_sys_ctrl                ;
            ExWb_fencei                 <= OfEx_fencei                  ;
            ExWb_rf_we                  <= OfEx_rf_we                   ;
            ExWb_rd                     <= OfEx_rd                      ;
            ExWb_rslt                   <=   Ex_rslt                    ;
            ExWb_csr_replay             <= OfEx_csr_replay              ;
            ExWb_csr_rf_we              <= OfEx_csr_rf_we               ;
            ExWb_csr_addr               <= OfEx_csr_addr                ;
            ExWb_csr_rslt               <=   Ex_csr_rslt                ;
        end
    end

    wire Ex_cmd_valid = OfEx_v && !OfEx_exc_valid && !Wb_exc_valid && !eret && !Wb_csr_replay && !csr_flush && !Wb_sfence_vma && !Wb_fencei && !Wb_br_misp;

    // load/store unit
    wire             Ex_lsu_cmd_valid = Ex_cmd_valid && !ifu_stall && !mul_stall && !div_stall;
    wire             Wb_lsu_exc_valid   ;
    wire [`XLEN-1:0] Wb_lsu_cause       ;
    wire [`XLEN-1:0] Wb_lsu_tval        ;
    wire [`XLEN-1:0] Ex_lsu_rslt        ;
    lsu lsu (
        .clk_i                  (clk_i                                  ), // input  wire
        .rst_i                  (rst                                    ), // input  wire
        .valid_i                (  Ex_lsu_cmd_valid                     ), // input  wire
        .stall_o                (lsu_stall                              ), // output wire
        .ready_i                (ibus_ready && mul_ready && div_ready   ), // input  wire
        .ready_o                (dbus_ready                             ), // output wire
        .exc_valid_o            (  Wb_lsu_exc_valid                     ), // output wire
        .cause_o                (  Wb_lsu_cause                         ), // output wire             [`XLEN-1:0]
        .tval_o                 (  Wb_lsu_tval                          ), // output wire             [`XLEN-1:0]
        .lsu_ctrl_i             (OfEx_lsu_ctrl                          ), // input  wire   [`LSU_CTRL_WIDTH-1:0]
        .awatop_i               (OfEx_awatop                            ), // input  wire                   [5:0]
        .src1_i                 (  Ex_src1                              ), // input  wire             [`XLEN-1:0]
        .src2_i                 (  Ex_src2                              ), // input  wire             [`XLEN-1:0]
        .imm_i                  (OfEx_imm                               ), // input  wire             [`XLEN-1:0]
        .dbus_axaddr_o          (dbus_axaddr_o                          ), // output wire  [`DBUS_ADDR_WIDTH-1:0]
        .dbus_arvalid_o         (dbus_arvalid_o                         ), // output wire
        .dbus_arready_i         (dbus_arready_i                         ), // input  wire
        .dbus_arlock_o          (dbus_arlock_o                          ), // output wire
        .dbus_aramo_o           (dbus_aramo_o                           ), // output wire
        .dbus_rvalid_i          (dbus_rvalid_i                          ), // input  wire
        .dbus_rready_o          (dbus_rready_o                          ), // output wire
        .dbus_rdata_i           (dbus_rdata_i                           ), // input  wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_rresp_i           (dbus_rresp_i                           ), // input  wire      [`RRESP_WIDTH-1:0]
        .dbus_wvalid_o          (dbus_wvalid_o                          ), // output wire
        .dbus_wready_i          (dbus_wready_i                          ), // input  wire
        .dbus_awlock_o          (dbus_awlock_o                          ), // output wire
        .dbus_wdata_o           (dbus_wdata_o                           ), // output wire  [`DBUS_DATA_WIDTH-1:0]
        .dbus_wstrb_o           (dbus_wstrb_o                           ), // output wire  [`DBUS_STRB_WIDTH-1:0]
        .dbus_bvalid_i          (dbus_bvalid_i                          ), // input  wire
        .dbus_bready_o          (dbus_bready_o                          ), // output wire
        .dbus_bresp_i           (dbus_bresp_i                           ), // input  wire      [`BRESP_WIDTH-1:0]
        .rslt_o                 (  Ex_lsu_rslt                          )  // output wire             [`XLEN-1:0]
    );

    // multiplier unit
    wire             Ex_mul_cmd_valid = Ex_cmd_valid && !ifu_stall && !lsu_stall && !div_stall; 
    wire [`XLEN-1:0] Ex_mul_rslt;
    multiplier multiplier (
        .clk_i                  (clk_i                                  ), // input  wire
        .rst_i                  (rst                                    ), // input  wire
        .valid_i                (  Ex_mul_cmd_valid                     ), // input  wire
        .stall_o                (mul_stall                              ), // output wire
        .ready_i                (ibus_ready && dbus_ready && div_ready  ), // input  wire
        .ready_o                (mul_ready                              ), // output wire
        .mul_ctrl_i             (OfEx_mul_ctrl                          ), // input  wire [`MUL_CTRL_WIDTH-1:0]
        .src1_i                 (  Ex_src1                              ), // input  wire           [`XLEN-1:0]
        .src2_i                 (  Ex_src2                              ), // input  wire           [`XLEN-1:0]
        .rslt_o                 (  Ex_mul_rslt                          )  // output wire           [`XLEN-1:0]
    );

    // divider unit
    wire             Ex_div_cmd_valid = Ex_cmd_valid && !ifu_stall && !lsu_stall && !mul_stall;
    wire [`XLEN-1:0] Ex_div_rslt;
    divider divider (
        .clk_i                  (clk_i                                  ), // input  wire
        .rst_i                  (rst                                    ), // input  wire
        .valid_i                (  Ex_div_cmd_valid                     ), // input  wire
        .stall_o                (div_stall                              ), // output wire
        .ready_i                (ibus_ready && dbus_ready && mul_ready  ), // input  wire
        .ready_o                (div_ready                              ), // output wire
        .div_ctrl_i             (OfEx_div_ctrl                          ), // input  wire [`DIV_CTRL_WIDTH-1:0]
        .src1_i                 (  Ex_src1                              ), // input  wire           [`XLEN-1:0]
        .src2_i                 (  Ex_src2                              ), // input  wire           [`XLEN-1:0]
        .rslt_o                 (  Ex_div_rslt                          )  // output wire           [`XLEN-1:0]
    );

//==============================================================================
// WB: Write Back
//------------------------------------------------------------------------------
    reg [31:0] ExWb_lsu_mul_div_rslt = 0;
    always @(posedge clk_i) begin
        if (ex_stall) begin
            ExWb_lsu_mul_div_rslt <= Ex_lsu_rslt | Ex_mul_rslt | Ex_div_rslt;
        end else if (!ifu_stall) begin
            ExWb_lsu_mul_div_rslt <= 0;
        end
    end
    assign Wb_rslt = ExWb_rslt | ExWb_lsu_mul_div_rslt;

    // synchronous exceptions
    always @(*) begin
        Wb_exc_valid    = ExWb_v && ExWb_exc_valid  ;
        Wb_cause        = ExWb_cause                ;
        Wb_tval         = ExWb_tval                 ;
        if (ExWb_v && !ExWb_exc_valid) begin
            if (Wb_lsu_exc_valid) begin                             // load/store/amo address misaligned or page fault
                Wb_exc_valid    = 1'b1                              ;
                Wb_cause        = Wb_lsu_cause                      ;
                Wb_tval         = Wb_lsu_tval                       ;
            end
            if (ExWb_br_misalign) begin             // instruction address misaligned
                Wb_exc_valid    = 1'b1                              ;
                Wb_cause        = `CAUSE_INSTR_ADDR_MISALIGNED      ;
                Wb_tval         = ExWb_br_tkn_pc                    ;
            end
        end
    end

endmodule
/******************************************************************************************/

`resetall
