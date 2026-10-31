`timescale 1ns/1ps
//==============================================================================
// Module      : dynamic_vision_720p (system top level)
// Description :
//   Top level of the 720P multi-mode dynamic vision system. It instantiates and
//   connects the full chain: capture -> front-end denoise -> DDR3 frame cache ->
//   three display-mode pipelines -> HDMI / LCD output -> touch user interface.
// Data path   :
//   OV5640 (720P RGB565) or internal test patterns -> color denoise -> DDR3
//   64-slot ring buffer (one write, two reads: the current frame and a
//   configurable delayed frame) -> 720P60 HDMI output through the MS7210 PHY.
// Modes (mode_sel): 0 = original view,
//                   1 = frame-difference moving-target extraction,
//                   2 = Eulerian video magnification (EVM).
// Clock domains:
//   clk_50m      LCD touch panel,
//   clk_200m     DDR3 MIG reference,
//   clk_75m      video algorithm main clock,
//   clk_75m_deg  phase-shifted HDMI sampling clock,
//   clk_10m      MS7210 configuration clock,
//   cam_pclk     camera pixel clock.
// Notes:
//   The front-end filter is always enabled (key_mode=0). All EVM temporal state
//   resides in on-chip BRAM; the DDR state path inside ddr3_top is tied off.
//==============================================================================
module dynamic_vision_720p(
    input               sys_clk_p,      // 100 MHz differential clock P
    input               sys_clk_n,      // 100 MHz differential clock N
    input               sys_rst_n,      // global reset, active low

    // OV5640 camera
    output              cam_rst_n,      // camera hardware reset, active low
    output              cam_pwdn,       // camera power-down
    output              cam_scl,        // SCCB config clock
    inout               cam_sda,        // SCCB config data
    input               cam_pclk,       // camera pixel clock
    input               cam_vsync,      // camera vertical sync
    input               cam_href,       // camera horizontal reference
    input       [7:0]   cam_data,       // camera 8-bit DVP data

    // MS7210 HDMI transmitter
    output              iic_scl,        // MS7210 config I2C clock
    inout               iic_sda,        // MS7210 config I2C data
    output              rstn_out,       // MS7210 reset, active low
    output              video_clk,      // HDMI pixel clock
    output              video_vs,       // HDMI vertical sync
    output              video_hs,       // HDMI horizontal sync
    output              video_de,       // HDMI data enable
    output      [23:0]  video_rgb,      // HDMI RGB888 data

    // push buttons
    input               key_user,       // KEY1: reserved mode key
    input               key2,           // KEY2: cycle video source

    output      [1:0]   led,            // alarm indicators

    // 800x480 RGB LCD with capacitive touch
    inout               touch_sda,      // touch I2C data
    output              touch_scl,      // touch I2C clock
    inout               touch_int,      // touch interrupt
    output              touch_rst_n,    // touch reset, active low
    output              lcd_de,         // LCD data enable
    output              lcd_hs,         // LCD horizontal sync
    output              lcd_vs,         // LCD vertical sync
    output              lcd_bl,         // LCD backlight
    output              lcd_clk,        // LCD pixel clock
    output              lcd_rst_n,      // LCD reset, active low
    inout       [23:0]  lcd_rgb,        // LCD RGB888 data

    // DDR3 physical pins
    inout       [63:0]  ddr3_dq,        // DDR3 data bus
    inout       [7:0]   ddr3_dqs_p,     // DDR3 differential strobe P
    inout       [7:0]   ddr3_dqs_n,     // DDR3 differential strobe N
    output      [14:0]  ddr3_addr,      // DDR3 address bus
    output      [2:0]   ddr3_ba,        // DDR3 bank address
    output              ddr3_ras_n,     // row address strobe, active low
    output              ddr3_cas_n,     // column address strobe, active low
    output              ddr3_we_n,      // write enable, active low
    output              ddr3_reset_n,   // DDR3 reset, active low
    output      [0:0]   ddr3_ck_p,      // differential clock P
    output      [0:0]   ddr3_ck_n,      // differential clock N
    output      [0:0]   ddr3_cke,       // clock enable
    output      [0:0]   ddr3_cs_n,      // chip select, active low
    output      [0:0]   ddr3_odt,       // on-die termination enable
    output      [7:0]   ddr3_dm         // data mask
);

//------------------------- clocks and reset -------------------------
wire clk_50m, clk_200m, clk_75m, clk_75m_deg, clk_10m;
wire locked;
wire clk_ibuf, sys_clk;
IBUFDS u_ibufds(.I(sys_clk_p), .IB(sys_clk_n), .O(clk_ibuf));  // differential input buffer
BUFG   u_bufg  (.I(clk_ibuf), .O(sys_clk));                     // global clock buffer
clk_wiz_0 u_clk_wiz(
    .clk_out1 (clk_50m),        // 50 MHz: LCD domain
    .clk_out2 (clk_200m),       // 200 MHz: DDR3 reference
    .clk_out3 (clk_75m),        // 75 MHz: main video clock
    .clk_out4 (clk_75m_deg),    // 75 MHz phase shifted: HDMI sampling
    .clk_out5 (clk_10m),        // 10 MHz: MS7210 config
    .reset    (1'b0),
    .locked   (locked),         // MMCM locked flag
    .clk_in1  (sys_clk)
);
wire rst_n = sys_rst_n & locked;   // reset while button pressed or clock not locked

// Cross-clock-domain sync registers for LCD UI parameters (declared early because
// ddr3_top.dly_frames uses frm_b below).
reg [1:0] mode_a, mode_b;          // display mode, two-flop synchronizer
reg [5:0] frm_a, frm_b;            // delayed-frame count, two-flop synchronizer
reg [2:0] sens_a, sens_b;          // magnification sensitivity, two-flop synchronizer
wire [2:0] sens_level_75 = sens_b; // sensitivity level synchronized into 75 MHz domain

// Frame-cache / display handshaking wires declared before first use to avoid
// implicit-net inference (ddr_calib, rddata and init_over are referenced by the
// capture/display instances below and driven later in this file).
wire        ddr_calib;
wire        init_over;
wire        dly_ready;
wire [15:0] rddata;
wire [15:0] rddata_dly;

//------------------------- OV5640 capture (self-contained driver) -------------------------
localparam H_CMOS_DISP   = 13'd1280;   // active pixels per line
localparam V_CMOS_DISP   = 13'd720;    // active lines per frame
localparam TOTAL_H_PIXEL = 13'd2570;   // total pixels per line (with blanking)
localparam TOTAL_V_PIXEL = 13'd980;    // total lines per frame (with blanking)
wire        cmos_frame_vsync;
wire        cmos_frame_href;
wire        cmos_frame_valid;
wire [15:0] wrdata;                    // RGB565 pixel from the camera
ov5640_dri u_ov5640_dri(
    .clk              (clk_50m),
    .rst_n            (rst_n),
    .cam_pclk         (cam_pclk),
    .cam_vsync        (cam_vsync),
    .cam_href         (cam_href),
    .cam_data         (cam_data),
    .cam_rst_n        (cam_rst_n),
    .cam_pwdn         (cam_pwdn),
    .cam_scl          (cam_scl),
    .cam_sda          (cam_sda),
    .cmos_h_pixel     (H_CMOS_DISP),
    .cmos_v_pixel     (V_CMOS_DISP),
    .total_h_pixel    (TOTAL_H_PIXEL),
    .total_v_pixel    (TOTAL_V_PIXEL),
    .capture_start    (ddr_calib),     // start capture only after DDR calibration
    .cam_init_done    (),
    .cmos_frame_vsync (cmos_frame_vsync),
    .cmos_frame_href  (cmos_frame_href),
    .cmos_frame_valid (cmos_frame_valid),
    .cmos_frame_data  (wrdata)
);

//------------------------- push-button debounce (75 MHz domain) -------------------------
wire k1tick, k2tick;
key_tick_debounce #(.CLK_HZ(75_000_000)) u_k1_db(
    .clk(clk_75m),.rst_n(rst_n),.key_in(key_user),.key_tick(k1tick)
);
key_tick_debounce #(.CLK_HZ(75_000_000)) u_k2_db(
    .clk(clk_75m),.rst_n(rst_n),.key_in(key2),.key_tick(k2tick)
);

// Mode select (75 MHz): 0 original / 1 extraction / 2 enhancement. The mode comes
// from the touch LCD; the push button no longer cycles the mode.
wire [1:0] mode_sel = mode_b;

// Source-change toggle generated in 75 MHz, then synchronized into cam_pclk.
reg k2_p;
always @(posedge clk_75m or negedge rst_n) begin
    if(!rst_n) k2_p <= 1'b0;
    else if(k2tick) k2_p <= ~k2_p;
end
reg [2:0] k2ps;
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) k2ps <= 3'd0;
    else k2ps <= {k2ps[1:0], k2_p};       // synchronizer chain
end
wire k2tick_cam = k2ps[2] ^ k2ps[1];      // edge detect -> one-cycle pulse in camera domain

reg [1:0] src_sel;   // camera-domain source: 0 OV5640 / 1 five color bars / 2 checkerboard
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) src_sel <= 2'd0;
    else if(k2tick_cam) src_sel <= (src_sel==2'd2) ? 2'd0 : src_sel + 1'b1;
end

//------------------------- internal test pattern generator -------------------------
// Locked to the raw camera href/vsync so its byte cadence matches cmos_capture
// exactly; tg_rgb is valid on the same cycle as cmos_frame_valid/data.
wire [15:0] tg_rgb;
video_gen_720p u_video_gen(
    .pclk      (cam_pclk),
    .rst_n     (rst_n),
    .src       (src_sel),
    .cam_href  (cam_href),
    .cam_vsync (cam_vsync),
    .rgb       (tg_rgb)
);

// Source mux (camera domain): timing always follows the camera, only pixels switch.
reg [15:0] src_rgb;
reg        src_hs, src_vs, src_de;
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin src_rgb<=0;src_hs<=0;src_vs<=0;src_de<=0; end
    else begin
        src_hs  <= cmos_frame_href;
        src_vs  <= cmos_frame_vsync;
        src_de  <= cmos_frame_valid;
        src_rgb <= (src_sel==2'd0) ? wrdata : tg_rgb;
    end
end

//------------------------- YCbCr chroma denoise (key_mode=0 enable, 1 bypass) -------------------------
wire [15:0] post_rgb;
wire        post_hs, post_vs, post_de;
vip_color_median u_median(
    .clk              (cam_pclk),
    .rst_n            (rst_n),
    .pre_frame_vsync  (src_vs),
    .pre_frame_href   (src_hs),
    .pre_frame_de     (src_de),
    .pre_rgb          (src_rgb),
    .key_mode         (1'b0),                // 0 = filter enabled
    .post_frame_vsync (post_vs),
    .post_frame_href  (post_hs),
    .post_frame_de    (post_de),
    .post_rgb         (post_rgb)
);

//------------------------- display timing (fixed 720P60) -------------------------
// Outputs first drive internal drv_* wires; the mode mux near the end selects what
// actually reaches the MS7210. Mode 0 selects drv_* directly, i.e. the base path.
wire        data_req;
wire [12:0] xpos, ypos;
wire        drv_hs, drv_vs, drv_de;
wire [23:0] drv_rgb;
video_driver u_video_driver(
    .pixel_clk  (clk_75m),
    .sys_rst_n  (rst_n & init_over),
    .video_hs   (drv_hs),
    .video_vs   (drv_vs),
    .video_de   (drv_de),
    .video_rgb  (drv_rgb),
    .data_req   (data_req),
    .pixel_data (rddata),
    .pixel_xpos (xpos),
    .pixel_ypos (ypos)
);

//------------------------- DDR3 frame ring (three-file architecture) -------------------------
// mode-2 EVM enable. All temporal state is kept in on-chip BRAM in this build, so
// the DDR state path inside ddr3_top is tied off (see the instantiation below).
wire        evm_en     = (mode_sel==2'd2);
ddr3_top u_ddr(
    .sys_clk_i          (clk_200m),
    .clk_ref_i          (clk_200m),
    .rst_n              (rst_n),

    .app_addr_rd_min    (29'd0),
    .app_addr_rd_max    (29'd230400),     // 64-bit words per frame
    .rd_bust_len        (10'd160),
    .app_addr_wr_min    (29'd0),
    .app_addr_wr_max    (29'd230400),
    .wr_bust_len        (10'd160),

    .ddr3_dq            (ddr3_dq),
    .ddr3_dqs_p         (ddr3_dqs_p),
    .ddr3_dqs_n         (ddr3_dqs_n),
    .ddr3_addr          (ddr3_addr),
    .ddr3_ba            (ddr3_ba),
    .ddr3_ras_n         (ddr3_ras_n),
    .ddr3_cas_n         (ddr3_cas_n),
    .ddr3_we_n          (ddr3_we_n),
    .ddr3_reset_n       (ddr3_reset_n),
    .ddr3_ck_p          (ddr3_ck_p),
    .ddr3_ck_n          (ddr3_ck_n),
    .ddr3_cke           (ddr3_cke),
    .ddr3_cs_n          (ddr3_cs_n),
    .ddr3_dm            (ddr3_dm),
    .ddr3_odt           (ddr3_odt),

    .ddr3_read_valid    (1'b1),
    .ddr3_pingpang_en   (1'b1),
    .wr_clk             (cam_pclk),       // write clock: camera pixel clock
    .rd_clk             (clk_75m),        // read clock: video display clock
    .wr_en              (post_de),
    .wrdata             (post_rgb),
    .rdata_req          (data_req),
    .rd_load            (drv_vs),
    .wr_load            (post_vs),
    .dly_frames         (frm_b),          // delayed-frame count set on the LCD (1~60)
    .rddata             (rddata),
    .rddata_dly         (rddata_dly),
    .init_calib_complete(ddr_calib),
    .dly_ready          (dly_ready),
    // All EVM temporal state (m/q/z) is in on-chip BRAM; the DDR state path is
    // tied off: inputs tied to 0, outputs left unconnected.
    .evm_en             (evm_en),
    .st_wr_en           (1'b0),
    .st_wr_din          (32'd0),
    .st_rd_dout         (),
    .st_rd_consume      (1'b0),
    .st_rd_empty        (),
    .st_rd_level        ()
);

//------------------------- mode 2: Eulerian video magnification -------------------------
// Self-contained D1 (pyramid layer) EVM: RGB565 in, RGB888 plus aligned de/hs/vs out.
// The 640x360 D1 temporal band-pass state (m/q/z) lives entirely in BLOCK RAM inside
// this module; the full-resolution original is preserved.
wire        evm_de, evm_hs, evm_vs;
wire [23:0] evm_rgb;
wire        evm_alarm;
dynamic_enhance_720p u_dynamic_enhance(
    .pclk       (clk_75m),
    .rst_n      (rst_n),
    .cur_hsync  (drv_hs),
    .cur_vsync  (~drv_vs),   // EVM expects active-high vs; drv_vs is active-low
    .cur_de     (drv_de),
    .cur_rgb565 (rddata),
    .in_valid   (evm_en & dly_ready),
    .out_hsync  (evm_hs),
    .out_vsync  (evm_vs),
    .out_de     (evm_de),
    .out_rgb    (evm_rgb),
    .alarm      (evm_alarm),
    .sens_level (sens_level_75)
);

//------------------------- mode 1: frame-difference extraction -------------------------
wire        ext_de, ext_hs, ext_vs;
wire [15:0] ext_rgb565;
wire [15:0] ext_amp_pix;          // quantified motion magnitude (for LCD display / alarm)
wire        lcd_calc_mode;        // touch-LCD measurement/calc mode switch
dynamic_extract_565 u_extract(
    .pclk      (clk_75m),
    .rst_n     (rst_n),
    .in_de     (drv_de),
    .in_hsync  (drv_hs),
    .in_vsync  (drv_vs),
    .cur_rgb   (rddata),          // current frame
    .dly_rgb   (rddata_dly),      // delayed frame
    .bypass    (~dly_ready),      // bypass to current frame until the delay path is ready
    .calc_mode (lcd_calc_mode),
    .out_de    (ext_de),
    .out_hsync (ext_hs),
    .out_vsync (ext_vs),
    .out_rgb   (ext_rgb565),
    .amp_pix   (ext_amp_pix)
);
// RGB565 to RGB888 (pad low bits with zeros).
wire [23:0] ext_rgb = {ext_rgb565[15:11],3'b0, ext_rgb565[10:5],2'b0, ext_rgb565[4:0],3'b0};

//------------------------- mode mux -> MS7210 -------------------------
// mode 0 original   : drv directly (current frame);
// mode 1 extraction : |current - delayed| (bypassed to current until dly_ready);
// mode 2 enhancement: EVM; per-pixel temporal state {m,q} is held in on-chip BRAM at
//                     the D1 layer while the full-resolution original is preserved.
//
// The mode-2 EVM stream lags drv by four video lines (two spatial Gaussian stages in
// the magnification path). Switching de/hs/vs/rgb with a bare combinational mux in the
// middle of a frame would jump the de/vs phase by those four lines; the HDMI receiver
// treats this as a broken field and re-locks (a multi-second black screen). To avoid it,
// the mode selection is latched on the falling edge of drv_vs (start of vertical
// blanking) so all four signals switch only while DE is inactive and the active field
// stays continuous, hence the receiver never drops lock.
reg [1:0] mode_eff;
reg       drv_vs_d;
always @(posedge clk_75m or negedge rst_n) begin
    if(!rst_n) begin mode_eff <= 2'd0; drv_vs_d <= 1'b1; end
    else begin
        drv_vs_d <= drv_vs;                            // drv_vs is active-low
        if(!drv_vs && drv_vs_d) mode_eff <= mode_sel;  // latch new mode at sync start
    end
end
assign video_hs  = (mode_eff==2'd2) ? evm_hs  : (mode_eff==2'd1) ? ext_hs  : drv_hs;
assign video_vs  = (mode_eff==2'd2) ? ~evm_vs : (mode_eff==2'd1) ? ext_vs  : drv_vs;
assign video_de  = (mode_eff==2'd2) ? evm_de  : (mode_eff==2'd1) ? ext_de  : drv_de;
assign video_rgb = (mode_eff==2'd2) ? evm_rgb : (mode_eff==2'd1) ? ext_rgb : drv_rgb;

//------------------------- RGB LCD + touch UI (clk_50m domain) -------------------------
// Buttons select the display mode; sliders set the DDR3 delay frames (1~60), the
// extraction threshold and the magnification sensitivity.
wire [1:0] lcd_mode;
wire [5:0] lcd_frame;
wire [2:0] lcd_sens;
wire [15:0] lcd_thresh;
// Motion magnitude synchronized from 75 MHz to 50 MHz with two flops (slow value).
reg [15:0] amp_a, amp_b;
always @(posedge clk_50m or negedge rst_n) begin
    if(!rst_n) begin amp_a<=16'd0; amp_b<=16'd0; end
    else begin amp_a<=ext_amp_pix; amp_b<=amp_a; end
end

top_lcd_touch u_lcd_touch(
    .sys_clk               (clk_50m),
    .rst_n                 (rst_n),
    .touch_sda             (touch_sda),
    .touch_scl             (touch_scl),
    .touch_int             (touch_int),
    .touch_rst_n           (touch_rst_n),
    .lcd_de                (lcd_de),
    .lcd_hs                (lcd_hs),
    .lcd_vs                (lcd_vs),
    .lcd_bl                (lcd_bl),
    .lcd_clk               (lcd_clk),
    .lcd_rst_n             (lcd_rst_n),
    .lcd_rgb               (lcd_rgb),
    .mode_switch_signal    (lcd_mode),
    .frame_switching_signal(lcd_frame),
    .sens_level            (lcd_sens),
    .thresh_lvl            (lcd_thresh),
    .amp_pix               (amp_b),
    .calc_mode             (lcd_calc_mode)
);

// Synchronize LCD mode/frame/sensitivity from clk_50m to clk_75m (slow manual signals,
// two flops are sufficient).
always @(posedge clk_75m or negedge rst_n) begin
    if(!rst_n) begin
        mode_a <= 2'd0; mode_b <= 2'd0;
        frm_a  <= 6'd10; frm_b  <= 6'd10;
        sens_a <= 3'd3; sens_b <= 3'd3;
    end else begin
        mode_a <= lcd_mode;  mode_b <= mode_a;
        frm_a  <= lcd_frame; frm_b <= frm_a;
        sens_a <= lcd_sens;  sens_b <= sens_a;
    end
end

//------------------------- MS7210 initialization -------------------------
ms72xx_ctl u_ms72xx_ctl(
    .clk      (clk_10m),
    .rst_n    (rst_n),
    .rstn_out (rstn_out),
    .init_over(init_over),       // asserted after all configuration registers are written
    .iic_scl  (iic_scl),
    .iic_sda  (iic_sda)
);

assign video_clk = clk_75m_deg;
// Alarm: light both LEDs on large EVM motion, or when extraction magnitude exceeds the threshold.
assign led = ((mode_sel==2'd2 && evm_alarm) ||
              (mode_sel==2'd1 && amp_b > lcd_thresh)) ? 2'b11 : 2'b00;

endmodule
