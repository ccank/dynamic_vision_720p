// RGB565 color 3x3 median: independent median network on R/G/B channels.
// Data latency 3 clocks; frame control delayed 3 clocks to align.

//==============================================================================
// File        : median_color_rgb565.v
// Module      : median_color_rgb565
// Description :
//   Color median for RGB565. It applies the 3x3 median sorting network independently
//   to the red, green and blue channels and repacks the filtered RGB565 pixel.
//==============================================================================
module median_color_rgb565(
    input              clk,
    input              rst_n,
    input              median_frame_vsync,
    input              median_frame_href,
    input              median_frame_clken,
    input  [15:0]      data11, data12, data13,
    input  [15:0]      data21, data22, data23,
    input  [15:0]      data31, data32, data33,
    output [15:0]      target_data,
    output             pos_median_vsync,
    output             pos_median_href,
    output             pos_median_clken
);
// R = [15:11] (5), G = [10:5] (6), B = [4:0] (5)
wire [4:0] r_med;
wire [5:0] g_med;
wire [4:0] b_med;

median_chan #(.DW(5)) u_r(
    .clk(clk),.rst_n(rst_n),
    .data11(data11[15:11]),.data12(data12[15:11]),.data13(data13[15:11]),
    .data21(data21[15:11]),.data22(data22[15:11]),.data23(data23[15:11]),
    .data31(data31[15:11]),.data32(data32[15:11]),.data33(data33[15:11]),
    .target_data(r_med));

median_chan #(.DW(6)) u_g(
    .clk(clk),.rst_n(rst_n),
    .data11(data11[10:5]),.data12(data12[10:5]),.data13(data13[10:5]),
    .data21(data21[10:5]),.data22(data22[10:5]),.data23(data23[10:5]),
    .data31(data31[10:5]),.data32(data32[10:5]),.data33(data33[10:5]),
    .target_data(g_med));

median_chan #(.DW(5)) u_b(
    .clk(clk),.rst_n(rst_n),
    .data11(data11[4:0]),.data12(data12[4:0]),.data13(data13[4:0]),
    .data21(data21[4:0]),.data22(data22[4:0]),.data23(data23[4:0]),
    .data31(data31[4:0]),.data32(data32[4:0]),.data33(data33[4:0]),
    .target_data(b_med));

assign target_data = {r_med, g_med, b_med};

reg [2:0] vs_r, hr_r, ck_r;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        vs_r <= 0; hr_r <= 0; ck_r <= 0;
    end else begin
        vs_r <= {vs_r[1:0], median_frame_vsync};
        hr_r <= {hr_r[1:0], median_frame_href};
        ck_r <= {ck_r[1:0], median_frame_clken};
    end
end
assign pos_median_vsync = vs_r[2];
assign pos_median_href  = hr_r[2];
assign pos_median_clken = ck_r[2];
endmodule
