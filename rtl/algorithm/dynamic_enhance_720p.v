`timescale 1ns/1ps
//==============================================================================
// dynamic_enhance_720p.v  (mode 2, paper-faithful Laplacian pyramid EVM, D1)
//
// Linear Eulerian Video Magnification for 720P60 RGB565, all temporal state on
// BLOCK RAM (no DDR3 state path). Follows the FPGA-EVM paper spatial pyramid:
//
//   1. RGB565 -> RGB888 -> luma Y.
//   2. Spatial: separable 5x5 Gaussian G=(1/16)[1 4 6 4 1] at FULL resolution,
//      then 2:1 sub-sample -> D1 layer 640x360 (the temporal band-pass is done
//      at D1 only; the highest-frequency L0 residual is NOT magnified, so
//      static high-contrast edges / sensor noise are never amplified).
//   3. Per-D1-pixel temporal band-pass (BRAM), Fs = 60 Hz:
//         fast low-pass m[t] = cl*m[t-1] + (1-cl)*p[t]   (~12 Hz)
//         slow low-pass q[t] = ch*q[t-1] + (1-ch)*m[t]   (~0.5 Hz)
//         band-pass     z    = m[t]-q[t]  (0.5..12 Hz)
//      A scene change (|p-m| over threshold) snaps m=q=p, z=0.
//   4. z is kept in a single simple-DP D1 frame. The display read runs ~4 D1
//      cells ahead of the S3 write, so it always sees the previous, fully
//      finished frame (no ping-pong; streams like the paper cascade). The read
//      address changes every 2 cols / 2 rows, giving nearest-neighbour 2x up-
//      sampling back to 1280x720 (each 2x2 block shares one z).
//   5. Output = clamp( FULL-resolution original RGB + ALPHA*z_up ). The static
//      image stays 1x1 sharp (L0 untouched); only the band-passed motion of the
//      object's D1 silhouette flickers.
//
// D1 update is a 4-stage fully pipelined read-modify-write clocked by the D1
// valid pulse (one D1 pixel every 2 pclk on even rows, none on odd rows); three
// extra flush pulses at the end of each frame drain the pipeline tail.
//
// BRAM: m/q Q4 12-bit single frame (one 24-bit simple-DP) + z 8-bit signed
// single frame (one simple-DP) at 640*360 = 230400 cells.
//==============================================================================

//==============================================================================
// File        : dynamic_enhance_720p.v
// Module      : dynamic_enhance_720p
// Description :
//   Eulerian video magnification (EVM) at the D1 pyramid layer: spatial Gaussian blur plus
//   a temporal IIR band-pass filter amplify subtle changes. RGB565 in, RGB888 out; all m/q/z
//   temporal state is stored in on-chip block RAM.
//==============================================================================
module dynamic_enhance_720p(
    input               pclk,          // = clk_75m
    input               rst_n,
    input               cur_hsync,
    input               cur_vsync,     // active high (top inverts drv_vs)
    input               cur_de,
    input       [15:0]  cur_rgb565,
    input               in_valid,      // delayed channel ready (dly_ready)
    output              out_hsync,
    output              out_vsync,
    output              out_de,
    output      [23:0]  out_rgb,
    output reg          alarm,       // 1 = large-scale blinking alarm, 0 = normal
    input       [2:0]   sens_level   // 1(most sensitive)~5(least), default 3
);
//------------------------------------------------ parameters
localparam HW    = 1280;
localparam HTOTAL = 1650; // full line clocks = 40+220+1280+110
localparam D1W   = 640;
localparam D1H   = 360;
localparam ND1   = 230400; // D1W*D1H
// IIR coefficients, Q8 (state is Q4: Y<<4)
localparam [8:0]  CL_Q = 9'd73;   // fast low-pass (~12 Hz)
localparam [8:0]  OML  = 9'd183;  // 1-CL
localparam [8:0]  CH_Q = 9'd243;  // slow low-pass (~0.5 Hz)
localparam [8:0]  OMH  = 9'd13;   // 1-CH
localparam signed [13:0] ALPHA = 14'sd20;
localparam signed [12:0] D_RST = 13'sd48;  // Q4 scene-change threshold (~3 luma)
// Magnitude dead-zone (luma units) on the band-pass output: |z| <= Z_DEAD is
// sensor/RGB565 quantization grain and is forced to 0. After the three-stage
// spatial Gaussian the residual flecks sit at |z| <= 1; dead-zone 1 removes
// them while keeping the motion (2 was too aggressive and dimmed real motion).
localparam [7:0] Z_DEAD = 8'd2;

//------------------------------------------------ run gating (4x4 golden)
reg       vs_d, iv1, iv2;
reg [3:0] vfcnt;
reg       run;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin vs_d<=0; iv1<=0; iv2<=0; vfcnt<=0; run<=0; end
    else begin
        vs_d <= cur_vsync;
        iv1  <= in_valid;
        iv2  <= iv1;
        if(cur_vsync && !vs_d) begin
            if(iv2 && (vfcnt<4'd15)) vfcnt <= vfcnt + 1'b1;
            run <= (vfcnt >= 4'd3);
        end
    end
end
reg run_d, lp_init;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin run_d<=0; lp_init<=0; end
    else begin
        run_d <= run;
        if(run && !run_d) lp_init <= 1'b1;
        else if(cur_vsync && !vs_d) lp_init <= 1'b0;
    end
end

//------------------------------------------------ RGB565 -> Y
wire [23:0] rgb888_in = cur_de ? {cur_rgb565[15:11],3'b0,
                                  cur_rgb565[10:5],2'b0,
                                  cur_rgb565[4:0],3'b0} : 24'd0;
wire [7:0] ri_ = rgb888_in[23:16];
wire [7:0] gi_ = rgb888_in[15:8];
wire [7:0] bi_ = rgb888_in[7:0];
wire [15:0] ynum = ri_*8'd77 + gi_*8'd150 + bi_*8'd29;
wire [7:0]  Y    = ynum[15:8];

//------------------------------------------------ vertical 5-tap Gaussian
wire [7:0] yl1, yl2, yl3, yl4;
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL)) u_yl1(.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(Y),  .dout(yl1));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL)) u_yl2(.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(yl1),.dout(yl2));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL)) u_yl3(.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(yl2),.dout(yl3));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL)) u_yl4(.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(yl3),.dout(yl4));
// center is yl2 (2 lines before current); G=(1/16)[1 4 6 4 1]
wire [11:0] vnum = yl4 + (yl3<<2) + (yl2<<2) + (yl2<<1) + (yl1<<2) + Y;
wire [7:0]  V    = vnum[11:4];
// delay control/rgb by 2 lines using the SAME 2-stage cascade
wire [2:0]  ctl_c1, ctl_v;
seg_lb #(.W(3),.AW(11),.LEN(HTOTAL)) u_cc1(.clk(pclk),.rst_n(rst_n),.en(1'b1),
    .din({cur_de,cur_hsync,cur_vsync}),.dout(ctl_c1));
seg_lb #(.W(3),.AW(11),.LEN(HTOTAL)) u_cc2(.clk(pclk),.rst_n(rst_n),.en(1'b1),
    .din(ctl_c1),.dout(ctl_v));
wire [15:0] rgb_c1, rgb_v;
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL)) u_rc1(.clk(pclk),.rst_n(rst_n),.en(1'b1),
    .din(cur_rgb565),.dout(rgb_c1));
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL)) u_rc2(.clk(pclk),.rst_n(rst_n),.en(1'b1),
    .din(rgb_c1),.dout(rgb_v));

//------------------------------------------------ horizontal 5-tap Gaussian
reg [7:0]  vd1, vd2, vd3, vd4;
reg [2:0]  cd1, cd2;
reg [15:0] rdd1, rdd2;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin vd1<=0;vd2<=0;vd3<=0;vd4<=0; cd1<=0;cd2<=0; rdd1<=0;rdd2<=0; end
    else begin
        vd1<=V;vd2<=vd1;vd3<=vd2;vd4<=vd3;
        cd1<=ctl_v;cd2<=cd1;
        rdd1<=rgb_v;rdd2<=rdd1;
    end
end
// center is vd2 (2 valid pixels before V)
wire [11:0] hnum = vd4 + (vd3<<2) + (vd2<<2) + (vd2<<1) + (vd1<<2) + V;
wire [7:0]  p    = hnum[11:4];   // full-resolution Gaussian luma
wire [2:0]  ctl_s = cd2;          // {de,hs,vs} at Gaussian center
wire [15:0] rgb_s = rdd2;         // full-resolution ORIGINAL at Gaussian center
// (first-stage valid pv is unused; the second-stage pv2 drives sub-sampling)

//==================================== second 5x5 Gaussian stage (cascade) ====
// Cascading two [1 4 6 4 1]/16 kernels gives an effective ~9x9 kernel
// (sigma ~1.414), a stronger spatial anti-alias so sensor / RGB565
// quantization high-frequency noise is removed before the temporal band-pass.
// ONLY the luma used for magnification is smoothed; the displayed original
// RGB is merely delayed and stays full-resolution sharp. The extra line
// buffers use distributed LUTRAM (the device has abundant LUT, tight BRAM).
wire [7:0]  pL1, pL2, pL3, pL4;
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_pL1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(p),   .dout(pL1));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_pL2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(pL1), .dout(pL2));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_pL3
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(pL2), .dout(pL3));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_pL4
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(pL3), .dout(pL4));
wire [11:0] vnum2 = pL4 + (pL3<<2) + (pL2<<2) + (pL2<<1) + (pL1<<2) + p;
wire [7:0]  V2    = vnum2[11:4];

// ctl / original rgb delayed two more lines to align with stage-2 center
wire [2:0]  ctl_v2, ctl_v2b;
wire [15:0] rgb_v2, rgb_v2b;
seg_lb #(.W(3), .AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_cs1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(ctl_s), .dout(ctl_v2));
seg_lb #(.W(3), .AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_cs2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(ctl_v2),.dout(ctl_v2b));
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_rs1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(rgb_s), .dout(rgb_v2));
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_rs2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(rgb_v2),.dout(rgb_v2b));

// second-stage horizontal 5-tap
reg [7:0]  h1, h2, h3, h4;
reg [2:0]  ch1, ch2;
reg [15:0] rh1, rh2;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin h1<=0;h2<=0;h3<=0;h4<=0; ch1<=0;ch2<=0; rh1<=0;rh2<=0; end
    else begin
        h1<=V2;h2<=h1;h3<=h2;h4<=h3;
        ch1<=ctl_v2b;ch2<=ch1;
        rh1<=rgb_v2b;rh2<=rh1;
    end
end
wire [11:0] hnum2 = h4 + (h3<<2) + (h2<<2) + (h2<<1) + (h1<<2) + V2;
wire [7:0]  P2     = hnum2[11:4];   // stage-2 smoothed luma (~9x9 equivalent)
wire [2:0]  ctl_s2 = ch2;
wire [15:0] rgb_s2 = rh2;
wire        pv2    = ch2[2];        // stage-2 valid (1280x720)

//==================================== third 5x5 Gaussian stage (cascade) ====
// Three cascaded [1 4 6 4 1]/16 -> effective ~13x13. Further suppresses the
// residual sensor / RGB565 grain that leaks into the temporal band-pass and
// then gets magnified by ALPHA. Only the luma used for magnification is
// smoothed; the displayed original RGB is merely delayed and stays sharp.
wire [7:0]  tL1, tL2, tL3, tL4;
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_tL1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(P2),  .dout(tL1));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_tL2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(tL1), .dout(tL2));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_tL3
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(tL2), .dout(tL3));
seg_lb #(.W(8),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_tL4
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(tL3), .dout(tL4));
// center is tL2
wire [11:0] vnum3 = tL4 + (tL3<<2) + (tL2<<2) + (tL2<<1) + (tL1<<2) + P2;
wire [7:0]  V3    = vnum3[11:4];

// ctl / original rgb delayed two more lines to align with stage-3 center
wire [2:0]  ctl_tv, ctl_tvb;
wire [15:0] rgb_tv, rgb_tvb;
seg_lb #(.W(3), .AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_ct1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(ctl_s2), .dout(ctl_tv));
seg_lb #(.W(3), .AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_ct2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(ctl_tv), .dout(ctl_tvb));
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_rt1
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(rgb_s2), .dout(rgb_tv));
seg_lb #(.W(16),.AW(11),.LEN(HTOTAL),.PRIM("distributed"),.RL(1)) u_rt2
    (.clk(pclk),.rst_n(rst_n),.en(1'b1),.din(rgb_tv), .dout(rgb_tvb));

// third-stage horizontal 5-tap
reg [7:0]  tt1, tt2, tt3, tt4;
reg [2:0]  ct1, ct2;
reg [15:0] tr1, tr2;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin tt1<=0;tt2<=0;tt3<=0;tt4<=0; ct1<=0;ct2<=0; tr1<=0;tr2<=0; end
    else begin
        tt1<=V3;tt2<=tt1;tt3<=tt2;tt4<=tt3;
        ct1<=ctl_tvb;ct2<=ct1;
        tr1<=rgb_tvb;tr2<=tr1;
    end
end
wire [11:0] hnum3 = tt4 + (tt3<<2) + (tt2<<2) + (tt2<<1) + (tt1<<2) + V3;
wire [7:0]  P3     = hnum3[11:4];   // final smoothed luma (~13x13 equivalent)
wire [2:0]  ctl_s3 = ct2;
wire [15:0] rgb_s3 = tr2;
wire        pv3    = ct2[2];        // final Gaussian valid (1280x720)
wire        pv3_g  = pv3 & run;

//------------------------------------------------ Gaussian center coordinates
// pv2 is asserted for exactly 1280 px/line x 720 lines; the first pv2 pixel
// is the Gaussian center (0,0).
reg [10:0] gx;
reg [9:0]  gy;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin gx<=11'd0; gy<=10'd0; end
    else if(pv3) begin
        if(gx==11'd1279) begin
            gx <= 11'd0;
            gy <= (gy==10'd719) ? 10'd0 : gy + 10'd1;
        end else gx <= gx + 11'd1;
    end
end

//------------------------------------------------ 2:1 sub-sample -> D1
// D1 pixel at even row / even col of the final Gaussian center; grid 640x360.
wire        d1_en   = pv3_g & ~gx[0] & ~gy[0];
wire [11:0] pQ4    = {P3,4'b0};                 // Q4 luma (smoothed)
wire [17:0] d1_addr = gy[9:1]*D1W + gx[10:1]; // 0..230399

// end-of-frame flush: drain the 4-stage pipeline tail (last 3 D1 pixels)
reg [1:0] fcnt;
reg       flushing;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin flushing<=0; fcnt<=0; end
    else if(!run) begin flushing<=0; fcnt<=0; end
    else if(d1_en && d1_addr==(ND1-1)) begin flushing<=1; fcnt<=2'd3; end
    else if(flushing) begin
        if(fcnt==2'd1) flushing<=0;
        fcnt <= fcnt - 1'b1;
    end
end
wire pe = d1_en | flushing;   // pipeline advance
reg  pe_d;
always @(posedge pclk) pe_d <= pe;

//------------------------------------------------ D1 temporal state memory
// m/q: Q4 12-bit each, single frame, simple dual-port (B read = old state).
// The u_mq instance is placed AFTER the S3 stage (below), where all pipeline
// write signals are declared; only the read wires are declared here for S1.
wire [23:0] mq_dout;
wire [11:0] m_prev = mq_dout[23:12];
wire [11:0] q_prev = mq_dout[11:0];

//------------------------------------------------ D1 pipeline
// S0: latch p / address (read address d1_addr is presented combinationally;
//     the old state is on mq_dout one pclk later, captured at S1).
reg [11:0] p0;
reg [17:0] a0;
reg        v0;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin p0<=0; a0<=0; v0<=0; end
    else if(pe) begin
        v0 <= d1_en;   // flush cycles carry no new D1 pixel
        p0 <= pQ4;
        a0 <= d1_addr;
    end
end

// S1: capture old m/q (latency 1), carry p/address
reg [11:0] p1, m1, q1;
reg [17:0] a1;
reg        v1;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin p1<=0;m1<=0;q1<=0;a1<=0;v1<=0; end
    else if(pe) begin
        v1 <= v0;
        m1 <= m_prev;
        q1 <= q_prev;
        p1 <= p0;
        a1 <= a0;
    end
end

// S2: fast low-pass m, scene-change test
wire signed [12:0] p1Q  = $signed({1'b0,p1});
wire signed [12:0] m1Q  = $signed({1'b0,m1});
wire signed [13:0] dev  = p1Q - m1Q;
wire               big1 = lp_init || (dev > D_RST) || (dev < -D_RST);
wire signed [21:0] mt1  = $signed({1'b0,CL_Q}) * m1Q;
wire signed [21:0] mt2  = $signed({1'b0,OML})  * p1Q;
wire signed [21:0] mts  = mt1 + mt2;
wire               mtsx = mts[21];
wire [21:0]        mtax = mtsx ? -mts : mts;
wire [13:0]        mtqx = (mtax + 22'd128) >>> 8;
wire signed [12:0] mtr  = mtsx ? -mtqx[12:0] : mtqx[12:0];
wire [11:0]        m_new = big1 ? p1 : mtr[11:0];
reg [11:0] m2, q2;
reg [17:0] a2;
reg        v2, big2;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin m2<=0;q2<=0;a2<=0;v2<=0;big2<=0; end
    else if(pe) begin
        v2<=v1; big2<=big1;
        m2<=m_new; q2<=q1; a2<=a1;
    end
end

// S3: slow low-pass q, band-pass z = m - q (quantise to signed 8-bit Y)
wire signed [12:0] m2Q  = $signed({1'b0,m2});
wire signed [12:0] q2Q  = $signed({1'b0,q2});
wire signed [21:0] qt1  = $signed({1'b0,CH_Q}) * q2Q;
wire signed [21:0] qt2  = $signed({1'b0,OMH})  * m2Q;
wire signed [21:0] qts  = qt1 + qt2;
wire               qtsx = qts[21];
wire [21:0]        qtax = qtsx ? -qts : qts;
wire [13:0]        qtqx = (qtax + 22'd128) >>> 8;
wire signed [12:0] qtr  = qtsx ? -qtqx[12:0] : qtqx[12:0];
wire signed [12:0] q_new = big2 ? m2Q : qtr;
wire signed [13:0] zQ4   = m2Q - q_new;
wire               zsx   = zQ4[13];
wire [13:0]        zax   = zsx ? -zQ4 : zQ4;
// nearest quantisation Q4->Y (|z|<0.5 Y naturally becomes 0), clamp +-127
wire [7:0]         zqi   = (zax + 14'd8) >>> 4;
wire [7:0]         zmag  = (zqi > 8'd127) ? 8'd127 : zqi;
wire signed [7:0]  z8    = zsx ? -$signed({1'b0,zmag}) : $signed({1'b0,zmag});
// magnitude dead-zone: kill residual quantization/sensor grain (|z| <= Z_DEAD)
wire signed [7:0]  z8d   = (zmag <= Z_DEAD) ? 8'sd0 : z8;
reg [11:0] wm, wq;
reg [7:0]  wz;
reg [17:0] wa;
reg        v3;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin wm<=0;wq<=0;wz<=0;wa<=0;v3<=0; end
    else if(pe) begin
        v3<=v2;
        wm<=m2;
        wq<=q_new[11:0];
        wz<=big2 ? 8'sd0 : z8d;
        wa<=a2;
    end
end
// write one pclk after the S3 latch (odd column / flush gap), once per D1 cell
wire w_we = pe_d & v3;

//------------------------------------------------ m/q state BRAM (simple DP)
// Port B reads the OLD state of the D1 cell latched in S0 (address a0), with
// latency 1 so it is ready exactly when S1 captures it; a0 is held across the
// odd-row gap (no D1 pixel) so end-of-row blocks are not misread.
xpm_memory_sdpram #(
    .ADDR_WIDTH_A(18),.ADDR_WIDTH_B(18),.AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(24),.CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),.ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),.MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("false"),.MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(ND1*24),.MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(24),.READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),.RST_MODE_A("SYNC"),.RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),.USE_EMBEDDED_CONSTRAINT(0),.USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),.WRITE_DATA_WIDTH_A(24),
    .WRITE_MODE_B("READ_FIRST"),.WRITE_PROTECT(1)
) u_mq (
    .clka(pclk),.ena(1'b1),.wea(w_we),.addra(wa),.dina({wm,wq}),
    .clkb(pclk),.enb(1'b1),.rstb(1'b0),.addrb(a0),.doutb(mq_dout),
    .dbiterrb(),.sbiterrb(),.injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.sleep(1'b0)
);

//------------------------------------------------ z band-pass state BRAM (single frame)
// Simple dual-port: port A writes the freshly computed z one pclk after S3;
// port B reads the display's current D1 cell (d1_addr). The write stream runs
// ~4 D1 cells BEHIND the read stream (S0..S3 latency; odd rows and blanking
// freeze both), so the read address always leads the write address and returns
// the PREVIOUS, fully finished frame's z. A single frame therefore suffices --
// no ping-pong (matches the paper cascade that streams z within one frame).
// Nearest 2x up-sample is implicit: d1_addr changes every 2 cols / 2 rows, so
// the 4 pixels of each 2x2 block read the same z.
wire signed [7:0] z_dB;
xpm_memory_sdpram #(
    .ADDR_WIDTH_A(18),.ADDR_WIDTH_B(18),.AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(8),.CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),.ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),.MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("false"),.MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(ND1*8),.MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(8),.READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),.RST_MODE_A("SYNC"),.RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),.USE_EMBEDDED_CONSTRAINT(0),.USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),.WRITE_DATA_WIDTH_A(8),
    .WRITE_MODE_B("READ_FIRST"),.WRITE_PROTECT(1)
) u_z (
    .clka(pclk),.ena(1'b1),.wea(w_we),.addra(wa),.dina(wz),
    .clkb(pclk),.enb(1'b1),.rstb(1'b0),.addrb(d1_addr),.doutb(z_dB),
    .dbiterrb(),.sbiterrb(),.injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.sleep(1'b0)
);
wire signed [7:0] zprev = z_dB;

//------------------------------------------------ display stage 1
// Final Gaussian center pixel: rgb_s3 (full-res original), ctl_s3, zprev.
reg [15:0] rgb_q;
reg [2:0]  ctl_q;
reg signed [7:0] z_q;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin rgb_q<=0; ctl_q<=0; z_q<=0; end
    else begin
        rgb_q <= rgb_s3;
        ctl_q <= ctl_s3;
        z_q   <= run ? zprev : 8'sd0;
    end
end

//------------------------------------------------ display stage 2
// dead-zone on display path too: kills residual high-freq grain without extra pipeline stage
wire signed [7:0] z_disp = (z_q > 8'sd0) ?
                            ((z_q > $signed({1'b0,8'd2})) ? z_q : 8'sd0) :
                            ((-z_q > $signed({1'b0,8'd2})) ? z_q : 8'sd0);
wire signed [15:0] az = z_disp * ALPHA;   // 20 * z (luma units), signed
wire [23:0] rgb888_q = ctl_q[2] ? {rgb_q[15:11],3'b0,rgb_q[10:5],2'b0,rgb_q[4:0],3'b0}
                                : 24'd0;
wire signed [15:0] sR = $signed({1'b0,rgb888_q[23:16]}) + az;
wire signed [15:0] sG = $signed({1'b0,rgb888_q[15:8]})  + az;
wire signed [15:0] sB = $signed({1'b0,rgb888_q[7:0]})   + az;
wire [7:0] oR = (sR<0)?8'd0:((sR>255)?8'd255:sR[7:0]);
wire [7:0] oG = (sG<0)?8'd0:((sG>255)?8'd255:sG[7:0]);
wire [7:0] oB = (sB<0)?8'd0:((sB>255)?8'd255:sB[7:0]);

reg [23:0] rgb_o;
reg [2:0]  ctl_o;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin rgb_o<=0; ctl_o<=0; end
    else begin
        rgb_o <= ctl_q[2] ? {oR,oG,oB} : 24'd0;
        ctl_o <= ctl_q;
    end
end
assign out_rgb   = rgb_o;
assign out_de    = ctl_o[2];
assign out_hsync = ctl_o[1];
assign out_vsync = ctl_o[0];

//------------------------------------------------ blinking alarm
// 2-D block-cluster detector (robust to broken / diagonal motion edges).
// Frame is split into an 8x8 grid; each cell counts hot pixels (|z_q|>Z_HOT).
// A cell is "active" once its hot count exceeds BLK_HOT. Scattered speckle never
// fills a single cell, but a real connected blinking region -- even diagonal or
// with intermittent edges -- lights up several cells. >= ALARM_CELLS active cells
// in one frame -> alarm (2 LEDs).
localparam [6:0]  ALARM_CELLS= 7'd2;    // >=2 active cells -> alarm
localparam [3:0]  STREAK     = 4'd2;    // 2 consecutive frames -> reject speckle

// Sensitivity 1~5: level 1 = most sensitive (lowest thresholds), 5 = least.
// Map: Z_HOT  1->1 2->2 3->2 4->3 5->4
//      BLK_HOT 1->120 2->220 3->300 4->420 5->560
reg [7:0]  z_hot;
reg [9:0]  blk_hot;
always @(*) begin
    case(sens_level)
        3'd1: begin z_hot=8'd1; blk_hot=10'd120; end
        3'd2: begin z_hot=8'd2; blk_hot=10'd220; end
        3'd4: begin z_hot=8'd3; blk_hot=10'd420; end
        3'd5: begin z_hot=8'd4; blk_hot=10'd560; end
        default: begin z_hot=8'd2; blk_hot=10'd300; end
    endcase
end

wire signed [8:0] zabs = z_disp[7] ? (9'sd0 - z_disp) : {1'b0, z_disp};
wire              hot  = ctl_q[2] && in_valid && (zabs >= $signed({1'b0,z_hot}));

// pixel coordinates in active video
reg [10:0] px, py;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin px <= 11'd0; py <= 11'd0; end
    else if(ctl_q[2]) px <= px + 1'b1;
    else if(px != 11'd0) begin
        px <= 11'd0;
        py <= (py < 11'd719) ? py + 1'b1 : 11'd0;
    end
end
wire [5:0] cell_idx = {py[9:7], px[9:7]};   // 3-bit row *8 + 3-bit col

// per-cell hot counters -- single always block to avoid multi-driver
reg [9:0] blk_cnt [0:63];

// at VS rising edge sweep all 64 cells: count active, reset, latch;
// otherwise accumulate hot pixels (scanning runs during VS blanking, no overlap)
reg        vs_q_d;
reg        scanning;
reg [5:0]  scan_idx;
reg [6:0]  active_cnt;
reg [3:0]  streak;
integer k;

// Single write port for the blk_cnt array: combinational logic resolves the
// ONLY write that may happen this cycle, so the flattened reg array gets one
// write-enable decode instead of two competing variable-index drivers (MDRV).
reg        blk_we;
reg [5:0]  blk_waddr;
reg [9:0]  blk_wdin;
always @(*) begin
    blk_we    = 1'b0;
    blk_waddr = 6'd0;
    blk_wdin  = 10'd0;
    if(scanning) begin
        // sweep: clear the cell currently being scanned
        blk_we    = 1'b1;
        blk_waddr = scan_idx;
        blk_wdin  = 10'd0;
    end else if(hot) begin
        // accumulate one hot pixel into its cell
        blk_we    = 1'b1;
        blk_waddr = cell_idx;
        blk_wdin  = blk_cnt[cell_idx] + 1'b1;
    end
end

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        vs_q_d    <= 1'b0;
        scanning  <= 1'b0;
        scan_idx  <= 6'd0;
        active_cnt<= 7'd0;
        streak    <= 4'd0;
        alarm     <= 1'b0;
        for(k=0;k<64;k=k+1) blk_cnt[k] <= 10'd0;
    end else begin
        vs_q_d <= ctl_q[0];
        if(ctl_q[0] && !vs_q_d) begin        // frame start: sweep previous frame
            scanning   <= 1'b1;
            scan_idx   <= 6'd0;
            active_cnt <= 7'd0;
        end else if(scanning) begin
            if(scan_idx == 6'd63) begin
                // live sum: active_cnt so far + this last cell (non-blocking
                // active_cnt would not be visible this cycle)
                scanning <= 1'b0;
                if((active_cnt + (blk_cnt[63] > blk_hot)) >= ALARM_CELLS) begin
                    streak <= streak + 1'b1;
                    alarm  <= (streak >= STREAK - 4'd1);
                end else begin
                    streak <= 4'd0;
                    alarm  <= 1'b0;
                end
            end else begin
                active_cnt <= active_cnt + (blk_cnt[scan_idx] > blk_hot);
                scan_idx <= scan_idx + 1'b1;
            end
        end
        // sole runtime write entry to the array (reset branch has priority)
        if(blk_we) blk_cnt[blk_waddr] <= blk_wdin;
    end
end

endmodule

//==============================================================================
// seg_lb: continuous-enable circular simple dual-port BRAM line/history buffer.
// dout = din delayed exactly LEN enables.
//==============================================================================
module seg_lb#(
    parameter W   = 8,
    parameter AW  = 11,
    parameter LEN = 1280,
    parameter PRIM = "block",  // "block" = BRAM, "distributed" = LUTRAM
    parameter RL   = 2         // XPM read latency (block=2, distributed=1)
)(
    input              clk,
    input              rst_n,
    input              en,
    input  [W-1:0]     din,
    output [W-1:0]     dout
);
reg [AW-1:0] wa;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) wa <= {AW{1'b0}};
    else if(en) wa <= wa + 1'b1;
end
// Compensate read latency: add RL to the read address so doutb equals din
// delayed by EXACTLY LEN enables (not LEN+RL).
wire [AW-1:0] ra = wa - LEN + RL;
xpm_memory_sdpram #(
    .ADDR_WIDTH_A(AW),
    .ADDR_WIDTH_B(AW),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(W),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION(PRIM=="block" ? "true" : "false"),
    .MEMORY_PRIMITIVE(PRIM),
    .MEMORY_SIZE(W*(2**AW)),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(W),
    .READ_LATENCY_B(RL),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_A("SYNC"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(1),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(W),
    // SDP port B is read-only; must be read-first (required for distributed SDP).
    .WRITE_MODE_B("read_first")
) u_lb (
    .clka(clk),.ena(1'b1),.wea(en),.addra(wa),.dina(din),
    .clkb(clk),.rstb(1'b0),.enb(1'b1),.addrb(ra),
    .doutb(dout),.dbiterrb(),.sbiterrb(),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.sleep(1'b0)
);
endmodule
