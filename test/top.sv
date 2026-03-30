/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

`define FLUSH_CYCLES    10000000

/* testbench for simulation */
//******************************************************************************************/
module top;

    bit clk  ; always  #40  clk   <= !clk;
    bit rst_n; initial #400 rst_n  = 1'b1;

    default clocking cb @(posedge soc.clk); endclocking

    longint unsigned mtime;
    always_ff @(cb) begin
        mtime <= mtime+1;
        if (mtime%`FLUSH_CYCLES=='h0) $fflush;
    end

    // display cycles
    longint unsigned display_cycles;
    initial begin
        if ($value$plusargs("display_cycles=%d", display_cycles)) begin
            $info("display_cycles=%d", display_cycles);
        end
    end

    always_ff @(cb) begin ///// display '.' periodically
        if ((display_cycles!=0) && (mtime!=0) && (mtime%(display_cycles/10)==0)) begin
            $write("\033[0;1;36m.\033[0m");
            $fflush();
        end
    end
//    always_ff @(cb) begin // Note
//        if ((display_cycles!=0) && (mtime!=0) && (mtime%(display_cycles/10)==0)) begin
//            $write("\033[0;1;36m.\033[0m");
//            $fflush();
//        end
//    end
    
    // timeout
    longint unsigned max_cycles;
    initial begin
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin
            $info("max_cycles=%d", max_cycles);
        end else begin
            $fatal(1, "specify a max_cycles.");
        end
    end
    always_ff @(cb) begin
        if (mtime>=max_cycles) begin
            $write("\n\n\n"                         );
            $write("\033[0;1;31m\n===> simulation timeout...\033[0m\n");
            $write("\n"                             );
            $finish(1);
        end
    end

    always_ff @(cb) begin
        if (soc.axi_interconnect.rd_state_q==soc.axi_interconnect.RD_IDLE &&
            soc.axi_interconnect.cpu_araddr_i[`PLEN-1:28] >= 'hc) begin
                $display("READ access to undefined address %h\n", soc.axi_interconnect.cpu_araddr_i);
                $display("mprv: %b, mpp: %b, priv_lvl_i: %b, satp[31]: %b", soc.mmu.mprv_i, soc.mmu.mpp_i, soc.cpu.priv_lvl, soc.mmu.satp_i[31]);
                if (soc.mmu.priv_lvl_i != 2'b11) begin
                    $finish(1);
                end
        end
    end

    // dump FST: Fast Signal Trace
    string trace_fst_file;
    initial begin
        if ($value$plusargs("trace_fst_file=%s", trace_fst_file)) begin
            $dumpfile(trace_fst_file);
            $dumpvars;
        end
    end

    // dump VCD: Value Change Dump
    string trace_vcd_file;
    initial begin
        if ($value$plusargs("trace_vcd_file=%s", trace_vcd_file)) begin
            $dumpfile(trace_vcd_file);
            $dumpvars;
        end
    end

    // dump store conditional series
    string trace_sc_file;
    int trace_sc_fd;
    reg trace_sc;
    initial begin
        trace_sc = 1'b0;
        if ($value$plusargs("trace_sc_file=%s", trace_sc_file)) begin
            trace_sc = 1'b1;
            trace_sc_fd = $fopen(trace_sc_file, "w");
            if (trace_sc_fd) ; else $fatal(1, "file cannot opened");
        end
    end
    final begin
        if (trace_sc) begin
            $fclose(trace_sc_fd);
        end
    end

    // uart tranceiver
    wire txd;
`ifdef NO_UART_BOOT
    assign txd  = 1'b1  ;

`else
    reg  [127:0] rom [`BIN_SIZE/16];

    reg   [31:0] addr_q  , addr_d        ;
    wire  [27:0] index   = addr_q[31:4]  ;
    wire   [3:0] offset  = addr_q[ 3:0]  ;

    reg         uart_wvalid_q   , uart_wvalid_d ;
    wire        uart_wready                     ;
    wire  [7:0] uart_wdata                      ;

    always_comb begin
        uart_wvalid_d   = uart_wvalid_q ;
        addr_d          = addr_q        ;
        if ((addr_q>=`BIN_SIZE-1) && uart_wready) begin
            uart_wvalid_d   = 1'b0          ;
        end
        if (uart_wvalid_q && uart_wready && (addr_q<`BIN_SIZE)) begin
            addr_d          = addr_q+'h1    ;
        end
    end

    always_ff @(cb) begin
        if (!rst_n) begin
            uart_wvalid_q   <= 1'b1             ;
            addr_q          <= 'h0              ;
        end else begin
            uart_wvalid_q   <= uart_wvalid_d    ;
            addr_q          <= addr_d           ;
        end
    end
    assign uart_wdata = rom[index][8*offset+:8];

    uart_tx #(
        .CLK_FREQ_MHZ   (`CLK_FREQ_MHZ  ),
        .BAUD_RATE      (`BAUD_RATE     )
    ) uart_tx (
        .clk_i          (soc.clk        ), // input  wire
        .rst_i          (!rst_n         ), // input  wire
        .txd_o          (txd            ), // output wire
        .wvalid_i       (uart_wvalid_q  ), // input  wire
        .wready_o       (uart_wready    ), // output wire
        .wdata_i        (uart_wdata     )  // input  wire [7:0]
    );
