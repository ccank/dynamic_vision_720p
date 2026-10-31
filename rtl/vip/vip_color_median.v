// Color RGB565 median processing wrapper with original/filtered switch.
// Both paths have exactly 5 pclk latency, so switching never misaligns timing.
// key_mode = 1 -> original bypass ; key_mode = 0 -> median filtered.

//==============================================================================
// File        : vip_color_median.v
// Module      : vip_color_median
// Description :
//   Front-end color denoise top. It converts RGB565 to YCbCr, applies a chroma box
//   filter plus a luma median, then converts back; key_mode=0 enables filtering, 1 bypasses it.
//==============================================================================
module vip_color_median(
    input              clk,
    input              rst_n,
    input              pre_frame_vsync,
    input              pre_frame_href,
    input              pre_frame_de,
    input      [15:0]  pre_rgb,
    input              key_mode,
    output             post_frame_vsync,
    output             post_frame_href,
    output             post_frame_de,
    output     [15:0]  post_rgb
);
//--------- 3x3 window (2 clocks) ---------
wire        m_vs, m_hr, m_de;
wire [15:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
matrix_generate_3x3_16bit u_matrix(
    .clk(clk),.rst_n(rst_n),
    .pre_frame_vsync(pre_frame_vsync),
    .pre_frame_href (pre_frame_href),
    .pre_frame_clken(pre_frame_de),
    .pre_img        (pre_rgb),
    .matrix_frame_vsync(m_vs),
    .matrix_frame_href (m_hr),
    .matrix_frame_clken(m_de),
    .matrix_p11(p11),.matrix_p12(p12),.matrix_p13(p13),
    .matrix_p21(p21),.matrix_p22(p22),.matrix_p23(p23),
    .matrix_p31(p31),.matrix_p32(p32),.matrix_p33(p33));

//--------- color median (3 clocks) ---------
wire [15:0] filt_rgb;
wire        f_vs, f_hr, f_de;
median_color_rgb565 u_median(
    .clk(clk),.rst_n(rst_n),
    .median_frame_vsync(m_vs),
    .median_frame_href (m_hr),
    .median_frame_clken(m_de),
    .data11(p11),.data12(p12),.data13(p13),
    .data21(p21),.data22(p22),.data23(p23),
    .data31(p31),.data32(p32),.data33(p33),
    .target_data(filt_rgb),
    .pos_median_vsync(f_vs),
    .pos_median_href (f_hr),
    .pos_median_clken(f_de));

//--------- original path, 5 pclk delay ---------
reg [15:0] o1,o2,o3,o4,o5;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin o1<=0;o2<=0;o3<=0;o4<=0;o5<=0; end
    else begin
        o1 <= pre_rgb;
        o2 <= o1;
        o3 <= o2;
        o4 <= o3;
        o5 <= o4;
    end
end

assign post_frame_vsync = f_vs;
assign post_frame_href  = f_hr;
assign post_frame_de    = f_de;
assign post_rgb         = key_mode ? o5 : filt_rgb;
endmodule
