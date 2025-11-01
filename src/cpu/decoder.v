/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"
/* decoder */
/******************************************************************************************/
module decoder (
    input  wire                  [31:0] ir_i            , // instruction
    input  wire                   [1:0] priv_lvl_i      , // privilege level
    input  wire                         tsr_i           , // trap sret
    input  wire                         tw_i            , // timeout wait
    input  wire                         tvm_i           , // trap virtual memory
    output wire                         illegal_instr_o , // illegal instruction
    output wire [`INSTR_TYPE_WIDTH-1:0] instr_type_o    , // instruction type
    output wire  [`SRC1_CTRL_WIDTH-1:0] src1_ctrl_o     , // source 1 control (uimm)
    output wire  [`SRC2_CTRL_WIDTH-1:0] src2_ctrl_o     , // source 2 control (imm, auipc)
    output wire   [`SYS_CTRL_WIDTH-1:0] sys_ctrl_o      , // system control
    output wire   [`CSR_CTRL_WIDTH-1:0] csr_ctrl_o      , // CSR control
    output wire   [`ALU_CTRL_WIDTH-1:0] alu_ctrl_o      , // ALU control
    output wire   [`BRU_CTRL_WIDTH-1:0] bru_ctrl_o      , // BRU control
    output wire   [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_o      , // load/store control
    output wire                   [5:0] awatop_o        , // amo control
    output wire   [`MUL_CTRL_WIDTH-1:0] mul_ctrl_o      , // mul control
    output wire   [`DIV_CTRL_WIDTH-1:0] div_ctrl_o      , // div control
    output wire                         fencei_o        , // is fencei
    output wire                         rf_we_o         , // register file write enable
    output wire                   [4:0] rd_o            , // write register index
    output wire                   [4:0] rs1_o           , // rs1 index
    output wire                   [4:0] rs2_o           , // rs2 index
    output wire                         csr_rf_we_o     , // CSR register file write enable
    output wire                  [11:0] csr_addr_o        // CSR register address(read|write)
);

    wire [31:0] ir      = ir_i      ;
    wire  [6:0] opcode  = ir[ 6: 0] ;
    wire  [2:0] funct3  = ir[14:12] ;
    wire  [6:0] funct7  = ir[31:25] ;
    wire [11:0] funct12 = ir[31:20] ;

    reg                         illegal_instr   ;
    reg [`INSTR_TYPE_WIDTH-1:0] instr_type      ;
    reg  [`SRC1_CTRL_WIDTH-1:0] src1_ctrl       ;
    reg  [`SRC2_CTRL_WIDTH-1:0] src2_ctrl       ;
    reg   [`SYS_CTRL_WIDTH-1:0] sys_ctrl        ;
    reg   [`CSR_CTRL_WIDTH-1:0] csr_ctrl        ;
    reg   [`ALU_CTRL_WIDTH-1:0] alu_ctrl        ;
    reg   [`BRU_CTRL_WIDTH-1:0] bru_ctrl        ;
    reg   [`LSU_CTRL_WIDTH-1:0] lsu_ctrl        ;
    reg                   [5:0] awatop          ;
    reg   [`MUL_CTRL_WIDTH-1:0] mul_ctrl        ;
    reg   [`DIV_CTRL_WIDTH-1:0] div_ctrl        ;
    reg                         fencei          ;
    reg                   [4:0] rd              ;
    reg                   [4:0] rs1             ;
    reg                   [4:0] rs2             ;
    reg                         csr_rf_we       ;
    reg                  [11:0] csr_addr        ;

    always @(*) begin

        illegal_instr   = 1'b0                  ;
        instr_type      = `NONE_TYPE            ;
        src1_ctrl       = 'h0                   ;
        src2_ctrl       = 'h0                   ;
        sys_ctrl        = 'h0                   ;
        csr_ctrl        = 'h0                   ;
        alu_ctrl        = 'h0                   ;
        bru_ctrl        = 'h0                   ;
        lsu_ctrl        = 'h0                   ;
        awatop          = `AWATOP_NON_ATOMIC    ;
        mul_ctrl        = 'h0                   ;
        div_ctrl        = 'h0                   ;
        fencei          = 1'b0                  ;

        // control signal
        case (opcode[1:0])
            2'b00: illegal_instr    = 1'b1  ;
            2'b01: illegal_instr    = 1'b1  ;
            2'b10: illegal_instr    = 1'b1  ;
            2'b11: begin
                case (opcode[6:2])
                    5'b11100: begin // SYSTEM
                        instr_type                          = `I_TYPE   ;
                        csr_ctrl[`CSR_CTRL_IS_CSR]          = 1'b1      ;
                        case (funct3)
                            3'b000 : begin
                                csr_ctrl[`CSR_CTRL_IS_CSR]  = 1'b0      ;
                                if ({ir[19:15], ir[11:7]}!=10'b0000000000) illegal_instr    = 1'b1  ;
                                case (funct12)
                                    12'b000000000000: begin sys_ctrl[`SYS_CTRL_ECALL]   = 1'b1  ; end // ecall
                                    12'b000000000001: begin sys_ctrl[`SYS_CTRL_EBREAK]  = 1'b1  ; end // ebreak
                                    12'b000100000010: begin // sret
                                        if ((priv_lvl_i==`PRIV_LVL_U) || ((priv_lvl_i==`PRIV_LVL_S) && tsr_i)) illegal_instr    = 1'b1  ;
                                        else sys_ctrl[`SYS_CTRL_SRET]   = 1'b1  ;
                                    end
                                    12'b001100000010: begin // mret
                                        if (priv_lvl_i<`PRIV_LVL_M) illegal_instr   = 1'b1  ;
                                        else sys_ctrl[`SYS_CTRL_MRET]   = 1'b1  ;
                                    end
                                    12'b000100000101: begin // wfi
                                        if ((priv_lvl_i==`PRIV_LVL_U) || ((priv_lvl_i==`PRIV_LVL_S) && tw_i)) illegal_instr     = 1'b1  ;
                                        else sys_ctrl[`SYS_CTRL_WFI]    = 1'b1  ;
                                    end
                                    default         : begin
                                        if ((funct7==7'b0001001) && (ir[11:7]==5'b00000) && ((priv_lvl_i==`PRIV_LVL_M) || ((priv_lvl_i==`PRIV_LVL_S) && !tvm_i))) begin
                                            illegal_instr                   = 1'b0  ;
                                            sys_ctrl[`SYS_CTRL_SFENCE_VMA]  = 1'b1  ;
                                        end else begin
                                            illegal_instr   = 1'b1  ;
                                        end
                                    end
                                endcase
                            end
                            3'b001 : begin                                                                                                   csr_ctrl[`CSR_CTRL_IS_WRITE] = 1'b1; end // csrrw
                            3'b010 : begin                                        if (ir[19:15]==0) csr_ctrl[`CSR_CTRL_IS_READ] = 1'b1; else csr_ctrl[`CSR_CTRL_IS_SET]   = 1'b1; end // csrrs
                            3'b011 : begin                                        if (ir[19:15]==0) csr_ctrl[`CSR_CTRL_IS_READ] = 1'b1; else csr_ctrl[`CSR_CTRL_IS_CLEAR] = 1'b1; end // csrrc
                            3'b101 : begin src1_ctrl[`SRC1_CTRL_USE_UIMM] = 1'b1;                                                            csr_ctrl[`CSR_CTRL_IS_WRITE] = 1'b1; end // csrrwi
                            3'b110 : begin src1_ctrl[`SRC1_CTRL_USE_UIMM] = 1'b1; if (ir[19:15]==0) csr_ctrl[`CSR_CTRL_IS_READ] = 1'b1; else csr_ctrl[`CSR_CTRL_IS_SET]   = 1'b1; end // csrrsi
                            3'b111 : begin src1_ctrl[`SRC1_CTRL_USE_UIMM] = 1'b1; if (ir[19:15]==0) csr_ctrl[`CSR_CTRL_IS_READ] = 1'b1; else csr_ctrl[`CSR_CTRL_IS_CLEAR] = 1'b1; end // csrrci
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b00011: begin // MISC-MEM
                        case (funct3)
                            3'b000 :                                    ; // fence
                            3'b001 : fencei                 = 1'b1      ; // fence.i
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b01101: begin // LUI
                        instr_type                          = `U_TYPE   ;
                        src2_ctrl[`SRC2_CTRL_USE_IMM]       = 1'b1      ;
                        alu_ctrl[`ALU_CTRL_IS_SRC2]         = 1'b1      ;
                    end
                    5'b00101: begin // AUIPC
                        instr_type                          = `U_TYPE   ;
                        src2_ctrl[`SRC2_CTRL_USE_AUIPC]     = 1'b1      ;
                        alu_ctrl[`ALU_CTRL_IS_SRC2]         = 1'b1      ;
                    end
                    5'b11011: begin // JAL
                        instr_type                          = `J_TYPE   ;
                        bru_ctrl[`BRU_CTRL_IS_CTRL_TSFR]    = 1'b1      ;
                        bru_ctrl[`BRU_CTRL_IS_JAL_JALR]     = 1'b1      ;
                    end
                    5'b11001: begin // JALR
                        instr_type                          = `I_TYPE   ;
                        bru_ctrl[`BRU_CTRL_IS_CTRL_TSFR]    = 1'b1      ;
                        bru_ctrl[`BRU_CTRL_IS_JAL_JALR]     = 1'b1      ;
                        bru_ctrl[`BRU_CTRL_IS_JALR]         = 1'b1      ;
                    end
                    5'b11000: begin // BRANCH
                        instr_type                          = `B_TYPE   ;
                        bru_ctrl[`BRU_CTRL_IS_CTRL_TSFR]    = 1'b1      ;
                        case (funct3)
                            3'b000 : begin                                       bru_ctrl[`BRU_CTRL_IS_BEQ] = 1'b1; end // beq
                            3'b001 : begin                                       bru_ctrl[`BRU_CTRL_IS_BNE] = 1'b1; end // bne
                            3'b100 : begin bru_ctrl[`BRU_CTRL_IS_SIGNED] = 1'b1; bru_ctrl[`BRU_CTRL_IS_BLT] = 1'b1; end // blt
                            3'b101 : begin bru_ctrl[`BRU_CTRL_IS_SIGNED] = 1'b1; bru_ctrl[`BRU_CTRL_IS_BGE] = 1'b1; end // bge
                            3'b110 : begin                                       bru_ctrl[`BRU_CTRL_IS_BLT] = 1'b1; end // bltu
                            3'b111 : begin                                       bru_ctrl[`BRU_CTRL_IS_BGE] = 1'b1; end // bgeu
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b00000: begin // LOAD
                        instr_type                          = `I_TYPE   ;
                        lsu_ctrl[`LSU_CTRL_IS_LOAD]         = 1'b1      ;
                        case (funct3)
                            3'b000 : begin lsu_ctrl[`LSU_CTRL_IS_SIGNED] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_BYTE]     = 1'b1; end // lb
                            3'b001 : begin lsu_ctrl[`LSU_CTRL_IS_SIGNED] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_HALFWORD] = 1'b1; end // lh
                            3'b010 : begin lsu_ctrl[`LSU_CTRL_IS_SIGNED] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_WORD]     = 1'b1; end // lw
                            3'b100 : begin                                       lsu_ctrl[`LSU_CTRL_IS_BYTE]     = 1'b1; end // lbu
                            3'b101 : begin                                       lsu_ctrl[`LSU_CTRL_IS_HALFWORD] = 1'b1; end // lhu
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b01000: begin // STORE
                        instr_type                          = `S_TYPE   ;
                        lsu_ctrl[`LSU_CTRL_IS_STORE]        = 1'b1      ;
                        case (funct3)
                            3'b000 : lsu_ctrl[`LSU_CTRL_IS_BYTE]     = 1'b1; // sb
                            3'b001 : lsu_ctrl[`LSU_CTRL_IS_HALFWORD] = 1'b1; // sh
                            3'b010 : lsu_ctrl[`LSU_CTRL_IS_WORD]     = 1'b1; // sw
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b00100: begin // OP-IMM
                        instr_type                          = `I_TYPE   ;
                        src2_ctrl[`SRC2_CTRL_USE_IMM]       = 1'b1      ;
                        case (funct3)
                            3'b000 : begin                                                                             alu_ctrl[`ALU_CTRL_IS_ADD]    = 1'b1; end // addi
                            3'b010 : begin alu_ctrl[`ALU_CTRL_IS_SIGNED] = 1'b1; alu_ctrl[`ALU_CTRL_IS_NEG]    = 1'b1; alu_ctrl[`ALU_CTRL_IS_LESS]   = 1'b1; end // slti
                            3'b011 : begin                                       alu_ctrl[`ALU_CTRL_IS_NEG]    = 1'b1; alu_ctrl[`ALU_CTRL_IS_LESS]   = 1'b1; end // sltui
                            3'b100 : begin                                       alu_ctrl[`ALU_CTRL_IS_XOR_OR] = 1'b1;                                       end // xori
                            3'b110 : begin                                       alu_ctrl[`ALU_CTRL_IS_XOR_OR] = 1'b1; alu_ctrl[`ALU_CTRL_IS_OR_AND] = 1'b1; end // ori
                            3'b111 : begin                                                                             alu_ctrl[`ALU_CTRL_IS_OR_AND] = 1'b1; end // andi
                            3'b001 : begin // slli
                                if (funct7==7'b0000000) begin alu_ctrl[`ALU_CTRL_IS_SHIFT_LEFT] = 1'b1  ; end // slli
                                else illegal_instr  = 1'b1  ;
                            end
                            3'b101 : begin // srli/srai
                                case (funct7)
                                    7'b0000000: begin                                       alu_ctrl[`ALU_CTRL_IS_SHIFT_RIGHT] = 1'b1; end // srli
                                    7'b0100000: begin alu_ctrl[`ALU_CTRL_IS_SIGNED] = 1'b1; alu_ctrl[`ALU_CTRL_IS_SHIFT_RIGHT] = 1'b1; end // srai
                                    default: illegal_instr  = 1'b1  ;
                                endcase
                                
                            end
                            default: illegal_instr  = 1'b1  ;
                        endcase
                    end
                    5'b01100: begin // OP
                        instr_type                          = `R_TYPE   ;
                        case ({funct7, funct3})
                            10'b0000000000: begin                                                                             alu_ctrl[`ALU_CTRL_IS_ADD]         = 1'b1; end // add
                            10'b0100000000: begin                                       alu_ctrl[`ALU_CTRL_IS_NEG]    = 1'b1; alu_ctrl[`ALU_CTRL_IS_ADD]         = 1'b1; end // sub
                            10'b0000000001: begin                                                                             alu_ctrl[`ALU_CTRL_IS_SHIFT_LEFT]  = 1'b1; end // sll
                            10'b0000000010: begin alu_ctrl[`ALU_CTRL_IS_SIGNED] = 1'b1; alu_ctrl[`ALU_CTRL_IS_NEG]    = 1'b1; alu_ctrl[`ALU_CTRL_IS_LESS]        = 1'b1; end // slt
                            10'b0000000011: begin                                       alu_ctrl[`ALU_CTRL_IS_NEG]    = 1'b1; alu_ctrl[`ALU_CTRL_IS_LESS]        = 1'b1; end // sltu
                            10'b0000000100: begin                                       alu_ctrl[`ALU_CTRL_IS_XOR_OR] = 1'b1;                                            end // xor
                            10'b0000000101: begin                                                                             alu_ctrl[`ALU_CTRL_IS_SHIFT_RIGHT] = 1'b1; end // srl
                            10'b0100000101: begin alu_ctrl[`ALU_CTRL_IS_SIGNED] = 1'b1;                                       alu_ctrl[`ALU_CTRL_IS_SHIFT_RIGHT] = 1'b1; end // sra
                            10'b0000000110: begin                                       alu_ctrl[`ALU_CTRL_IS_XOR_OR] = 1'b1; alu_ctrl[`ALU_CTRL_IS_OR_AND]      = 1'b1; end // or
                            10'b0000000111: begin                                                                             alu_ctrl[`ALU_CTRL_IS_OR_AND]      = 1'b1; end // and
                            10'b0000001000: begin mul_ctrl[`MUL_CTRL_IS_MUL] = 1'b1;                                                                                                                           end // mul
                            10'b0000001001: begin mul_ctrl[`MUL_CTRL_IS_MUL] = 1'b1; mul_ctrl[`MUL_CTRL_IS_SRC1_SIGNED] = 1'b1; mul_ctrl[`MUL_CTRL_IS_SRC2_SIGNED] = 1'b1; mul_ctrl[`MUL_CTRL_IS_HIGH] = 1'b1; end // mulh
                            10'b0000001010: begin mul_ctrl[`MUL_CTRL_IS_MUL] = 1'b1; mul_ctrl[`MUL_CTRL_IS_SRC1_SIGNED] = 1'b1;                                            mul_ctrl[`MUL_CTRL_IS_HIGH] = 1'b1; end // mulhsu
                            10'b0000001011: begin mul_ctrl[`MUL_CTRL_IS_MUL] = 1'b1;                                                                                       mul_ctrl[`MUL_CTRL_IS_HIGH] = 1'b1; end // mulhu
                            10'b0000001100: begin div_ctrl[`DIV_CTRL_IS_DIV] = 1'b1; div_ctrl[`DIV_CTRL_IS_SIGNED] = 1'b1;                                    end // div
                            10'b0000001101: begin div_ctrl[`DIV_CTRL_IS_DIV] = 1'b1;                                                                          end // divu
                            10'b0000001110: begin div_ctrl[`DIV_CTRL_IS_DIV] = 1'b1; div_ctrl[`DIV_CTRL_IS_SIGNED] = 1'b1; div_ctrl[`DIV_CTRL_IS_REM] = 1'b1; end // rem
                            10'b0000001111: begin div_ctrl[`DIV_CTRL_IS_DIV] = 1'b1;                                       div_ctrl[`DIV_CTRL_IS_REM] = 1'b1; end // remu
                            default       : illegal_instr   = 1'b1  ;
                        endcase
                    end
                    5'b01011: begin // AMO
                        instr_type                          = `R_TYPE   ;
                        case ({funct7[6:2], funct3})
                            8'b00010010: begin
                                if (ir[24:20]==5'b00000) begin lsu_ctrl[`LSU_CTRL_IS_LOAD] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_LRSC] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // lr.w
                                else illegal_instr  = 1'b1  ;
                            end
                            8'b00011010: begin lsu_ctrl[`LSU_CTRL_IS_STORE] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_LRSC] = 1'b1; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // sc.w
                            8'b00001010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_SWAP             ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amoswap.w
                            8'b00000010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_ADD              ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amoadd.w
                            8'b00100010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_EOR              ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amoxor.w
                            8'b01100010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_CLR              ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amoand.w
                            8'b01000010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_SET              ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amoor.w
                            8'b10000010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_SMIN             ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amomin.w
                            8'b10100010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_SMAX             ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amomax.w
                            8'b11000010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_UMIN             ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amominu.w
                            8'b11100010: begin lsu_ctrl[`LSU_CTRL_IS_AMO]   = 1'b1; awatop = `AWATOP_UMAX             ; lsu_ctrl[`LSU_CTRL_IS_WORD] = 1'b1; end // amomaxu.w
                            default    : illegal_instr  = 1'b1  ;
                        endcase
                    end
                    default : illegal_instr = 1'b1  ;
                endcase
            end
            default: illegal_instr  = 1'b1  ;
        endcase

        // register address
        case (instr_type)
            `S_TYPE, `B_TYPE            : rd = 5'd0         ;
            default                     : rd = ir[11:7]     ;
        endcase
        case (instr_type)
            `U_TYPE, `J_TYPE            : rs1 = 5'd0        ;
            default                     : rs1 = ir[19:15]   ;
        endcase
        case (instr_type)
            `I_TYPE, `U_TYPE, `J_TYPE   : rs2 = 5'd0        ;
            default                     : rs2 = ir[24:20]   ;
        endcase

        // csr address
        csr_rf_we   = (csr_ctrl[`CSR_CTRL_IS_CSR] && !csr_ctrl[`CSR_CTRL_IS_READ])  ;
        csr_addr    = (csr_ctrl[`CSR_CTRL_IS_CSR]) ? ir[31:20] : 0                  ;

    end

    assign illegal_instr_o  = illegal_instr ;
    assign instr_type_o     = instr_type    ;
    assign src1_ctrl_o      = src1_ctrl     ;
    assign src2_ctrl_o      = src2_ctrl     ;
    assign sys_ctrl_o       = sys_ctrl      ;
    assign csr_ctrl_o       = csr_ctrl      ;
    assign alu_ctrl_o       = alu_ctrl      ;
    assign bru_ctrl_o       = bru_ctrl      ;
    assign lsu_ctrl_o       = lsu_ctrl      ;
    assign awatop_o         = awatop        ;
    assign mul_ctrl_o       = mul_ctrl      ;
    assign div_ctrl_o       = div_ctrl      ;
    assign fencei_o         = fencei        ;
    assign rf_we_o          = |rd           ;
    assign rd_o             = rd            ;
    assign rs1_o            = rs1           ;
    assign rs2_o            = rs2           ;
    assign csr_rf_we_o      = csr_rf_we     ;
    assign csr_addr_o       = csr_addr      ;

endmodule
/******************************************************************************************/

`resetall