`endif // NO_UART_BOOT

    // soc
    wire rxd;
    soc soc (
        .clk_i          (clk            ), // input  wire
        .rst_ni         (rst_n          ), // input  wire
        .rxd_i          (txd            ), // input  wire
        .txd_o          (rxd            ), // output wire
        .eth_mdc        (               ), // output wire
        .eth_mdio       (               ), // inout  wire
        .eth_rstn       (               ), // output wire
`ifdef ETH_IF_RMII
        .eth_crsdv      (               ), // input  wire
        .eth_rxerr      (               ), // input  wire
        .eth_rxd        (               ), // input  wire [1:0]
        .eth_txen       (               ), // output wire
        .eth_txd        (               ), // output wire [1:0]
        .eth_refclk     (               ), // output wire
        .eth_intn       (               ), // input  wire
`else
        .eth_rx_clk     (clk            ), // input  wire
        .eth_tx_clk     (clk            ), // input  wire
        .eth_rx_dv      (1'b0           ), // input  wire
        .eth_rxerr      (1'b0           ), // input  wire
        .eth_rxd        (4'h0           ), // input  wire [3:0]
        .eth_tx_en      (               ), // output wire
        .eth_txd        (               ), // output wire [3:0]
        .eth_refclk     (               ), // output wire
`endif
`ifdef NEXYS // Nexys
        .ddr2_addr      (               ), // output wire [12:0]
        .ddr2_ba        (               ), // output wire  [2:0]
        .ddr2_cas_n     (               ), // output wire
        .ddr2_ck_n      (               ), // output wire  [0:0]
        .ddr2_ck_p      (               ), // output wire  [0:0]
        .ddr2_cke       (               ), // output wire  [0:0]
        .ddr2_ras_n     (               ), // output wire
        .ddr2_we_n      (               ), // output wire
        .ddr2_dq        (               ), // inout  wire [15:0]
        .ddr2_dqs_n     (               ), // inout  wire  [1:0]
        .ddr2_dqs_p     (               ), // inout  wire  [1:0]
        .ddr2_cs_n      (               ), // output wire  [0:0]
        .ddr2_dm        (               ), // output wire  [1:0]
        .ddr2_odt       (               ), // output wire  [0:0]
        .sd_cd          (               ),  // input  wire
        .sd_rst         (               ),  // output wire
        .sd_sclk        (               ),  // output wire
        .sd_cmd         (               ),  // inout  wire
        .sd_dat         (               ),  // inout  wire [3:0]
        .pclk           (1'b0           ),  // input  wire
        .camera_v_sync  (1'b0           ),  // input  wire
        .camera_h_ref   (1'b0           ),  // input  wire
        .din            (8'h00          ),  // input  wire [7:0]
        .sioc           (               ),  // output wire
        .siod           (               ),  // inout  wire
        .reset          (               ),  // output wire
        .power_down     (               ),  // output wire
        .xclk           (               )   // output wire
`else // DDR3, Arty
        .ddr3_addr      (               ), // output wire [13:0]
        .ddr3_ba        (               ), // output wire  [2:0]
        .ddr3_cas_n     (               ), // output wire
        .ddr3_ck_n      (               ), // output wire  [0:0]
        .ddr3_ck_p      (               ), // output wire  [0:0]
        .ddr3_cke       (               ), // output wire  [0:0]
        .ddr3_ras_n     (               ), // output wire
        .ddr3_reset_n   (               ), // output wire
        .ddr3_we_n      (               ), // output wire
        .ddr3_dq        (               ), // inout  wire [15:0]
        .ddr3_dqs_n     (               ), // inout  wire  [1:0]
        .ddr3_dqs_p     (               ), // inout  wire  [1:0]
        .ddr3_cs_n      (               ), // output wire  [0:0]
        .ddr3_dm        (               ), // output wire  [1:0]
        .ddr3_odt       (               )  // output wire  [0:0]
`endif
    );

    // ram
    string mem_file, kernel_file, initrd_file, dtb_file;
    int unsigned kernel_base, initrd_base, dtb_base;

    initial begin

        // mem_file
        if ($value$plusargs("mem_file=%s", mem_file)) begin
            $info("mem_file: %s", mem_file);
`ifdef NO_UART_BOOT
            $readmemh(mem_file, soc.dram_controller.u_mig_7series_0.ram);
