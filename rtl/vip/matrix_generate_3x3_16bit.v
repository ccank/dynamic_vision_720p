// 3x3 window generator for 16-bit RGB565 pixels (same timing as 8-bit version).

//==============================================================================
// File        : matrix_generate_3x3_16bit.v
// Module      : matrix_generate_3x3_16bit
// Description :
//   3x3 window generator for RGB565 pixels. Using the line buffers it aligns nine
//   neighborhood pixels (matrix 3x3) and presents them together every clock cycle.
//==============================================================================
module matrix_generate_3x3_16bit (
    input              clk,
    input              rst_n,
    input              pre_frame_vsync,
    input              pre_frame_href,
    input              pre_frame_clken,
    input      [15:0]  pre_img,
    output             matrix_frame_vsync,
    output             matrix_frame_href,
    output             matrix_frame_clken,
    output reg [15:0]  matrix_p11,
    output reg [15:0]  matrix_p12,
    output reg [15:0]  matrix_p13,
    output reg [15:0]  matrix_p21,
    output reg [15:0]  matrix_p22,
    output reg [15:0]  matrix_p23,
    output reg [15:0]  matrix_p31,
    output reg [15:0]  matrix_p32,
    output reg [15:0]  matrix_p33
);
wire [15:0] row1_data;
wire [15:0] row2_data;
wire        read_frame_href;
wire        read_frame_clken;
reg  [15:0] row3_data;
reg  [1:0]  pre_frame_vsync_r;
reg  [1:0]  pre_frame_href_r;
reg  [1:0]  pre_frame_clken_r;

assign read_frame_href    = pre_frame_href_r[0];
assign read_frame_clken   = pre_frame_clken_r[0];
assign matrix_frame_vsync = pre_frame_vsync_r[1];
assign matrix_frame_href  = pre_frame_href_r[1];
assign matrix_frame_clken = pre_frame_clken_r[1];

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) row3_data <= 0;
    else begin
        if(pre_frame_clken) row3_data <= pre_img;
        else               row3_data <= row3_data;
    end
end

line_shift_ram_16bit u_line_shift_ram_16bit(
    .clock          (clk),
    .clken          (pre_frame_clken),
    .pre_frame_href (pre_frame_href),
    .shiftin        (pre_img),
    .taps0x         (row2_data),
    .taps1x         (row1_data)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pre_frame_vsync_r <= 0;
        pre_frame_href_r  <= 0;
        pre_frame_clken_r <= 0;
    end else begin
        pre_frame_vsync_r <= {pre_frame_vsync_r[0], pre_frame_vsync};
        pre_frame_href_r  <= {pre_frame_href_r[0],  pre_frame_href};
        pre_frame_clken_r <= {pre_frame_clken_r[0], pre_frame_clken};
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        {matrix_p11, matrix_p12, matrix_p13} <= 48'h0;
        {matrix_p21, matrix_p22, matrix_p23} <= 48'h0;
        {matrix_p31, matrix_p32, matrix_p33} <= 48'h0;
    end
    else if(read_frame_href) begin
        if(read_frame_clken) begin
            {matrix_p11, matrix_p12, matrix_p13} <= {matrix_p12, matrix_p13, row1_data};
            {matrix_p21, matrix_p22, matrix_p23} <= {matrix_p22, matrix_p23, row2_data};
            {matrix_p31, matrix_p32, matrix_p33} <= {matrix_p32, matrix_p33, row3_data};
        end else begin
            {matrix_p11, matrix_p12, matrix_p13} <= {matrix_p11, matrix_p12, matrix_p13};
            {matrix_p21, matrix_p22, matrix_p23} <= {matrix_p21, matrix_p22, matrix_p23};
            {matrix_p31, matrix_p32, matrix_p33} <= {matrix_p31, matrix_p32, matrix_p33};
        end
    end else begin
        {matrix_p11, matrix_p12, matrix_p13} <= 48'h0;
        {matrix_p21, matrix_p22, matrix_p23} <= 48'h0;
        {matrix_p31, matrix_p32, matrix_p33} <= 48'h0;
    end
end
endmodule
