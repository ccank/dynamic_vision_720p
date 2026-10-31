// ddr3_top.v
// Wrapper: MIG + 64-slot ring (video one write, two reads) + pack/unpack FIFOs,
// and (mode 2) the per-pixel EVM temporal-state path.
//   rddata      : current frame pixels (display / EVM)
//   rddata_dly  : delayed frame pixels (extraction), delay set by dly_frames
//   dly_ready   : delayed channel valid (enough frames written since power-up)
// Mode 2 exchanges the EVM state {m,q} through evm_state_path; the state region
// sits after the 64 video slots in DDR. MIG physical interface is unchanged.

//==============================================================================
// File        : ddr3_top.v
// Module      : ddr3_top
// Description :
//   DDR3 subsystem wrapper. It integrates the MIG IP, the 64-slot ring scheduler and the
//   pack/unpack FIFOs. In this build the EVM DDR state path is tied off because all temporal
//   state is kept in on-chip BRAM.
//==============================================================================
module ddr3_top(
    input              sys_clk_i,
    input              clk_ref_i,
    input              rst_n,
    input   [28:0]     app_addr_rd_min,
    input   [28:0]     app_addr_rd_max,
    input   [9:0]      rd_bust_len,
    input   [28:0]     app_addr_wr_min,
    input   [28:0]     app_addr_wr_max,
    input   [9:0]      wr_bust_len,
    inout   [63:0]     ddr3_dq,
    inout   [7:0]      ddr3_dqs_n,
    inout   [7:0]      ddr3_dqs_p,
    output  [14:0]     ddr3_addr,
    output  [2:0]      ddr3_ba,
    output             ddr3_ras_n,
    output             ddr3_cas_n,
    output             ddr3_we_n,
    output             ddr3_reset_n,
    output  [0:0]      ddr3_ck_p,
    output  [0:0]      ddr3_ck_n,
    output  [0:0]      ddr3_cke,
    output  [0:0]      ddr3_cs_n,
    output  [7:0]      ddr3_dm,
    output  [0:0]      ddr3_odt,
    input              ddr3_read_valid,
    input              ddr3_pingpang_en,
    input              wr_clk,
    input              rd_clk,
    input              wr_en,
    input   [15:0]     wrdata,
    input              rdata_req,
    input              rd_load,
    input              wr_load,
    input   [5:0]      dly_frames,
    output  [15:0]     rddata,
    output  [15:0]     rddata_dly,
    output             init_calib_complete,
    output             dly_ready,
    // mode-2 EVM temporal state (algorithm domain = rd_clk)
    input              evm_en,
    input              st_wr_en,        // new-state valid, one per active pixel
    input   [31:0]     st_wr_din,       // {m_new,q_new}
    output  [31:0]     st_rd_dout,      // old state {m_prev,q_prev}
    input              st_rd_consume,   // p_vld: consume one old state
    output             st_rd_empty,
    output  [10:0]     st_rd_level
);
//wire define
wire                  ui_clk;
wire [28:0]           app_addr;
wire [2:0]            app_cmd;
wire                  app_en;
wire                  app_rdy;
wire [511:0]          app_rd_data;
wire                  app_rd_data_end;
wire                  app_rd_data_valid;
wire [511:0]          app_wdf_data;
wire                  app_wdf_end;
wire [63:0]           app_wdf_mask;
wire                  app_wdf_rdy;
wire                  app_sr_active;
wire                  app_ref_ack;
wire                  app_zq_ack;
wire                  app_wdf_wren;
wire                  ui_clk_sync_rst;
wire                  wren_cur, wren_dly;
wire [15:0]           wfifo_rcount;
wire [15:0]           wcount_cur, wcount_dly;
// packed video write word (EVM state path removed in the D1 BRAM build)
wire [511:0]          wfifo_dout;

