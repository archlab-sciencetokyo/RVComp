/*
 * SPDX-License-Identifier: MIT
 * 
 * Copyright (c) 2025 Archlab, Science Tokyo
 */

`resetall
`default_nettype none

`include "rvcom.vh"

/* DDR3/DDR2 memory interface for simulation */
/******************************************************************************************/
module mig_7series_0 #(
`ifdef DDR2 // Nexys
    localparam DRAM_SIZE    = 128*1024*1024     ,
    localparam ADDR_WIDTH   = 27                ,
`else // DDR3, Arty
    localparam DRAM_SIZE    = 256*1024*1024     ,
    localparam ADDR_WIDTH   = 28                ,
`endif
    localparam DATA_WIDTH   = 128               ,
    localparam STRB_WIDTH   = DATA_WIDTH/8
) (
    // Memory interface ports
`ifdef DDR2 // Nexys
    output logic  [12:0] ddr2_addr              ,
    output logic   [2:0] ddr2_ba                ,
    output logic         ddr2_cas_n             ,
    output logic   [0:0] ddr2_ck_n              ,
    output logic   [0:0] ddr2_ck_p              ,
    output logic   [0:0] ddr2_cke               ,
    output logic         ddr2_ras_n             ,
    output logic         ddr2_we_n              ,
    inout  logic  [15:0] ddr2_dq                ,
    inout  logic   [1:0] ddr2_dqs_n             ,
    inout  logic   [1:0] ddr2_dqs_p             ,
    output logic         init_calib_complete    ,
    output logic   [0:0] ddr2_cs_n              ,
    output logic   [1:0] ddr2_dm                ,
    output logic   [0:0] ddr2_odt               ,
`else // DDR3, Arty
    output logic  [13:0] ddr3_addr              ,
    output logic   [2:0] ddr3_ba                ,
    output logic         ddr3_cas_n             ,
    output logic   [0:0] ddr3_ck_n              ,
    output logic   [0:0] ddr3_ck_p              ,
    output logic   [0:0] ddr3_cke               ,
    output logic         ddr3_ras_n             ,
    output logic         ddr3_reset_n           ,
    output logic         ddr3_we_n              ,
    inout  logic  [15:0] ddr3_dq                ,
    inout  logic   [1:0] ddr3_dqs_n             ,
    inout  logic   [1:0] ddr3_dqs_p             ,
    output logic         init_calib_complete    ,
    output logic   [0:0] ddr3_cs_n              ,
    output logic   [1:0] ddr3_dm                ,
    output logic   [0:0] ddr3_odt               ,
`endif
    // Application interface ports
    output logic         ui_clk                 ,
    output logic         ui_clk_sync_rst        ,
    output logic         mmcm_locked            ,
    input  logic         aresetn                ,
    input  logic         app_sr_req             ,
    input  logic         app_ref_req            ,
    input  logic         app_zq_req             ,
    output logic         app_sr_active          ,
    output logic         app_ref_ack            ,
    output logic         app_zq_ack             ,
    // Slave Interface Write Address Ports
    input  logic   [0:0] s_axi_awid             ,
    input  logic  [27:0] s_axi_awaddr           ,
    input  logic   [7:0] s_axi_awlen            ,
    input  logic   [2:0] s_axi_awsize           ,
    input  logic   [1:0] s_axi_awburst          ,
    input  logic   [0:0] s_axi_awlock           , // This is not used in the current mig implementation.
    input  logic   [3:0] s_axi_awcache          , // This is not used in the current mig implementation.
    input  logic   [2:0] s_axi_awprot           , // This is not used in the current mig implementation.
    input  logic   [3:0] s_axi_awqos            ,
    input  logic         s_axi_awvalid          ,
    output logic         s_axi_awready          ,
    // Slave Interface Write Data Ports
    input  logic [127:0] s_axi_wdata            ,
    input  logic  [15:0] s_axi_wstrb            ,
    input  logic         s_axi_wlast            ,
    input  logic         s_axi_wvalid           ,
    output logic         s_axi_wready           ,
    // Slave Interface Write Response Ports
    output logic   [0:0] s_axi_bid              ,
    output logic   [1:0] s_axi_bresp            ,
    output logic         s_axi_bvalid           ,
    input  logic         s_axi_bready           ,
    // Slave Interface Read Address Ports
    input  logic   [0:0] s_axi_arid             ,
    input  logic  [27:0] s_axi_araddr           ,
    input  logic   [7:0] s_axi_arlen            ,
    input  logic   [2:0] s_axi_arsize           ,
    input  logic   [1:0] s_axi_arburst          ,
    input  logic   [0:0] s_axi_arlock           , // This is not used in the current mig implementation.
    input  logic   [3:0] s_axi_arcache          , // This is not used in the current mig implementation.
    input  logic   [2:0] s_axi_arprot           , // This is not used in the current mig implementation.
    input  logic   [3:0] s_axi_arqos            ,
    input  logic         s_axi_arvalid          ,
    output logic         s_axi_arready          ,
    // Slave Interface Read Data Ports
    output logic   [0:0] s_axi_rid              ,
    output logic [127:0] s_axi_rdata            ,
    output logic   [1:0] s_axi_rresp            ,
    output logic         s_axi_rlast            ,
    output logic         s_axi_rvalid           ,
    input  logic         s_axi_rready           ,
    // System Clock Ports
    input  logic         sys_clk_i              ,
    // Reference Clock Ports
    input  logic         clk_ref_i              ,
    input  logic         sys_rst                 
);

    // clock
    bit clk; always #50 clk <= !clk ; // 80 MHz
    assign ui_clk           = clk   ;

    // reset
    initial begin
        init_calib_complete = 1'b0  ;
        ui_clk_sync_rst     = 1'b1  ;
        mmcm_locked         = 1'b0  ;
        #500
        init_calib_complete = 1'b1  ;
        ui_clk_sync_rst     = 1'b0  ;
        mmcm_locked         = 1'b1  ;
    end

    // ram
    localparam OFFSET_WIDTH     = $clog2(DATA_WIDTH/8)          ;
    localparam VALID_ADDR_WIDTH = $clog2(DRAM_SIZE)-OFFSET_WIDTH;
    logic [DATA_WIDTH-1:0] ram [0:2**VALID_ADDR_WIDTH-1];

    wire  [VALID_ADDR_WIDTH-1:0] valid_awaddr   = s_axi_awaddr[VALID_ADDR_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];
    wire  [VALID_ADDR_WIDTH-1:0] valid_araddr   = s_axi_araddr[VALID_ADDR_WIDTH+OFFSET_WIDTH-1:OFFSET_WIDTH];

    assign s_axi_awready    = (!s_axi_bvalid || s_axi_bready)   ;
    assign s_axi_wready     = (!s_axi_bvalid || s_axi_bready)   ;
    assign s_axi_arready    = (!s_axi_rvalid || s_axi_rready)   ;

    always_ff @(posedge clk) begin
        // DRC: design rule check
        if (s_axi_awvalid!=s_axi_wvalid) $fatal(1, "unexpected behavior detected! (s_axi_awvalid!=s_axi_wvalid)");
        if (s_axi_awready!=s_axi_wready) $fatal(1, "unexpected behavior detected! (s_axi_awready!=s_axi_wready)");
        // read
        if (s_axi_arready) begin
            s_axi_rvalid    <= s_axi_arvalid;
            if (s_axi_arvalid) begin
                s_axi_rdata     <= ram[valid_araddr];
            end
        end
        // write
        if (s_axi_wready) begin
            s_axi_bvalid    <= s_axi_wvalid ;
            if (s_axi_wvalid) begin
                for (int i=0; i<STRB_WIDTH; i=i+1) begin
                    if (s_axi_wstrb[i]) ram[valid_awaddr][8*i+:8] <= s_axi_wdata[8*i+:8];
                end
            end
        end
    end

endmodule

`resetall
