/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* control status register file */
/******************************************************************************************/
module csr_regfile #(
    parameter  HART_ID  = -1
) (
    input  wire                       clk_i                 , // clock
    input  wire                       rst_i                 , // reset
    output wire                 [1:0] priv_lvl_o            , // privilege level
    output wire           [`XLEN-1:0] satp_o                , // Supervisor Address Translation and Protection
    output wire                       tsr_o                 , // Trap SRet
    output wire                       tw_o                  , // Timeout Wait
    output wire                       tvm_o                 , // Trap Virtual Memory
    output wire                       mxr_o                 , // Make eXecutable Readable
    output wire                       sum_o                 , // permit Supervisor User Memory access
    output wire                       mprv_o                , // Modify PRiVilege
    output wire                 [1:0] mpp_o                 , // Machine Previous Privilege mode
    output reg            [`XLEN-1:0] trap_vector_base_o    , // trap vector base
    output reg                        eret_o                , // is eret
    output reg            [`XLEN-1:0] epc_o                 , // Exception Program Counter
    input  wire                [63:0] mtime_i               , // from clint mtimer device 
    input  wire                       timer_irq_i           , // from clint mtimer device (timer interrupt request)
    input  wire                       ipi_i                 , // from clint mswi device (inter-processor interrupt)
    input  wire                 [1:0] irq_i                 , // from plic (interrupt request)
    output wire                       global_mie_o          , // global machine interrupt enable
    output wire                       global_sie_o          , // global supervisor interrupt enable
    output wire           [`XLEN-1:0] mie_o                 , // machine interrupt enable
    output wire           [`XLEN-1:0] mip_o                 , // machine interrupt pending
    output wire           [`XLEN-1:0] mideleg_o             , // machine interrupt delegation
    input  wire                       stall_i               , // stall while executing
    input  wire [`CSR_CTRL_WIDTH-1:0] csr_ctrl_i            , // csr control
    input  wire                [11:0] csr_raddr_i           , // csr read reeust address
    output wire           [`XLEN-1:0] csr_rdata_o           , // csr read response data
    output wire                       illegal_csr_instr_o   , // illegal csr instruction
    input  wire                       csr_we_i              , // csr write enable
    input  wire                [11:0] csr_waddr_i           , // csr write request address
    input  wire           [`XLEN-1:0] csr_wdata_i           , // csr write request data
    input  wire                       valid_i               , // valid instruction 
    input  wire                       exc_valid_i           , // exception valid
    input  wire [`SYS_CTRL_WIDTH-1:0] sys_ctrl_i            , // system control
    input  wire           [`XLEN-1:0] pc_i                  , // program counter
    input  wire           [`XLEN-1:0] cause_i               , // exception cause
    input  wire           [`XLEN-1:0] tval_i                , // bad address of instruction
    output reg                        flush_o                 // flush pipeline
);

    // DRC: design rule check
    initial begin
        if (HART_ID==-1) $fatal(1, "set the proper hard id");
    end

    // CSRs: control and status registers
    reg       [1:0] priv_lvl_q          , priv_lvl_d            ;

    // supervisor trap setup
    reg [`XLEN-1:0] stvec_q             , stvec_d               ;
    reg       [2:0] scounteren_q        , scounteren_d          ;

    // supervisor trap handling
    reg [`XLEN-1:0] sscratch_q          , sscratch_d            ;
    reg [`XLEN-1:0] sepc_q              , sepc_d                ;
    reg [`XLEN-1:0] scause_q            , scause_d              ;
    reg [`XLEN-1:0] stval_q             , stval_d               ;

    // supervisor protection and translation
    reg [`XLEN-1:0] satp_q              , satp_d                ;

    // machine trap setup
    reg      [63:0] mstatus_q           , mstatus_d             ;
    reg [`XLEN-1:0] misa_q                                      ;
    reg      [63:0] medeleg_q           , medeleg_d             ;
    reg [`XLEN-1:0] mideleg_q           , mideleg_d             ;
    reg [`XLEN-1:0] mie_q               , mie_d                 ;
    reg [`XLEN-1:0] mtvec_q             , mtvec_d               ;
    reg       [2:0] mcounteren_q        , mcounteren_d          ;

    // machine trap handling
    reg [`XLEN-1:0] mscratch_q          , mscratch_d            ;
    reg [`XLEN-1:0] mepc_q              , mepc_d                ;
    reg [`XLEN-1:0] mcause_q            , mcause_d              ;
    reg [`XLEN-1:0] mtval_q             , mtval_d               ;
    reg [`XLEN-1:0] mip_q               , mip_d                 ;

    // machine counter/timers
    reg      [63:0] mcycle_q            , mcycle_d              ;
    reg      [63:0] minstret_q          , minstret_d            ;

    // machine counter setup
    reg       [2:0] mcountinhibit_q     , mcountinhibit_d       ; // {minstret, 0, mcycle}

    // assignments
    assign priv_lvl_o       = priv_lvl_q                ;
    assign satp_o           = satp_q                    ; // Supervisor Address Translation and Protection
    assign tsr_o            = mstatus_q[`MSTATUS_TSR]   ; // Trap SRet
    assign tw_o             = mstatus_q[`MSTATUS_TW]    ; // Timeout Wait
    assign tvm_o            = mstatus_q[`MSTATUS_TVM]   ; // Trap Virtual Memory
    assign mxr_o            = mstatus_q[`MSTATUS_MXR]   ; // Make eXecutable Readable
    assign sum_o            = mstatus_q[`MSTATUS_SUM]   ; // permit Supervisor User Memory access
    assign mprv_o           = mstatus_q[`MSTATUS_MPRV]  ; // Modify PRiVilege
    assign mpp_o            = mstatus_q[`MSTATUS_MPP]   ; // Machine Previous Privilege mode
    assign global_mie_o     = ((priv_lvl_q==`PRIV_LVL_M) && mstatus_q[`MSTATUS_MIE]) || (priv_lvl_q<`PRIV_LVL_M);
    assign global_sie_o     = ((priv_lvl_q==`PRIV_LVL_S) && mstatus_q[`MSTATUS_SIE]) || (priv_lvl_q<`PRIV_LVL_S);
    assign mie_o            = mie_q                     ;
    assign mip_o            = mip_q                     ;
    assign mideleg_o        = mideleg_q                 ;

    // read CSRs
    reg [`XLEN-1:0] csr_rdata       ;
    reg             csr_access_exc  ;
    always @(*) begin
        csr_rdata       = 'h0   ;
        csr_access_exc  = 1'b0  ;
        if (csr_ctrl_i[`CSR_CTRL_IS_CSR]) begin
            case (csr_raddr_i[9:8]) // privilege level
                2'b00   : begin // user level
                    case (csr_raddr_i[11:10]) // read/write accessibility
                        2'b11   : begin // read-only
                            if (!csr_ctrl_i[`CSR_CTRL_IS_READ]) csr_access_exc  = 1'b1  ;
                            case (csr_raddr_i[7:0])
                                8'h00   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[0]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[0] && scounteren_q[0]))) csr_access_exc = 1'b1  ; else csr_rdata   = mcycle_q[`XLEN-1:0]   ; end // cycle
                                8'h01   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[1]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[1] && scounteren_q[1]))) csr_access_exc = 1'b1  ; else csr_rdata   = mtime_i[`XLEN-1:0]    ; end // time
                                8'h02   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[2]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[2] && scounteren_q[2]))) csr_access_exc = 1'b1  ; else csr_rdata   = minstret_q[`XLEN-1:0] ; end // instret
                                8'h80   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[0]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[0] && scounteren_q[0]))) csr_access_exc = 1'b1  ; else csr_rdata   = mcycle_q[63:32]       ; end // cycleh, RV32 only
                                8'h81   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[1]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[1] && scounteren_q[1]))) csr_access_exc = 1'b1  ; else csr_rdata   = mtime_i[63:32]        ; end // timeh, RV32 only
                                8'h82   : begin if (((priv_lvl_q==`PRIV_LVL_S) && !mcounteren_q[2]) || ((priv_lvl_q==`PRIV_LVL_U) && !(mcounteren_q[2] && scounteren_q[2]))) csr_access_exc = 1'b1  ; else csr_rdata   = minstret_q[63:32]     ; end // instreth, RV32 only
                                default : csr_access_exc    = 1'b1                                      ;
                            endcase
                        end
                        default : csr_access_exc    = 1'b1  ;
                    endcase
                end
                2'b01   : begin // supervisor level
                    if (priv_lvl_q<`PRIV_LVL_S) csr_access_exc  = 1'b1  ;
                    case (csr_raddr_i[11:10]) // read/write accessibility
                        2'b00   : begin // read/write
                            case (csr_raddr_i[7:0])
                                8'h00   : csr_rdata         = mstatus_q[`XLEN-1:0] & `SSTATUS_READ_MASK     ; // sstatus
                                8'h04   : csr_rdata         = mie_q & mideleg_q                             ; // sie
                                8'h05   : csr_rdata         = stvec_q                                       ;
                                8'h06   : csr_rdata         = {{(`XLEN-3){1'b0}}, scounteren_q}             ;
                                8'h40   : csr_rdata         = sscratch_q                                    ;
                                8'h41   : csr_rdata         = sepc_q                                        ;
                                8'h42   : csr_rdata         = scause_q                                      ;
                                8'h43   : csr_rdata         = stval_q                                       ;
                                8'h44   : csr_rdata         = (mip_q | (irq_i[1] << `IRQ_S_EXT)) & mideleg_q; // sip
                                8'h80   : begin
                                    if ((priv_lvl_q==`PRIV_LVL_S) && mstatus_q[`MSTATUS_TVM]) csr_access_exc = 1'b1 ;
                                    else  csr_rdata         = satp_q                                        ;
                                end
                                default : csr_access_exc    = 1'b1                                          ;
                            endcase
                        end
                        default : csr_access_exc    = 1'b1  ;
                    endcase
                end
                2'b11   : begin // machine level
                    if (priv_lvl_q<`PRIV_LVL_M) csr_access_exc  = 1'b1  ;
                    case (csr_raddr_i[11:10]) // read/write accessibility
                        2'b00   : begin // read/write
                            case (csr_raddr_i[7:0])
                                8'h00   : csr_rdata         = mstatus_q[`XLEN-1:0]                  ;
                                8'h01   : csr_rdata         = misa_q                                ;
                                8'h02   : csr_rdata         = medeleg_q[`XLEN-1:0]                  ;
                                8'h03   : csr_rdata         = mideleg_q                             ;
                                8'h04   : csr_rdata         = mie_q                                 ;
                                8'h05   : csr_rdata         = mtvec_q                               ;
                                8'h06   : csr_rdata         = {{(`XLEN-3){1'b0}}, mcounteren_q}     ;
                                8'h10   : csr_rdata         = mstatus_q[63:32]                      ; // mstatush, RV32 only
                                8'h12   : csr_rdata         = medeleg_q[63:32]                      ; // medelegh, RV32 only
                                8'h40   : csr_rdata         = mscratch_q                            ;
                                8'h41   : csr_rdata         = mepc_q                                ;
                                8'h42   : csr_rdata         = mcause_q                              ;
                                8'h43   : csr_rdata         = mtval_q                               ;
                                8'h44   : csr_rdata         = mip_q | (irq_i[1] << `IRQ_S_EXT)      ;
                                8'h20   : csr_rdata         = {{(`XLEN-3){1'b0}}, mcountinhibit_q}  ;
                                default : csr_access_exc    = 1'b1                                  ;
                            endcase
                        end
                        2'b01   : begin // read/write
                            case (csr_raddr_i[7:0])
                                8'hA0   : csr_rdata         = 'h1                                   ; // tselect, FIXME: This is not correct implementation.
                                default : csr_access_exc    = 1'b1                                  ;
                            endcase
                        end
                        2'b10   : begin // read/write
                            case (csr_raddr_i[7:0])
                                8'h00   : csr_rdata         = mcycle_q[`XLEN-1:0]                   ; // mcycle
                                8'h02   : csr_rdata         = minstret_q[`XLEN-1:0]                 ; // minstret
                                8'h80   : csr_rdata         = mcycle_q[63:32]                       ; // mcycleh, RV32 only
                                8'h82   : csr_rdata         = minstret_q[63:32]                     ; // minstreth, RV32 only
                                default : csr_access_exc    = 1'b1                                  ;
                            endcase
                        end
                        2'b11   : begin // read-only
                            if (!csr_ctrl_i[`CSR_CTRL_IS_READ]) csr_access_exc  = 1'b1  ;
                            case (csr_raddr_i[7:0])
                                8'h11   : csr_rdata         = 'h0                                   ; // mvendorid
                                8'h12   : csr_rdata         = 'h0                                   ; // marchid
                                8'h13   : csr_rdata         = 'h0                                   ; // mimpid
                                8'h14   : csr_rdata         = HART_ID                               ; // mhartid
                                default : csr_access_exc    = 1'b1                                  ;
                            endcase
                        end
                        default : csr_access_exc    = 1'b1  ;
                    endcase
                end
                default : csr_access_exc    = 1'b1  ;
            endcase
        end
    end
    assign csr_rdata_o          = csr_rdata     ;
    assign illegal_csr_instr_o  = csr_access_exc;

    // write CSRs
    reg             deleg                                           ;
    wire            mret    = valid_i && sys_ctrl_i[`SYS_CTRL_MRET] ;
    wire            sret    = valid_i && sys_ctrl_i[`SYS_CTRL_SRET] ;
    reg [`XLEN-1:0] mask                                            ;

    always @(*) begin

        priv_lvl_d      = priv_lvl_q        ;
        stvec_d         = stvec_q           ;
        scounteren_d    = scounteren_q      ;
        sscratch_d      = sscratch_q        ;
        sepc_d          = sepc_q            ;
        scause_d        = scause_q          ;
        stval_d         = stval_q           ;
        satp_d          = satp_q            ;
        mstatus_d       = mstatus_q         ;
        medeleg_d       = medeleg_q         ;
        mideleg_d       = mideleg_q         ;
        mie_d           = mie_q             ;
        mtvec_d         = mtvec_q           ;
        mcounteren_d    = mcounteren_q      ;
        mscratch_d      = mscratch_q        ;
        mepc_d          = mepc_q            ;
        mcause_d        = mcause_q          ;
        mtval_d         = mtval_q           ;
        mip_d           = mip_q             ;
        mcycle_d        = mcycle_q          ;
        if (!mcountinhibit_q[0]) begin
            mcycle_d        = mcycle_q+'h1      ;
        end
        minstret_d      = minstret_q        ;
        if (valid_i && !exc_valid_i && !mcountinhibit_q[2]) begin
            minstret_d      = minstret_q+'h1    ;
        end
        mcountinhibit_d = mcountinhibit_q   ;
        flush_o         = 1'b0              ;
        mask            = 'h0               ;

        if (csr_we_i) begin
            case (csr_waddr_i)
                12'h100: begin
                    mask                        = `SSTATUS_WRITE_MASK                                   ;
                    mstatus_d[`XLEN-1:0]        = (mstatus_q[`XLEN-1:0] & ~mask) | (csr_wdata_i & mask) ; // sstatus
                    flush_o                     = 1'b1                                                  ;
                end
                12'h104: begin
                    mask                        = mideleg_q                                             ;
                    mie_d                       = (mie_q     & ~mask) | (csr_wdata_i & mask)            ; // sie
                end
                12'h105: stvec_d                = {csr_wdata_i[`XLEN-1:2], 2'b00}                       ;
                12'h106: scounteren_d           = csr_wdata_i[2:0]                                      ;
                12'h140: sscratch_d             = csr_wdata_i                                           ;
                12'h141: sepc_d                 = {csr_wdata_i[`XLEN-1:2], 2'b00}                       ;
                12'h142: scause_d               = csr_wdata_i                                           ;
                12'h143: stval_d                = csr_wdata_i                                           ;
                12'h144: begin
                    mask                        = mideleg_q  & `MIP_SSIP_MASK                           ;
                    mip_d                       = (mip_q     & ~mask) | (csr_wdata_i & mask)            ; // sip
                end
                12'h180: begin
                    satp_d                      = csr_wdata_i                                           ;
                    satp_d[`SATP_ASID]          = {{`ASIDMAX{1'b0}}}                                    ;
                    flush_o                     = 1'b1                                                  ;
                end
                12'h300: begin
                    mask                        = `MSTATUS_WRITE_MASK                                   ;
                    mstatus_d[`XLEN-1:0]        = (mstatus_q[`XLEN-1:0] & ~mask) | (csr_wdata_i & mask) ;
                    if (mstatus_q[`MSTATUS_MDT]) begin
                        mstatus_d[`MSTATUS_MIE] = 1'b0                                                  ;
                    end
                    flush_o                     = 1'b1                                                  ;
                end
                12'h302: begin
                    mask                        = `MEDELEG_WRITE_MASK                                   ;
                    medeleg_d[`XLEN-1:0]        = (medeleg_q[`XLEN-1:0] & ~mask) | (csr_wdata_i & mask) ;
                end
                12'h303: begin
                    mask                        = `MIDELEG_WRITE_MASK                                   ;
                    mideleg_d                   = (mideleg_q & ~mask) | (csr_wdata_i & mask)            ;
                end
                12'h304: begin
                    mask                        = `MIE_WRITE_MASK                                       ;
                    mie_d                       = (mie_q     & ~mask) | (csr_wdata_i & mask)            ;
                end
                12'h305: mtvec_d                = {csr_wdata_i[`XLEN-1:2], 2'b00}                       ;
                12'h306: mcounteren_d           = csr_wdata_i[2:0]                                      ;
                12'h310: begin
                    mask                        = `MSTATUSH_WRITE_MASK                                  ;
                    mstatus_d[63:32]            = (mstatus_q[63:32] & ~mask) | (csr_wdata_i & mask)     ; // mstatush, RV32 only
                    if (mstatus_d[`MSTATUS_MDT]) begin
                        mstatus_d[`MSTATUS_MIE] = 1'b0                                                  ;
                    end
                    flush_o                     = 1'b1                                                  ;
                end
                12'h312: medeleg_d[63:32]       = csr_wdata_i                                           ; // medelegh, RV32 only
                12'h340: mscratch_d             = csr_wdata_i                                           ;
                12'h341: mepc_d                 = {csr_wdata_i[`XLEN-1:2], 2'b00}                       ;
                12'h342: mcause_d               = csr_wdata_i                                           ;
                12'h343: mtval_d                = csr_wdata_i                                           ;
                12'h344: begin
                    mask                        = `MIP_WRITE_MASK                                       ;
                    mip_d                       = (mip_q     & ~mask) | (csr_wdata_i & mask)            ;
                end
                12'hb00: mcycle_d[`XLEN-1:0]    = csr_wdata_i                                           ;
                12'hb02: minstret_d[`XLEN-1:0]  = csr_wdata_i                                           ;
                12'hb80: mcycle_d[63:32]        = csr_wdata_i                                           ; // mcycleh, RV32 only
                12'hb82: minstret_d[63:32]      = csr_wdata_i                                           ; // minstreth, RV32 only
                12'h320: mcountinhibit_d        = {csr_wdata_i[2], 1'b0, csr_wdata_i[0]}                ;
                default:                                                                                ;
            endcase
        end

        // exceptions/interrupts
        mip_d[`MIP_MTIP]    = timer_irq_i   ;
        mip_d[`MIP_MSIP]    = ipi_i         ;
        mip_d[`MIP_MEIP]    = irq_i[0]      ;
        mip_d[`MIP_SEIP]    = irq_i[1]      ;
        deleg               = 1'b0          ;
        if (exc_valid_i) begin
            if (priv_lvl_q<=`PRIV_LVL_S) begin
                if (cause_i[`XLEN-1]) begin                                 // interrupts
                    if (mideleg_q[cause_i[$clog2(`XLEN)-1:0]]) begin
                        deleg                   = 1'b1                      ;
                    end
                end else begin                                              // exceptions
                    if (medeleg_q[cause_i[$clog2(`XLEN)-1:0]]) begin
                        deleg                   = 1'b1                      ;
                    end
                end
            end
            if (deleg) begin                                            // trap to supervisor mode
                mstatus_d[`MSTATUS_SIE]     = 1'b0                      ;
                mstatus_d[`MSTATUS_SPIE]    = mstatus_q[`MSTATUS_SIE]   ;
                mstatus_d[`MSTATUS_SPP]     = priv_lvl_q[0]             ;
                scause_d                    = cause_i                   ;
                sepc_d                      = {pc_i[`XLEN-1:2], 2'b00}  ;
                stval_d                     = tval_i                    ;
                priv_lvl_d                  = `PRIV_LVL_S               ;
            end else begin                                              // trap to machine mode
                mstatus_d[`MSTATUS_MIE]     = 1'b0                      ;
                mstatus_d[`MSTATUS_MPIE]    = mstatus_q[`MSTATUS_MIE]   ;
                mstatus_d[`MSTATUS_MPP]     = priv_lvl_q                ;
                mcause_d                    = cause_i                   ;
                mepc_d                      = {pc_i[`XLEN-1:2], 2'b00}  ;
                mtval_d                     = tval_i                    ;
                priv_lvl_d                  = `PRIV_LVL_M               ;
                mstatus_d[`MSTATUS_MDT]     = 1'b1                      ;
            end
        end

        // mret/sret
        eret_o                      = 1'b0                              ;
        // mret
        if (mret) begin
            eret_o                      = 1'b1                              ;
            mstatus_d[`MSTATUS_MIE]     = mstatus_q[`MSTATUS_MPIE]          ;
            priv_lvl_d                  = mstatus_q[`MSTATUS_MPP]           ;
            mstatus_d[`MSTATUS_MPP]     = `PRIV_LVL_U                       ;
            mstatus_d[`MSTATUS_MPIE]    = 1'b1                              ;
            if (mstatus_q[`MSTATUS_MPP]<`PRIV_LVL_M) begin
                mstatus_d[`MSTATUS_MPRV]    = 1'b0                              ;
            end
            mstatus_d[`MSTATUS_MDT]     = 1'b0                              ;
        end
        // sret
        if (sret) begin
            eret_o                      = 1'b1                              ;
            mstatus_d[`MSTATUS_SIE]     = mstatus_q[`MSTATUS_SPIE]          ;
            priv_lvl_d                  = {1'b0, mstatus_q[`MSTATUS_SPP]}   ;
            mstatus_d[`MSTATUS_SPP]     = 1'b0                              ; // set spp to user mode
            mstatus_d[`MSTATUS_SPIE]    = 1'b1                              ;
            mstatus_d[`MSTATUS_MPRV]    = 1'b0                              ;
            if (priv_lvl_q==`PRIV_LVL_M) begin
                mstatus_d[`MSTATUS_MDT]     = 1'b0                              ;
            end
        end

        // trap vector
        trap_vector_base_o  = {mtvec_q[`XLEN-1:2], 2'b00}   ;
        if (deleg) begin
            trap_vector_base_o  = {stvec_q[`XLEN-1:2], 2'b00}   ;
        end
        // exception pc
        epc_o               = {mepc_q[`XLEN-1:2], 2'b00}    ;
        if (sret) begin
            epc_o               = {sepc_q[`XLEN-1:2], 2'b00}    ;
        end

    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            priv_lvl_q      <= `PRIV_LVL_M      ;
            mcycle_q        <= 64'h0            ;
            minstret_q      <= 64'h0            ;
            stvec_q         <= 'h0              ;
            scounteren_q    <= 'h0              ;
            sscratch_q      <= 'h0              ;
            sepc_q          <= 'h0              ;
            scause_q        <= 'h0              ;
            stval_q         <= 'h0              ;
            satp_q          <= 'h0              ;
            mstatus_q       <= 64'h40000000000  ; // Upon reset, the M-mode-disable-trap (MDT) field is set to 1.
            misa_q          <= `ISA_CODE        ;
            medeleg_q       <= 64'h0            ;
            mideleg_q       <= 'h0              ;
            mie_q           <= 'h0              ;
            mtvec_q         <= `RESET_VECTOR    ;
            mcounteren_q    <= 'h0              ;
            mscratch_q      <= 'h0              ;
            mepc_q          <= 'h0              ;
            mcause_q        <= 'h0              ;
            mtval_q         <= 'h0              ;
            mip_q           <= 'h0              ;
            mcountinhibit_q <= 'h0              ;
        end else if (!stall_i) begin
            priv_lvl_q      <= priv_lvl_d       ;
            mcycle_q        <= mcycle_d         ;
            minstret_q      <= minstret_d       ;
            stvec_q         <= stvec_d          ;
            scounteren_q    <= scounteren_d     ;
            sscratch_q      <= sscratch_d       ;
            sepc_q          <= sepc_d           ;
            scause_q        <= scause_d         ;
            stval_q         <= stval_d          ;
            satp_q          <= satp_d           ;
            mstatus_q       <= mstatus_d        ;
            medeleg_q       <= medeleg_d        ;
            mideleg_q       <= mideleg_d        ;
            mie_q           <= mie_d            ;
            mtvec_q         <= mtvec_d          ;
            mcounteren_q    <= mcounteren_d     ;
            mscratch_q      <= mscratch_d       ;
            mepc_q          <= mepc_d           ;
            mcause_q        <= mcause_d         ;
            mtval_q         <= mtval_d          ;
            mip_q           <= mip_d            ;
            mcountinhibit_q <= mcountinhibit_d  ;
        end
    end
endmodule
/******************************************************************************************/

`resetall