//ring controller: video one write + two reads (state path tied off)
ddr3_ring_rw u_ddr3_rw(
    .ui_clk             (ui_clk),
    .ui_clk_sync_rst    (ui_clk_sync_rst),
    .init_calib_complete(init_calib_complete),
    .app_rdy            (app_rdy),
    .app_wdf_rdy        (app_wdf_rdy),
    .app_rd_data_valid  (app_rd_data_valid),
    .wfifo_rcount       (wfifo_rcount),
    .rfifo_wcount_cur   (wcount_cur),
    .rfifo_wcount_dly   (wcount_dly),
    .rd_load            (rd_load),
    .wr_load            (wr_load),
    .frame_addr_size    (app_addr_rd_max),
    .burst_len          (rd_bust_len[7:0]),
    .dly_frames         (dly_frames),
    .ddr3_read_valid    (ddr3_read_valid),
    // D1 BRAM build keeps ALL temporal state on-chip; the DDR state path is
    // disabled: never enter the state scheduling branches, pop the video write
    // FIFO on every write, and leave the state FIFO controls unconnected.
    .evm_en             (1'b0),
    .st_wfifo_rcount    (9'd0),
    .st_rfifo_wcount    (11'd0),
    .st_wfifo_rden      (),
    .st_rfifo_wren      (),
    .st_wr_sel          (),
    .rfifo_wren_cur     (wren_cur),
    .rfifo_wren_dly     (wren_dly),
    .app_addr           (app_addr),
    .app_en             (app_en),
    .app_wdf_wren       (app_wdf_wren),
    .app_wdf_end        (app_wdf_end),
    .app_cmd            (app_cmd),
    .dly_ready          (dly_ready)
);

//MIG IP
mig_7series_0 u_mig_7series_0 (
    .ddr3_addr           (ddr3_addr),
    .ddr3_ba             (ddr3_ba),
    .ddr3_cas_n          (ddr3_cas_n),
    .ddr3_ck_n           (ddr3_ck_n),
    .ddr3_ck_p           (ddr3_ck_p),
    .ddr3_cke            (ddr3_cke),
    .ddr3_ras_n          (ddr3_ras_n),
    .ddr3_reset_n        (ddr3_reset_n),
    .ddr3_we_n           (ddr3_we_n),
    .ddr3_dq             (ddr3_dq),
    .ddr3_dqs_n          (ddr3_dqs_n),
    .ddr3_dqs_p          (ddr3_dqs_p),
    .ddr3_cs_n           (ddr3_cs_n),
    .ddr3_dm             (ddr3_dm),
    .ddr3_odt            (ddr3_odt),
    .app_addr            (app_addr),
    .app_cmd             (app_cmd),
    .app_en              (app_en),
    .app_wdf_data        (app_wdf_data),
    .app_wdf_end         (app_wdf_end),
    .app_wdf_wren        (app_wdf_wren),
    .app_rd_data         (app_rd_data),
    .app_rd_data_end     (app_rd_data_end),
    .app_rd_data_valid   (app_rd_data_valid),
    .init_calib_complete (init_calib_complete),
    .app_rdy             (app_rdy),
    .app_wdf_rdy         (app_wdf_rdy),
    .app_sr_req          (1'b0),
    .app_ref_req         (1'b0),
    .app_zq_req          (1'b0),
    .app_sr_active       (app_sr_active),
    .app_ref_ack         (app_ref_ack),
    .app_zq_ack          (app_zq_ack),
    .ui_clk              (ui_clk),
    .ui_clk_sync_rst     (ui_clk_sync_rst),
    .app_wdf_mask        (64'b0),
    .sys_clk_i           (sys_clk_i),
    .clk_ref_i           (clk_ref_i),
    .sys_rst             (rst_n)
);

//pack/unpack FIFOs (current + delayed unpack)
ddr3_fifo_ctrl u_ddr3_fifo_ctrl(
    .rst_n              (rst_n & init_calib_complete),
    .wr_clk             (wr_clk),
    .rd_clk             (rd_clk),
    .ui_clk             (ui_clk),
    .wr_en              (wr_en),
    .wrdata             (wrdata),
    .rfifo_din          (app_rd_data),
    .rdata_req          (rdata_req),
    .rfifo_wren         (wren_cur),
    .rfifo_wren_dly     (wren_dly),
    // state path removed: every MIG write is a video write
    .wfifo_rden         (app_wdf_wren),
    .rd_load            (rd_load),
    .wr_load            (wr_load),
    .wfifo_dout         (wfifo_dout),
    .rfifo_wcount       (wcount_cur),
    .rfifo_wcount_dly   (wcount_dly),
    .wfifo_rcount       (wfifo_rcount),
    .rddata             (rddata),
    .rddata_dly         (rddata_dly)
);

// D1 BRAM build: the EVM temporal state {m,q,z} lives entirely in BLOCK RAM
// inside dynamic_enhance_720p, so the DDR state path (evm_state_path) and the
// diagnostics ILA (evm_diag) are removed. The MIG write data is always the
// packed video word. State-path port outputs are held at safe defaults.
assign app_wdf_data = wfifo_dout;
assign st_rd_dout   = 32'd0;
assign st_rd_empty  = 1'b1;
assign st_rd_level  = 11'd0;

endmodule