`else  // UART_BOOT
            $readmemh(mem_file, rom         );
`endif // NO_UART_BOOT
        end else begin
            $fatal(1, "specify a mem_file.");
        end

        // kernel
        if ($value$plusargs("kernel=%s", kernel_file)) begin
            if ($value$plusargs("kernel_base=0x%x", kernel_base)) begin
                $info("kernel       : %s (0x%08x)", kernel_file, kernel_base);
                $readmemh(kernel_file, soc.dram_controller.u_mig_7series_0.ram, (kernel_base-`DRAM_BASE)/`DBUS_STRB_WIDTH);
            end else begin
                $fatal(1, "specify a kernel_base.");
            end
        end

        // initrd
        if ($value$plusargs("initrd=%s", initrd_file)) begin
            if ($value$plusargs("initrd_base=0x%x", initrd_base)) begin
                $info("initrd       : %s (0x%08x)", initrd_file, initrd_base);
                $readmemh(initrd_file, soc.dram_controller.u_mig_7series_0.ram, (initrd_base-`DRAM_BASE)/`DBUS_STRB_WIDTH);
            end else begin
                $fatal(1, "specify a initrd_base.");
            end
        end

    end

    // uart receiver
    wire       uart_rvalid  ;
    wire [7:0] uart_rdata   ;
    uart_rx #(
        .CLK_FREQ_MHZ   (`CLK_FREQ_MHZ  ),
        .BAUD_RATE      (`BAUD_RATE     ),
        .DETECT_COUNT   (`DETECT_COUNT  )
    ) uart_rx (
        .clk_i          (soc.clk        ), // input  wire
        .rst_i          (!rst_n         ), // input  wire
        .rxd_i          (rxd            ), // input  wire
        .rvalid_o       (uart_rvalid    ), // output wire
        .rready_i       (1'b1           ), // input  wire
        .rdata_o        (uart_rdata     )  // output wire [7:0]
    );

    // loader
    bit load_done;
    always_ff @(cb) begin
        if (soc.cpu.r_pc==`START_PC) load_done  <= 1'b1 ;
    end

    bit cpu_fini, cpu_sim_fini, soc_sim_fini;

    // counter
    longint unsigned mcycle, minstret;
    always_ff @(cb) begin
        if (load_done && !cpu_sim_fini) begin
            ++mcycle;
        end
        if (load_done && !cpu_sim_fini && !soc.cpu.stall && soc.cpu.Wb_v) begin
            ++minstret;
        end
    end

    // signature file
    string sig_file;
    int sig_fd;
    bit dump_signature;
    initial begin
        if ($value$plusargs("signature=%s", sig_file)) begin
            sig_fd = $fopen(sig_file, "w");
            if (sig_fd) ; else $fatal(1, "file cannot opened");
            dump_signature = 1'b1;
        end
    end
    final begin
        if (dump_signature) begin
            $fclose(sig_fd);
        end
    end

    always_ff @(cb) if (dump_signature) begin
        if (soc.dbus_wvalid && soc.dbus_wready && (soc.dbus_axaddr==`SIG_ADDR) && (soc.dbus_wstrb=={`DBUS_STRB_WIDTH{1'b1}})) begin
            $fwrite(sig_fd, "%08x\n", soc.dbus_wdata);
        end
    end

    // commit log file
    string commit_log_file;
    int commit_log_fd;
    bit commit_log_on;
    initial begin
        if ($value$plusargs("commit_log_file=%s", commit_log_file)) begin
            commit_log_fd = $fopen(commit_log_file, "w");
            if (commit_log_fd) ; else $fatal(1, "file cannot opened");
            commit_log_on = 1'b1;
        end
    end
    final begin
        if (commit_log_on) begin
            $fclose(commit_log_fd);
        end
    end

    logic                        dbus_re_q      , dbus_re_d     ;
    logic [`DBUS_ADDR_WIDTH-1:0] dbus_raddr_q   , dbus_raddr_d  ;
    logic                        dbus_we_q      , dbus_we_d     ;
    logic [`DBUS_ADDR_WIDTH-1:0] dbus_waddr_q   , dbus_waddr_d  ;
    logic [`DBUS_DATA_WIDTH-1:0] dbus_wdata_q   , dbus_wdata_d  ;
    logic [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_q   , dbus_wstrb_d  ;
    always_comb begin
        dbus_re_d       = dbus_re_q         ;
        dbus_raddr_d    = dbus_raddr_q      ;
        dbus_we_d       = dbus_we_q         ;
        dbus_waddr_d    = dbus_waddr_q      ;
        dbus_wdata_d    = dbus_wdata_q      ;
        dbus_wstrb_d    = dbus_wstrb_q      ;
        if ((!soc.cpu.stall && soc.cpu.Wb_v) || soc.cpu.Wb_exc_valid) begin
            dbus_re_d       = 1'b0              ;
            dbus_we_d       = 1'b0              ;
        end
        if (soc.dbus_arvalid && soc.dbus_arready) begin
            dbus_re_d       = 1'b1              ;
            dbus_raddr_d    = soc.dbus_axaddr   ;
        end
        if (soc.dbus_wvalid && soc.dbus_wready) begin
            dbus_we_d       = 1'b1              ;
            dbus_waddr_d    = soc.dbus_axaddr   ;
            dbus_wdata_d    = soc.dbus_wdata    ;
            dbus_wstrb_d    = soc.dbus_wstrb    ;
        end
    end

    always_ff @(posedge soc.clk) begin
        if (soc.rst) begin
            dbus_re_q       <= 1'b0             ;
            dbus_we_q       <= 1'b0             ;
        end else begin
            dbus_re_q       <= dbus_re_d        ;
            dbus_raddr_q    <= dbus_raddr_d     ;
            dbus_we_q       <= dbus_we_d        ;
            dbus_waddr_q    <= dbus_waddr_d     ;
            dbus_wdata_q    <= dbus_wdata_d     ;
            dbus_wstrb_q    <= dbus_wstrb_d     ;
        end
    end

    always_ff @(cb) if (commit_log_on) begin
        if (load_done && !cpu_sim_fini && !soc.cpu.stall && soc.cpu.Wb_v && (soc.cpu.ExWb_ir!=`UNIMP)) begin
            spike_commit_log(commit_log_fd, 0, soc.cpu.priv_lvl, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_rf_we, soc.cpu.ExWb_rd, soc.cpu.Wb_rslt, dbus_re_q, dbus_raddr_q, dbus_we_q, dbus_waddr_q, dbus_wdata_q, dbus_wstrb_q, soc.cpu.csrs.csr_we_i, soc.cpu.csrs.csr_waddr_i, soc.cpu.csrs.csr_wdata_i);
        end
    end

    // trace register file
    string trace_rf_file;
    int trace_rf_fd;
    bit trace_rf_on;
    int unsigned trace_rf_begin, trace_rf_end = -1;
    initial begin
        if ($value$plusargs("trace_rf_file=%s", trace_rf_file)) begin
            trace_rf_fd = $fopen(trace_rf_file, "w");
            if (trace_rf_fd) ; else $fatal(1, "file cannot opened");
            trace_rf_on = 1'b1;
            if ($value$plusargs("trace_rf_begin=%d", trace_rf_begin )) ;
            if ($value$plusargs("trace_rf_end=%d"  , trace_rf_end   )) ;
        end
    end
    final begin
        if (trace_rf_on) begin
            $fclose(trace_rf_fd);
        end
    end

    always_ff @(cb) if (trace_rf_on) begin
        if (load_done && !cpu_sim_fini && !soc.cpu.stall && soc.cpu.Wb_v) begin
            if (minstret>=trace_rf_begin && minstret<=trace_rf_end) begin
                rf32_fprint(trace_rf_fd, minstret, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_rf_we, soc.cpu.ExWb_rd, soc.cpu.Wb_rslt, soc.cpu.regs.xreg);
            end
        end
    end

    // trace data memory
    string trace_dmem_file;
    int trace_dmem_fd;
    bit trace_dmem_on;
    initial begin
        if ($value$plusargs("trace_dmem_file=%s", trace_dmem_file)) begin
            trace_dmem_fd   = $fopen(trace_dmem_file, "w")  ;
            if (trace_dmem_fd) ; else $fatal(1, "file cannot opened")   ;
            trace_dmem_on   = 1'b1  ;
        end
    end
    final begin
        if (trace_dmem_on) begin
            $fclose(trace_dmem_fd);
        end
    end

    always_ff @(cb) if (trace_dmem_on) begin
        if (load_done && !cpu_sim_fini && soc.dram_controller.u_mig_7series_0.s_axi_wvalid && soc.dram_controller.u_mig_7series_0.s_axi_wready) begin
            $fwrite(trace_dmem_fd, "addr=[%08x] wdata=[%08x] wstrb=[%04b]\n", soc.dram_controller.u_mig_7series_0.s_axi_awaddr, soc.dram_controller.u_mig_7series_0.s_axi_wdata, soc.dram_controller.u_mig_7series_0.s_axi_wstrb);
        end
    end

    // debug log
    bit enable_debug_log;
    initial begin
        if ($value$plusargs("enable_debug_log=%d", enable_debug_log)) $write("enable debug log detected!!\n");
    end
    // rvtest pass/fail
    bit rvtest_mode;
    initial begin
        if ($value$plusargs("rvtest_mode=%d", rvtest_mode)) begin
            $info("rvtest_mode=%d", rvtest_mode);
        end
    end
    

//    reg rsvd;
//    always_ff @(cb) if (enable_debug_log) begin
//        if ((rsvd==0) && (soc.dram_controller.rsvd_q==1)) $write("\033[0;1;36m[       debug]       load reseved detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_araddr);
//        if ((rsvd==1) && (soc.dram_controller.rsvd_q==0)) $write("\033[0;1;36m[       debug]  store conditional detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_awaddr);
//        rsvd    <= soc.dram_controller.rsvd_q  ;
//    end

    // peripheral read/write
    always_ff @(cb) if (enable_debug_log) begin
        if (soc.bus_wvalid && soc.bus_wready) begin
            case (soc.bus_awaddr[31:24])
//                8'h02   : $write("\033[0;1;36m[       debug] clint write detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x], wdata=[%08x], wstrb=[%04b]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_awaddr, soc.bus_wdata, soc.bus_wstrb);
                8'h0c   : $write("\033[0;1;36m[       debug]  plic write detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x], wdata=[%08x], wstrb=[%04b]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_awaddr, soc.bus_wdata, soc.bus_wstrb);
//                8'h10   : $write("\033[0;1;36m[       debug]  uart write detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x], wdata=[%08x], wstrb=[%04b]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_awaddr, soc.bus_wdata, soc.bus_wstrb);
                default : ;
            endcase
        end
        if (soc.bus_arvalid && soc.bus_arready) begin
            case (soc.bus_araddr[31:24])
//                8'h02   : $write("\033[0;1;36m[       debug] clint read  detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_araddr);
                8'h0c   : $write("\033[0;1;36m[       debug]  plic read  detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_araddr);
//                8'h10   : $write("\033[0;1;36m[       debug]  uart read  detected!! time=[%12d], pc=[%08x], ir=[%08x], addr=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.bus_araddr);
                default : ;
            endcase
        end
        if (|soc.irq) begin
            $write("\033[0;1;36m[       debug] irq detected!! mtime=[%12d], irq=[%02b]\033[0m\n", mtime, soc.irq);
        end
    end

    // store conditional
    always_ff @(cb) if (trace_sc) begin
        if (soc.cpu.lsu.state_q == soc.cpu.lsu.STORE
            && soc.cpu.lsu.dbus_bvalid_i
            && soc.cpu.lsu.lsu_ctrl_q[`LSU_CTRL_IS_LRSC]
        ) begin
            $fwrite(trace_sc_fd, "store conditional detected !! pc=[%08x] rslt=[%08x] \n", soc.cpu.ExWb_pc, soc.cpu.lsu.rslt_d);        
        end
    end

    // exceptions/interrupts
    always_ff @(cb) if (enable_debug_log) begin
        if (!soc.cpu.stall && soc.cpu.Wb_exc_valid) begin
            case (soc.cpu.Wb_cause)
                `CAUSE_S_TIMER              : begin $write("\033[0;1;36m[       debug] supervisor    timer interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_S_SOFT               : begin $write("\033[0;1;36m[       debug] supervisor software interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_S_EXT                : begin $write("\033[0;1;36m[       debug] supervisor external interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_M_TIMER              : begin $write("\033[0;1;36m[       debug]    machine    timer interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_M_SOFT               : begin $write("\033[0;1;36m[       debug]    machine software interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_M_EXT                : begin $write("\033[0;1;36m[       debug]    machine external interrupt detected!! mtime=[%12d]\033[0m\n", mtime); end
                `CAUSE_INSTR_ADDR_MISALIGNED: begin $write("\033[0;1;36m[       debug]         instr addr misaligned detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_INSTR_ACCESS_FAULT   : begin $write("\033[0;1;36m[       debug]            instr access fault detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_ILLEGAL_INSTR        : begin $write("\033[0;1;36m[       debug]                 illegal instr detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_BREAKPOINT           : begin $write("\033[0;1;36m[       debug]                    breakpoint detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_LD_ADDR_MISALIGNED   : begin $write("\033[0;1;36m[       debug]          load addr misaligned detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_LD_ACCESS_FAULT      : begin $write("\033[0;1;36m[       debug]             load access fault detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_ST_ADDR_MISALIGNED   : begin $write("\033[0;1;36m[       debug]         store addr misaligned detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_ST_ACCESS_FAULT      : begin $write("\033[0;1;36m[       debug]            store access fault detected!! mtime=[%12d], pc=[%08x], ir=[%08x], tval=[%08x]\033[0m\n", mtime, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval); end
                `CAUSE_INSTR_PAGE_FAULT     : begin $write("\033[0;1;36m[       debug]              instr page fault detected!! mtime=[%12d], priv_lvl=[%1d], mpp=[%1d], mprv=[%1d], pc=[%08x], ir=[%08x], tval=[%08x], vaddr=[%08x], pte_addr=[%08x]\033[0m\n", mtime, soc.mmu.ptw.priv_lvl_i, soc.mmu.ptw.mpp_i, soc.mmu.ptw.mprv_i, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval, soc.mmu.ptw.vaddr_q, soc.mmu.ptw.pte_araddr_q); end
                `CAUSE_LOAD_PAGE_FAULT      : begin $write("\033[0;1;36m[       debug]               load page fault detected!! mtime=[%12d], priv_lvl=[%1d], mpp=[%1d], mprv=[%1d], pc=[%08x], ir=[%08x], tval=[%08x], vaddr=[%08x], pte_addr=[%08x]\033[0m\n", mtime, soc.mmu.ptw.priv_lvl_i, soc.mmu.ptw.mpp_i, soc.mmu.ptw.mprv_i, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval, soc.mmu.ptw.vaddr_q, soc.mmu.ptw.pte_araddr_q); end
                `CAUSE_STORE_PAGE_FAULT     : begin $write("\033[0;1;36m[       debug]              store page fault detected!! mtime=[%12d], priv_lvl=[%1d], mpp=[%1d], mprv=[%1d], pc=[%08x], ir=[%08x], tval=[%08x], vaddr=[%08x], pte_addr=[%08x]\033[0m\n", mtime, soc.mmu.ptw.priv_lvl_i, soc.mmu.ptw.mpp_i, soc.mmu.ptw.mprv_i, soc.cpu.ExWb_pc, soc.cpu.ExWb_ir, soc.cpu.Wb_tval, soc.mmu.ptw.vaddr_q, soc.mmu.ptw.pte_araddr_q); end
                default                     : ;
            endcase
        end
    end


//    // wfi
//    int unsigned wfi_cntr;
//    always_ff @(cb) if (enable_debug_log) begin
//        if (!soc.cpu.stall && soc.cpu.Wb_v) begin
//            if (soc.cpu.ExWb_ir==32'h10500073) begin
//                if (wfi_cntr%10000=='h0) $write("\033[0;1;36m[       debug] wfi detected!! mtime=[%12d], wfi_cntr=[%12d], pc=[%08x]\033[0m\n", mtime, wfi_cntr, soc.cpu.ExWb_pc);
//                wfi_cntr <= wfi_cntr+'h1;
//            end
//        end
//    end

    // cache/tlb
    longint unsigned l0_icache_hit, l0_icache_miss, l0_icache_total;
    longint unsigned itlb_hit, itlb_miss, itlb_total, icache_hit, icache_miss, icache_total;
    longint unsigned dtlb_hit, dtlb_miss, dtlb_total, dcache_hit, dcache_miss, dcache_total;
    longint unsigned cache_hit, cache_miss, cache_total;
    // branch
    longint unsigned branch_hit, branch_miss, branch_total, branch_miss_penalty, branch_miss_penalty_total;
    // stall
    longint unsigned ifu_stall, lsu_stall, mul_stall, div_stall;
    longint unsigned load_stall, store_stall, amo_stall;
    // laod/store instruction nums
    longint unsigned load_insts, store_insts;
    reg [1:0] state_d = 0;
    localparam IDLE=2'h0, LOAD=2'h1, STORE=2'h2;
    longint unsigned total_penalty, total_estimate_cycle;
    
    reg [1:0] pre_mul_state_q, pre_div_state_q;
    always_ff @(cb) begin
        if (soc.cpu.ifu.state_q==soc.cpu.ifu.IDLE) begin
            if (!soc.cpu.ifu.hit) l0_icache_miss                <= l0_icache_miss+'h1   ;
            if (!soc.cpu.rst && !soc.cpu.stall) l0_icache_total <= l0_icache_total+'h1  ;
        end
        if (soc.mmu.istate_q==soc.mmu.I_TLB) begin
            if (soc.mmu.itlb_valid) itlb_hit                    <= itlb_hit+'h1         ;
            itlb_total                                          <= itlb_total+'h1       ;
        end
        if (soc.mmu.istate_q==soc.mmu.I_CACHE) begin
            if ( soc.mmu.icache_hit) icache_hit                 <= icache_hit+'h1       ;
            if (!soc.mmu.icache_hit) icache_miss                <= icache_miss+'h1      ;
            icache_total                                        <= icache_total+'h1     ;
        end
        if (soc.mmu.dstate_q==soc.mmu.D_TLB) begin
            if (soc.mmu.dtlb_valid) dtlb_hit                    <= dtlb_hit+'h1         ;
            dtlb_total                                          <= dtlb_total+'h1       ;
        end
        if (soc.mmu.dstate_q==soc.mmu.D_CACHE) begin
            if ( soc.mmu.dcache_hit) dcache_hit                 <= dcache_hit+'h1       ;
            if (!soc.mmu.dcache_hit) dcache_miss                <= dcache_miss+'h1      ;
            dcache_total                                        <= dcache_total+'h1     ;
        end
        if (soc.l2_cache.state_q==soc.l2_cache.CHECK_VALID) begin
            if ( |soc.l2_cache.hit_q) cache_hit                 <= cache_hit+'h1        ;
            if (~|soc.l2_cache.hit_q) cache_miss                <= cache_miss+'h1       ;
            cache_total                                         <= cache_total+'h1      ;
        end
        if (soc.cpu.Wb_br_misp && !soc.cpu.stall) begin
            branch_miss                                         <= branch_miss+'h1       ;
        end
        if (soc.cpu.ExWb_v && soc.cpu.ExWb_is_ctrl_tsfr && !soc.cpu.Wb_br_misp && !soc.cpu.stall) begin
            branch_hit                                          <= branch_hit+'h1        ;
        end
        pre_mul_state_q <= soc.cpu.multiplier.state_q;
        pre_div_state_q <= soc.cpu.divider.state_q;
        if (soc.cpu.ifu_stall && soc.cpu.ifu.state_q != soc.cpu.ifu.RET) begin
            ifu_stall                                           <= ifu_stall+'h1        ;
        end
        if (!soc.cpu.Wb_exc_valid && !soc.cpu.eret && !soc.cpu.Wb_csr_replay && !(soc.cpu.csr_flush || soc.cpu.Wb_sfence_vma || soc.cpu.Wb_fencei)
            && soc.cpu.lsu_stall && soc.cpu.lsu.state_q != soc.cpu.lsu.RET) begin
            if (state_d==IDLE) begin
                if (soc.cpu.lsu.lsu_ctrl_q[`LSU_CTRL_IS_LOAD]) state_d = LOAD;
                if (soc.cpu.lsu.lsu_ctrl_q[`LSU_CTRL_IS_STORE]) state_d = STORE;
            end
            lsu_stall                                           <= lsu_stall+'h1        ;
            if (state_d == LOAD) load_stall                     <= load_stall+'h1       ;
            if (state_d == STORE) store_stall                   <= store_stall+'h1      ;
        end else begin
            state_d = IDLE;
        end
        if (soc.cpu.mul_stall && !(pre_mul_state_q == soc.cpu.multiplier.RET && soc.cpu.multiplier.state_q == soc.cpu.multiplier.RET)) begin
            mul_stall                                           <= mul_stall+'h1        ;
        end
        if (soc.cpu.div_stall && !(pre_div_state_q == soc.cpu.divider.RET && soc.cpu.divider.state_q == soc.cpu.divider.RET)) begin
            div_stall                                           <= div_stall+'h1        ;
        end
        if (soc.cpu.lsu.valid_i && soc.cpu.lsu.state_q==soc.cpu.lsu.IDLE && soc.cpu.lsu.lsu_ctrl_q[`LSU_CTRL_IS_LOAD]) begin
            load_insts                                        <= load_insts+'h1       ;
        end
        if(soc.cpu.lsu.valid_i && soc.cpu.lsu.state_q==soc.cpu.lsu.IDLE && soc.cpu.lsu.lsu_ctrl_q[`LSU_CTRL_IS_STORE]) begin
            store_insts                                       <= store_insts+'h1      ;
        end
    end
    assign l0_icache_hit             = l0_icache_total-l0_icache_miss;
    assign itlb_miss                 = itlb_total-itlb_hit            ;
    assign dtlb_miss                 = dtlb_total-dtlb_hit            ;
    assign branch_total              = branch_hit+branch_miss         ;
    assign branch_miss_penalty       = 4                              ;
    assign branch_miss_penalty_total = branch_miss*branch_miss_penalty;
    assign total_penalty             = branch_miss * branch_miss_penalty + ifu_stall + lsu_stall + mul_stall + div_stall ;
    assign total_estimate_cycle      = minstret + total_penalty       ;
    // print, exit
    always_ff @(cb) begin
        // uart_putc
        if (soc.dbus_wvalid && soc.dbus_wready && (soc.dbus_axaddr==`UART_BASE) && soc.dbus_wstrb=='b1) begin
            $write("%c", soc.dbus_wdata[7:0])   ;
        end
        // unimp
        if (soc.cpu.Wb_exc_valid && (soc.cpu.ExWb_ir==`UNIMP) && !soc.cpu.stall) begin
            if (rvtest_mode) begin
                if (soc.cpu.regs.xreg[10] == 32'd0) begin
                    $write("\033[0;1;32mpass!!\033[0m\n");
                end else begin
                    $write("\033[0;1;31mfail!! a0=[%d]\033[0m\n", soc.cpu.regs.xreg[10]);
                end
            end
            $write("\033[0;1;32munimp detected!!\033[0m\n");
            $finish(1);
        end
    end
    // results
    final begin
        $write("\n"                                                                                                 );
        $write("===> pc                             :     %08x\n"   , soc.cpu.ExWb_pc                               );
        $write("===> ir                             :     %08x\n"   , soc.cpu.ExWb_ir                               );
        $write("===> mtime                          : %12d\n"       , mtime                                         );
        $write("===> mcycle                         : %12d\n"       , mcycle                                        );
        $write("===> minstret                       : %12d\n"       , minstret                                      );
        $write("===> L0 icache hit                  : %12d\n"       , l0_icache_hit                                 );
        $write("===> L0 icache miss                 : %12d\n"       , l0_icache_miss                                );
        $write("===> L0 icache total                : %12d\n"       , l0_icache_total                               );
        $write("===> L0 icache hit rate             :     %f\n"     , $itor(l0_icache_hit) / $itor(l0_icache_total) );
        $write("===> itlb hit                       : %12d\n"       , itlb_hit                                      );
        $write("===> itlb miss                      : %12d\n"       , itlb_miss                                     );
        $write("===> itlb total                     : %12d\n"       , itlb_total                                    );
        $write("===> itlb hit rate                  :     %f\n"     , $itor(itlb_hit) / $itor(itlb_total)           );
        $write("===> dtlb hit                       : %12d\n"       , dtlb_hit                                      );
        $write("===> dtlb miss                      : %12d\n"       , dtlb_miss                                     );
        $write("===> dtlb total                     : %12d\n"       , dtlb_total                                    );
        $write("===> dtlb hit rate                  :     %f\n"     , $itor(dtlb_hit) / $itor(dtlb_total)           );
        $write("===> L1 icache hit                  : %12d\n"       , icache_hit                                    );
        $write("===> L1 icache miss                 : %12d\n"       , icache_miss                                   );
        $write("===> L1 icache total                : %12d\n"       , icache_total                                  );
        $write("===> L1 icache hit rate             :     %f\n"     , $itor(icache_hit) / $itor(icache_total)       );
        $write("===> L1 dcache hit                  : %12d\n"       , dcache_hit                                    );
        $write("===> L1 dcache miss                 : %12d\n"       , dcache_miss                                   );
        $write("===> L1 dcache total                : %12d\n"       , dcache_total                                  );
        $write("===> L1 dcache hit rate             :     %f\n"     , $itor(dcache_hit) / $itor(dcache_total)       );
        $write("===> L2 cache hit                   : %12d\n"       , cache_hit                                     );
        $write("===> L2 cache miss                  : %12d\n"       , cache_miss                                    );
        $write("===> L2 cache total                 : %12d\n"       , cache_total                                   );
        $write("===> L2 cache hit rate              :     %f\n"     , $itor(cache_hit) / $itor(cache_total)         );
        $write("===> branch hit                     : %12d\n"       , branch_hit                                    );
        $write("===> branch miss                    : %12d\n"       , branch_miss                                   );
        $write("===> branch total                   : %12d\n"       , branch_total                                  );
        $write("===> branch miss rate               :     %f\n"     , $itor(branch_miss) / $itor(branch_total)      );
        $write("===> branch miss penalty total      : %12d\n"       , branch_miss_penalty_total                     );
        $write("===> ifu stall                      : %12d\n"       , ifu_stall                                     );
        $write("===> lsu stall                      : %12d\n"       , lsu_stall                                     );
        $write("   ===> load stall                  : %12d\n"       , load_stall                                    );
        $write("   ===> store stall                 : %12d\n"       , store_stall                                   );
        $write("===> mul stall                      : %12d\n"       , mul_stall                                     );
        $write("===> div stall                      : %12d\n"       , div_stall                                     );
        $write("===> total penalty                  : %12d\n"       , total_penalty                                 );
        $write("===> branch miss penalty rate       :     %f\n"     , $itor(branch_miss_penalty_total) / $itor(total_penalty));
        $write("===> ifu stall rate                 :     %f\n"     , $itor(ifu_stall) / $itor(total_penalty)       );
        $write("===> lsu stall rate                 :     %f\n"     , $itor(lsu_stall) / $itor(total_penalty)       );
        $write("    ===> load stall rate            :     %f\n"     , $itor(load_stall) / $itor(total_penalty)      );
        $write("    ===> store stall rate           :     %f\n"     , $itor(store_stall) / $itor(total_penalty)     );
        $write("===> mul stall rate                 :     %f\n"     , $itor(mul_stall) / $itor(total_penalty)       );
        $write("===> div stall rate                 :     %f\n"     , $itor(div_stall) / $itor(total_penalty)       );
        $write("===> total estimate cycle           : %12d\n"       , total_estimate_cycle                          );
        $write("===> load instructions              : %12d\n"       , load_insts                                    );
        $write("===> store instructions             : %12d\n"       , store_insts                                   );
        $write("===> IPC (Instructions Per Cycle)   :     %f\n"     , $itor(minstret) / $itor(mcycle)               );
        $write("===> simulation finish!!\n"                                                                         );
        $write("\n"                                                                                                 );
    end

endmodule
/******************************************************************************************/

/* fuction of printing register file */
/******************************************************************************************/
function void rf32_fprint (
    input     int          fd       , // file descriptor
    input     int          instret  , // instruction count
    input     logic [31:0] pc       , // program counter
    input     logic [31:0] ir       , // instruction
    input     logic        rf_we    , // register file write enable
    input     logic  [4:0] rd       , // register file write address
    input     logic [31:0] rf_wdata , // register file write data
    const ref logic [31:0] xreg[0:31] // register file
);

    $fwrite(fd, "%08d %08x %08x\n", instret, pc, ir);
    for (int i=0; i<4; i++) begin
        for (int j=0; j<8; j++) begin
            $fwrite(fd, "%08x", ((i*8+j)==0 ) ? 0 : (rf_we && ((i*8+j)==rd)) ? rf_wdata : xreg[i*8+j]);
            $fwrite(fd, "%s", ((j==7) ? "\n" : " "));
        end
    end

endfunction
/******************************************************************************************/

/* function of printiing spike commit like */
/******************************************************************************************/
function void spike_commit_log (
    input int          fd           ,
    input logic [31:0] hartid       ,
    input logic  [1:0] priv_lvl     ,
    input logic [31:0] pc           ,
    input logic [31:0] ir           ,
    input logic        rf_we        ,
    input logic  [4:0] rd           ,
    input logic [31:0] rf_wdata     ,
    input logic        dbus_re      ,
    input logic [31:0] dbus_raddr   ,
    input logic        dbus_we      ,
    input logic [31:0] dbus_waddr   ,
    input logic [31:0] dbus_wdata   ,
    input logic  [3:0] dbus_wstrb   ,
    input logic        csr_we       ,
    input logic [31:0] csr_waddr    ,
    input logic [31:0] csr_wdata
);

    string       rd_s               ;
    logic  [2:0] dbus_wdata_size    ;
    string       dbus_wdata_s       ;
    string       csr_s              ;
    bit          illegal_csr_write  ;

    if (rd < 10) rd_s = $sformatf("x%0d ", rd);
    else rd_s = $sformatf("x%0d", rd);

    $fwrite(fd, "core%4d: %1d 0x%08x (0x%08x)", hartid, priv_lvl, pc, ir);
    if (|rf_we) begin
        $fwrite(fd, " %s 0x%08x", rd_s, rf_wdata);
    end

    // dbus read
    if (dbus_re) begin
        $fwrite(fd, " mem 0x%08x", dbus_raddr);
    end

    // dbus write
    dbus_wdata_size = 0;
    for (int i=0; i<4; i++) if (dbus_wstrb[i]) dbus_wdata_size++;

    case (dbus_wdata_size)
        3'd1    : dbus_wdata_s  = $sformatf("0x%02x", dbus_wdata[ 7: 0]);
        3'd2    : dbus_wdata_s  = $sformatf("0x%04x", dbus_wdata[15: 0]);
        3'd4    : dbus_wdata_s  = $sformatf("0x%08x", dbus_wdata[31: 0]);
        default : ;
    endcase

    if (dbus_we) begin
        $fwrite(fd, " mem 0x%08x %s", dbus_waddr, dbus_wdata_s);
    end

    // csr write
    illegal_csr_write   = 1'b0;
    case (csr_waddr)
        12'h100: csr_s  = $sformatf("c768_mstatus"                  )   ;
        12'h104: csr_s  = $sformatf("c772_mie"                      )   ;
        12'h105: csr_s  = $sformatf("c%03d_stvec"        , csr_waddr)   ;
        12'h106: csr_s  = $sformatf("c%03d_scounteren"   , csr_waddr)   ;
        12'h140: csr_s  = $sformatf("c%03d_sscratch"     , csr_waddr)   ;
        12'h141: csr_s  = $sformatf("c%03d_sepc"         , csr_waddr)   ;
        12'h142: csr_s  = $sformatf("c%03d_scause"       , csr_waddr)   ;
        12'h143: csr_s  = $sformatf("c%03d_stval"        , csr_waddr)   ;
        12'h144: csr_s  = $sformatf("c836_mip"                      )   ;
        12'h180: csr_s  = $sformatf("c%03d_satp"         , csr_waddr)   ;
        12'h300: csr_s  = $sformatf("c%03d_mstatus"      , csr_waddr)   ;
        12'h302: csr_s  = $sformatf("c%03d_medeleg"      , csr_waddr)   ;
        12'h303: csr_s  = $sformatf("c%03d_mideleg"      , csr_waddr)   ;
        12'h304: csr_s  = $sformatf("c%03d_mie"          , csr_waddr)   ;
        12'h305: csr_s  = $sformatf("c%03d_mtvec"        , csr_waddr)   ;
        12'h306: csr_s  = $sformatf("c%03d_mcounteren"   , csr_waddr)   ;
        12'h312: csr_s  = $sformatf("c%03d_medelegh"     , csr_waddr)   ;
        12'h340: csr_s  = $sformatf("c%03d_mscratch"     , csr_waddr)   ;
        12'h341: csr_s  = $sformatf("c%03d_mepc"         , csr_waddr)   ;
        12'h342: csr_s  = $sformatf("c%03d_mcause"       , csr_waddr)   ;
        12'h343: csr_s  = $sformatf("c%03d_mtval"        , csr_waddr)   ;
        12'h344: csr_s  = $sformatf("c%03d_mip"          , csr_waddr)   ;
        12'h3a0: csr_s  = $sformatf("c%03d_pmpcfg0"      , csr_waddr)   ;
        12'h3b0: csr_s  = $sformatf("c%03d_pmpaddr0"     , csr_waddr)   ;
        12'hb00: csr_s  = $sformatf("c%03d_mcycle"       , csr_waddr)   ;
        12'hb02: csr_s  = $sformatf("c%03d_minstret"     , csr_waddr)   ;
        12'hb80: csr_s  = $sformatf("c%03d_mcycleh"      , csr_waddr)   ;
        12'hb82: csr_s  = $sformatf("c%03d_minstreth"    , csr_waddr)   ;
        12'h320: csr_s  = $sformatf("c%03d_mcountinhibit", csr_waddr)   ;
        default: illegal_csr_write = 1'b1                               ;
    endcase
    if (csr_we && !illegal_csr_write) begin
        $fwrite(fd, " %s 0x%08x", csr_s, csr_wdata);
    end

    $fwrite(fd, "\n");

endfunction
/******************************************************************************************/

`resetall
