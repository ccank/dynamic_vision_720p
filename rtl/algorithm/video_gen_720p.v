`timescale 1ns/1ps
//==============================================================================
// video_gen_720p.v
//   720P internal test pattern generator. It does NOT generate its own timing:
//   it locks onto the OV5640 frame/line timing (cam_vsync / cam_href) and only
//   supplies pattern colors. Because the source mux keeps the camera vs/href/de
//   in every mode and switches only the pixel color, selecting a pattern can
//   never shift the picture.
//
//   Inside href, a byte_flag toggles on every pclk and resets outside href,
//   exactly like cmos_capture_data; the color is latched on the low byte and is
//   therefore valid on the same cycle as cmos_frame_data / cmos_frame_valid.
//
//   src=1 : five 120x120 squares, one centered in each of 5 vertical color bars,
//           moving on a clockwise square path (H and V, +/-3 px) at 20/10/5/1/
//           0.2 Hz (blue-bar red square uses the 6-point path, 5Hz).
//   src=2 : 512x320 checkerboard panel (16x16 cyan/red cells), 5Hz path.
//==============================================================================

//==============================================================================
// File        : video_gen_720p.v
// Module      : video_gen_720p
// Description :
//   Internal 720P test pattern generator (color bars / blocks / checkerboard). It is locked to
//   the camera href/vsync timing so its output can replace the live camera source seamlessly.
//==============================================================================
module video_gen_720p(
    input               pclk,
    input               rst_n,
    input       [1:0]   src,        // 1: five squares, 2: checkerboard
    input               cam_href,   // camera line window (locked timing)
    input               cam_vsync,  // camera frame sync (locked timing)
    output reg  [15:0]  rgb         // pattern color, aligned to camera de
);

// byte flag inside href (same cadence as cmos_capture_data)
reg byte_flag;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n)            byte_flag <= 1'b0;
    else if(!cam_href)    byte_flag <= 1'b0;
    else                  byte_flag <= ~byte_flag;
end

// pclk count within the line window -> pixel x
reg [12:0] hbyte;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n)            hbyte <= 13'd0;
    else if(!cam_href)    hbyte <= 13'd0;
    else                  hbyte <= hbyte + 13'd1;
end
wire [11:0] x = hbyte[12:1];   // 0..1279

// line count y: reset on vsync, advance at href falling edge
reg cam_href_d, cam_vsync_d;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin cam_href_d<=1'b0; cam_vsync_d<=1'b0; end
    else       begin cam_href_d<=cam_href; cam_vsync_d<=cam_vsync; end
end
wire href_fall = cam_href_d & ~cam_href;
wire vs_rise   = cam_vsync & ~cam_vsync_d;
reg [11:0] y;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n)              y <= 12'd0;
    else if(cam_vsync)      y <= 12'd0;
    else if(href_fall)      y <= (y==12'd719) ? 12'd0 : y + 12'd1;
end

//------------------------------------------------------------
// Red square (blue bar) and checkerboard: 6-frame clockwise path, 5Hz
//------------------------------------------------------------
reg [2:0] path_idx;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n)
        path_idx <= 3'd0;
    else if(vs_rise)
        path_idx <= (path_idx == 3'd5) ? 3'd0 : path_idx + 3'd1;
end
reg signed [4:0] sq_off_h, sq_off_v;
always @(*) begin
    case(path_idx)
        3'd0: begin sq_off_h = 5'sd0; sq_off_v = 5'sd0; end
        3'd1: begin sq_off_h = 5'sd3; sq_off_v = 5'sd0; end
        3'd2: begin sq_off_h = 5'sd3; sq_off_v = 5'sd3; end
        3'd3: begin sq_off_h = 5'sd0; sq_off_v = 5'sd3; end
        3'd4: begin sq_off_h = 5'sd0; sq_off_v = 5'sd1; end
        3'd5: begin sq_off_h = 5'sd1; sq_off_v = 5'sd0; end
    endcase
end

//------------------------------------------------------------
// Phase accumulators for the 4 new squares (Fs~30): inc=f*65536/30
//------------------------------------------------------------
reg [15:0] ph20, ph10, ph1, p02;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin ph20<=16'd0; ph10<=16'd0; ph1<=16'd0; p02<=16'd0; end
    else if(vs_rise) begin
        ph20 <= ph20 + 16'd43691;
        ph10 <= ph10 + 16'd21845;
        ph1  <= ph1  + 16'd2185;
        p02  <= p02  + 16'd437;
    end
end

//------------------------------------------------------------
// phase -> clockwise square path, +/-3 px
//------------------------------------------------------------
function signed [4:0] path_h;
    input [15:0] p;
    reg [16:0] e;
    reg signed [4:0] ep;
    begin
        e  = p[13:0] * 7'd6;
        ep = -5'sd3 + $signed({1'b0, e[16:14]});
        case(p[15:14])
            2'b00: path_h = ep;
            2'b01: path_h = 5'sd3;
            2'b10: path_h = -ep;
            2'b11: path_h = -5'sd3;
        endcase
    end
endfunction
function signed [4:0] path_v;
    input [15:0] p;
    reg [16:0] e;
    reg signed [4:0] ep;
    begin
        e  = p[13:0] * 7'd6;
        ep = -5'sd3 + $signed({1'b0, e[16:14]});
        case(p[15:14])
            2'b00: path_v = -5'sd3;
            2'b01: path_v = ep;
            2'b10: path_v = 5'sd3;
            2'b11: path_v = -ep;
        endcase
    end
endfunction

wire signed [4:0] oh20 = path_h(ph20), ov20 = path_v(ph20);
wire signed [4:0] oh10 = path_h(ph10), ov10 = path_v(ph10);
wire signed [4:0] oh1  = path_h(ph1 ), ov1  = path_v(ph1 );
wire signed [4:0] oh02 = path_h(p02 ), ov02 = path_v(p02 );

//------------------------------------------------------------
// Five 120x120 squares (half-size 60)
//------------------------------------------------------------
localparam [11:0] SQ_HALF = 12'd60;

wire in_q20 =
   ($signed({1'b0,x}) >= $signed({1'b0,12'd128-SQ_HALF}) + oh20) &&
   ($signed({1'b0,x}) <  $signed({1'b0,12'd128+SQ_HALF}) + oh20) &&
   ($signed({1'b0,y}) >= $signed({1'b0,12'd300})        + ov20) &&
   ($signed({1'b0,y}) <  $signed({1'b0,12'd420})        + ov20);
wire in_q10 =
   ($signed({1'b0,x}) >= $signed({1'b0,12'd384-SQ_HALF}) + oh10) &&
   ($signed({1'b0,x}) <  $signed({1'b0,12'd384+SQ_HALF}) + oh10) &&
   ($signed({1'b0,y}) >= $signed({1'b0,12'd300})         + ov10) &&
   ($signed({1'b0,y}) <  $signed({1'b0,12'd420})         + ov10);
wire signed [12:0] sq_left  = 12'd640-SQ_HALF + sq_off_h;
wire signed [12:0] sq_right = 12'd640+SQ_HALF + sq_off_h;
wire signed [12:0] sq_top   = 12'd360-SQ_HALF + sq_off_v;
wire signed [12:0] sq_bot   = 12'd360+SQ_HALF + sq_off_v;
wire in_q5 =
   ($signed({1'b0,x}) >= sq_left)  && ($signed({1'b0,x}) < sq_right) &&
   ($signed({1'b0,y}) >= sq_top)   && ($signed({1'b0,y}) < sq_bot);
wire in_q1 =
   ($signed({1'b0,x}) >= $signed({1'b0,12'd896-SQ_HALF}) + oh1) &&
   ($signed({1'b0,x}) <  $signed({1'b0,12'd896+SQ_HALF}) + oh1) &&
   ($signed({1'b0,y}) >= $signed({1'b0,12'd300})         + ov1) &&
   ($signed({1'b0,y}) <  $signed({1'b0,12'd420})         + ov1);
wire in_q02 =
   ($signed({1'b0,x}) >= $signed({1'b0,12'd1152-SQ_HALF}) + oh02) &&
   ($signed({1'b0,x}) <  $signed({1'b0,12'd1152+SQ_HALF}) + oh02) &&
   ($signed({1'b0,y}) >= $signed({1'b0,12'd300})          + ov02) &&
   ($signed({1'b0,y}) <  $signed({1'b0,12'd420})          + ov02);

//------------------------------------------------------------
// Checkerboard panel: 512x320 centered, 16x16 cells, 5Hz path
//------------------------------------------------------------
wire signed [12:0] pn_left   = 12'd640-12'd256 + sq_off_h;
wire signed [12:0] pn_right  = 12'd640+12'd256 + sq_off_h;
wire signed [12:0] pn_top    = 12'd360-12'd160 + sq_off_v;
wire signed [12:0] pn_bottom = 12'd360+12'd160 + sq_off_v;
wire in_panel =
   ($signed({1'b0,x}) >= pn_left)  && ($signed({1'b0,x}) < pn_right) &&
   ($signed({1'b0,y}) >= pn_top)   && ($signed({1'b0,y}) < pn_bottom);
wire signed [12:0] rel_x = $signed({1'b0,x}) - pn_left;
wire signed [12:0] rel_y = $signed({1'b0,y}) - pn_top;
wire [11:0] gx = rel_x[12:4];
wire [11:0] gy = rel_y[12:4];
wire chk_a = ((gx + gy) & 12'd1) == 1'b0;

// 5 vertical color bars (RGB565): black, white, blue, yellow, green
reg [15:0] bar_rgb;
always @(*) begin
    if(x < 12'd256)       bar_rgb = 16'h0000;
    else if(x < 12'd512)  bar_rgb = 16'hFFFF;
    else if(x < 12'd768)  bar_rgb = 16'h001F;
    else if(x < 12'd1024) bar_rgb = 16'hFFE0;
    else                   bar_rgb = 16'h07E0;
end

reg [15:0] src1_rgb;
always @(*) begin
    if(in_q20)      src1_rgb = 16'h07FF; // cyan    (20Hz)
    else if(in_q10) src1_rgb = 16'hFD20; // orange  (10Hz)
    else if(in_q5)  src1_rgb = 16'hF800; // red     (5Hz)
    else if(in_q1)  src1_rgb = 16'h601F; // violet  (1Hz)
    else if(in_q02) src1_rgb = 16'hF81F; // magenta (0.2Hz)
    else            src1_rgb = bar_rgb;
end

//------------------------------------------------------------
// Whole-block brightness micro-vibration (models the brightness change caused
// by real micro vibration / deformation). A triangle-wave approximation of a
// sine at each square's frequency modulates RGB565 by about one LSB (R/B +/-1,
// G +/-2 ~= Y +/-8, barely visible); the EVM stage then amplifies it. Clamp
// asymmetry becomes a small DC term that the EVM slow reference removes.
// Background bars are untouched.
//------------------------------------------------------------
function signed [8:0] tri_cc;   // triangle "sine", -128..127
    input [15:0] pp;
    reg [7:0] saw;
    begin
        saw = pp[14:7];
        tri_cc = $signed({1'b0, pp[15] ? (8'd255-saw) : saw}) - 9'sd128;
    end
endfunction

// red square 5Hz: 6-step sine level derived from path_idx
reg signed [8:0] k5;
always @(*) begin
    case(path_idx)
        3'd0: k5 = 9'sd0;
        3'd1: k5 = 9'sd110;
        3'd2: k5 = 9'sd110;
        3'd3: k5 = 9'sd0;
        3'd4: k5 = -9'sd110;
        default: k5 = -9'sd110;
    endcase
end

wire signed [8:0] ksel =
      in_q20 ? tri_cc(ph20)
    : in_q10 ? tri_cc(ph10)
    : in_q5  ? k5
    : in_q1  ? tri_cc(ph1)
    : in_q02 ? tri_cc(p02)
    : 9'sd0;

// symmetric threshold mapping (avoids arithmetic-shift truncation asymmetry)
wire signed [1:0] dr = (ksel>=9'sd64)  ?  2'sd1
                     : (ksel<=-9'sd64) ? -2'sd1 : 2'sd0;
wire signed [2:0] dg = (ksel>=9'sd48)  ?  3'sd2
                     : (ksel>=9'sd16)  ?  3'sd1
                     : (ksel<=-9'sd48) ? -3'sd2
                     : (ksel<=-9'sd16) ? -3'sd1 : 3'sd0;
wire signed [1:0] db = dr;

wire [4:0] r5 = src1_rgb[15:11];
wire [5:0] g6 = src1_rgb[10:5];
wire [4:0] b5 = src1_rgb[4:0];
wire signed [6:0] nr = $signed({2'b0,r5}) + dr;
wire signed [7:0] ng = $signed({2'b0,g6}) + dg;
wire signed [6:0] nb = $signed({2'b0,b5}) + db;
wire [4:0] rr = (nr<0)?5'd0:((nr>31)?5'd31:nr[4:0]);
wire [5:0] gg = (ng<0)?6'd0:((ng>63)?6'd63:ng[5:0]);
wire [4:0] bb = (nb<0)?5'd0:((nb>31)?5'd31:nb[4:0]);
wire [15:0] src1_vib = {rr,gg,bb};

// src2: same color-bar background as src1, but only the single centered red
// square (5Hz, micro-vibration). Other four squares removed.
wire [15:0] src2_rgb = in_q5 ? src1_vib : bar_rgb;

reg [15:0] pixel_rgb;
always @(*) begin
    case(src)
        2'd1:    pixel_rgb = src1_vib;
        2'd2:    pixel_rgb = src2_rgb;
        default: pixel_rgb = bar_rgb;
    endcase
end

// latch color on the low byte; rgb is then valid together with cmos_frame_valid
wire low_byte = cam_href & byte_flag;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n)            rgb <= 16'd0;
    else if(low_byte)     rgb <= pixel_rgb;
end

endmodule
