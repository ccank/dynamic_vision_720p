// dynamic_extract_565.v
// Frame-difference motion extraction for RGB565.
//
// Two readout modes selected by calc_mode (synchronized from LCD clock domain):
//   calc_mode = 0 (yellow): per-frame motion pixel count mcnt -> amp_pix
//   calc_mode = 1 (grey)  : 2 s (120 frame) binary afterimage in block RAM,
//                            unique lit pixels only (write-1-to-set means a
//                            repeated hit stays 1), then area and object height
//                            are scanned and displacement = 2*area/height.
//
// Multi-driver safety: amp_pix is assigned in exactly ONE always block. The BRAM
// write port and read port each have their own always; every FSM register lives
// in a single FSM always.
`timescale 1ns / 1ps

//==============================================================================
// File        : dynamic_extract_565.v
// Module      : dynamic_extract_565
// Description :
//   Frame-difference moving-target extraction on RGB565. It subtracts the delayed frame from
//   the current frame, thresholds and highlights moving pixels, quantifies motion magnitude
//   and raises the alarm, with optional geometry measurement in calc mode.
//==============================================================================
module dynamic_extract_565(
    input               pclk,
    input               rst_n,
    input               in_de,
    input               in_hsync,
    input               in_vsync,
    input       [15:0]  cur_rgb,
    input       [15:0]  dly_rgb,
    input               bypass,
    input               calc_mode,
    output              out_de,
    output              out_hsync,
    output              out_vsync,
    output  reg [15:0]  out_rgb,
    output reg  [15:0]  amp_pix
);

//---------------------------------------------------------------------------
// RGB565 channel absolute differences + frame-difference video pipeline
//---------------------------------------------------------------------------
wire [5:0] cr = {1'b0,cur_rgb[15:11]};
wire [5:0] dr = {1'b0,dly_rgb[15:11]};
wire [5:0] adr = (cr>=dr) ? (cr-dr) : (dr-cr);
wire [4:0] diff_r = adr[4:0];

wire [6:0] cg = {1'b0,cur_rgb[10:5]};
wire [6:0] dg = {1'b0,dly_rgb[10:5]};
wire [6:0] adg = (cg>=dg) ? (cg-dg) : (dg-cg);
wire [5:0] diff_g = adg[5:0];

wire [5:0] cb = {1'b0,cur_rgb[4:0]};
wire [5:0] db = {1'b0,dly_rgb[4:0]};
wire [5:0] adb = (cb>=db) ? (cb-db) : (db-cb);
wire [4:0] diff_b = adb[4:0];

wire [15:0] diff = {diff_r,diff_g,diff_b};

reg [15:0]  d0;
reg         de0, hs0, vs0;
reg         de1, hs1, vs1;

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        d0<=16'b0; de0<=1'b0; hs0<=1'b0; vs0<=1'b0;
    end else begin
        d0<=bypass ? cur_rgb : diff; de0<=in_de; hs0<=in_hsync; vs0<=in_vsync;
    end
end

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        out_rgb<=16'b0; de1<=1'b0; hs1<=1'b0; vs1<=1'b0;
    end else begin
        out_rgb<=d0; de1<=de0; hs1<=hs0; vs1<=vs0;
    end
end

assign out_de    = de1;
assign out_hsync = hs1;
assign out_vsync = vs1;

//---------------------------------------------------------------------------
// pixel coordinates in active video (1280 x 720)
//---------------------------------------------------------------------------
reg [10:0] px, py;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin px<=11'd0; py<=11'd0; end
    else if(in_de) px <= px + 1'b1;
    else if(px != 11'd0) begin
        px <= 11'd0;
        py <= (py < 11'd719) ? py + 1'b1 : 11'd0;
    end
end

wire motion = in_de && !bypass &&
              (adg > 7'd8 || adr > 6'd6 || adb > 6'd6);

//---------------------------------------------------------------------------
// calc_mode CDC (slow touch button, two-flop synchronizer)
//---------------------------------------------------------------------------
reg cm_s0, cm_s1;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin cm_s0<=1'b0; cm_s1<=1'b0; end
    else       begin cm_s0<=calc_mode; cm_s1<=cm_s0; end
end
wire cm = cm_s1;

// VS rising-edge flag, shared by the counter and the FSM (read-only here)
reg vd;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) vd<=1'b0;
    else       vd<=in_vsync;
end
wire vs_rise = in_vsync && !vd;

//---------------------------------------------------------------------------
// Yellow mode: raw per-frame motion pixel count (drives mcnt ONLY)
//---------------------------------------------------------------------------
reg [15:0] mcnt;
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) mcnt<=16'd0;
    else if(vs_rise) mcnt<=16'd0;
    else if(motion)  mcnt<=mcnt + 1'b1;
end

//---------------------------------------------------------------------------
// Grey mode: 640 x 360 binary afterimage (2x2 downsample), 1 bit per bin.
//   address = {py[9:1] (9b,0..359), px[10:1] (10b,0..639)} <= 230399
// Writing 1 sets a latch; writing it again keeps 1 -> unique lit pixel area,
// no read-modify-write needed.
//---------------------------------------------------------------------------
localparam [18:0] DEPTH  = 19'd230400; // 640*360
localparam [6:0]  NFRAME = 7'd119;     // 120 frames ~ 2 s @60 fps
localparam [10:0] ROW_MIN= 11'd12;     // min lit bins in a row to count edge

(* ram_style = "block" *) reg img [0:230399];

// write port (sole writer of img)
reg         img_we;
reg [18:0]  img_wa;
reg         img_wd;
always @(posedge pclk) begin
    if(img_we) img[img_wa] <= img_wd;
end

// read port (sole writer of img_q), 1-cycle latency
reg         img_re;
reg [18:0]  img_ra;
reg         img_q;
always @(posedge pclk) begin
    if(img_re) img_q <= img[img_ra];
end

wire [18:0] pix_a = {py[9:1], px[10:1]};

localparam [2:0] S_IDLE=0, S_CLEAR=1, S_ACCUM=2, S_SCAN=3, S_DRAIN=4, S_OUT=5, S_DIV=6;
reg [2:0]   st;
reg [18:0]  clr_a;
reg [6:0]   win;
reg [18:0]  ra;
reg [9:0]   a_col;
reg [8:0]   a_row;
reg         qv;
reg [9:0]   qcol;
reg [8:0]   qrow;
reg [1:0]   drain;
reg [19:0]  area;
reg [10:0]  cur_sum;
reg [8:0]   ymin, ymax;
reg         got;
reg [15:0]  disp_pix;
reg         disp_up;

//---- multi-cycle restoring serial divider. It replaces the old single-cycle
//---- 22b/11b variable '/' which synthesized into a ~150 logic-level carry
//---- chain (worst setup -13.9 ns @75 MHz). One subtract/compare per cycle.
reg [4:0]   div_cnt;                         // 0..21 -> 22 iterations
reg [11:0]  div_rem;                         // remainder, 1 guard bit over D
reg [21:0]  div_q;                           // work reg, loaded with numerator
reg [10:0]  div_d;                           // latched divisor
wire [11:0] div_rshf = {div_rem[10:0], div_q[21]};   // R<<1 | Q.msb
wire        div_ge   = (div_rshf >= {1'b0, div_d});  // shifted R >= D ?
wire [11:0]  div_rsub = div_rshf - {1'b0, div_d};
wire [11:0]  div_rem_n = div_ge ? div_rsub : div_rshf;
wire [21:0]  div_q_n   = {div_q[20:0], div_ge};      // Q<<1 | quotient bit

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        st<=S_IDLE; clr_a<=19'd0; win<=7'd0;
        img_we<=1'b0; img_wa<=19'd0; img_wd<=1'b0;
        img_re<=1'b0; img_ra<=19'd0;
        ra<=19'd0; a_col<=10'd0; a_row<=9'd0;
        qv<=1'b0; qcol<=10'd0; qrow<=9'd0; drain<=2'd0;
        area<=20'd0; cur_sum<=11'd0; ymin<=9'd0; ymax<=9'd0; got<=1'b0;
        disp_pix<=16'd0; disp_up<=1'b0;
        div_cnt<=5'd0; div_rem<=12'd0; div_q<=22'd0; div_d<=11'd0;
    end else begin
        // default control values every cycle
        img_we  <= 1'b0;
        img_re  <= 1'b0;
        disp_up <= 1'b0;

        if(cm == 1'b0) begin
            // grey mode off: park the FSM, never touch the BRAM
            st <= S_IDLE;
        end else begin
            case(st)
            //--------------------------------------------------------------
            S_IDLE: begin
                clr_a   <= 19'd0;
                area    <= 20'd0;
                cur_sum <= 11'd0;
                ymin    <= 9'd0; ymax<=9'd0; got<=1'b0;
                st      <= S_CLEAR;
            end

            //-------------------------------------------------------------- clear
            S_CLEAR: begin
                img_we <= 1'b1; img_wd <= 1'b0; img_wa <= clr_a;
                if(clr_a == DEPTH-19'd1) begin
                    win <= 7'd0;
                    st  <= S_ACCUM;
                end else begin
                    clr_a <= clr_a + 19'd1;
                end
            end

            //-------------------------------------------------------------- accumulate
            S_ACCUM: begin
                if(motion) begin
                    img_we <= 1'b1; img_wd <= 1'b1; img_wa <= pix_a;
                end
                if(vs_rise) begin
                    if(win == NFRAME) begin
                        ra<=19'd0; a_col<=10'd0; a_row<=9'd0;
                        qv<=1'b0; drain<=2'd0;
                        st<=S_SCAN;
                    end else begin
                        win <= win + 7'd1;
                    end
                end
            end

            //-------------------------------------------------------------- scan
            S_SCAN: begin
                // issue one read address per cycle while in range
                if(ra < DEPTH) begin
                    img_re <= 1'b1; img_ra <= ra;
                    ra <= ra + 19'd1;
                    if(a_col == 10'd639) begin a_col<=10'd0; a_row<=a_row+9'd1; end
                    else                       a_col<=a_col+10'd1;
                end
                // return pipeline (1-cycle latency)
                qv   <= img_re;
                qcol <= a_col;
                qrow <= a_row;
                if(qv) begin
                    if(img_q) area <= area + 20'd1;
                    if(qcol == 10'd639) begin
                        // finish this row: cur_sum plus the current returned bin
                        if((cur_sum + {10'd0,img_q}) > ROW_MIN) begin
                            if(!got) begin ymin<=qrow; got<=1'b1; end
                            ymax<=qrow;
                        end
                        cur_sum <= 11'd0;
                    end else if(img_q) begin
                        cur_sum <= cur_sum + 11'd1;
                    end
                end
                if(ra == DEPTH) begin
                    img_re<=1'b0;
                    st<=S_DRAIN;
                end
            end

            //-------------------------------------------------------------- drain pipe
            S_DRAIN: begin
                qv <= img_re;
                if(qv) begin
                    if(img_q) area <= area + 20'd1;
                end
                drain <= drain + 2'd1;
                if(drain == 2'd2) st<=S_OUT;
            end

            //-------------------------------------------------------------- output
            //-------------------------------------------------------------- output:
            // latch operands and launch the serial divider, then run 22 cycles
            S_OUT: begin
                if(got && (ymax > ymin)) begin
                    // 2x2 downsample: d = 2*area / (2*height). Numerator is 22b,
                    // divisor 11b; quotient is taken low 16b exactly as before.
                    div_q   <= {1'b0, area, 1'b0};
                    div_d   <= 11'd2 * (ymax - ymin);
                    div_rem <= 12'd0;
                    div_cnt <= 5'd0;
                    st      <= S_DIV;
                end else begin
                    disp_pix <= 16'd0;
                    disp_up  <= 1'b1;
                    st       <= S_IDLE;
                end
            end

            //-------------------------------------------------------------- serial divide
            // one 12b subtract/compare per cycle; result lands after 22 cycles
            S_DIV: begin
                div_rem <= div_rem_n;
                div_q   <= div_q_n;
                div_cnt <= div_cnt + 5'd1;
                if(div_cnt == 5'd21) begin
                    disp_pix <= div_q_n[15:0];
                    disp_up  <= 1'b1;
                    st       <= S_IDLE;
                end else begin
                    st       <= S_DIV;
                end
            end

            default: st<=S_IDLE;
            endcase
        end
    end
end

//---------------------------------------------------------------------------
// SOLE driver of amp_pix
//---------------------------------------------------------------------------
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) amp_pix<=16'd0;
    else if(cm == 1'b0) begin
        if(vs_rise) amp_pix <= mcnt;      // yellow: raw count each frame
    end else begin
        if(disp_up) amp_pix <= disp_pix;  // grey: latch 2 s displacement result
    end
end

endmodule
