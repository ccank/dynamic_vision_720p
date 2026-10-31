// Single-channel 3x3 median network: 7 sorters, 3 clock latency.

//==============================================================================
// File        : median_chan.v
// Module      : median_chan
// Description :
//   Single-channel 3x3 median sorting network. Seven three-value sorters derive the
//   median of nine inputs with a fixed three-cycle latency.
//==============================================================================
module median_chan #(parameter DW = 8) (
    input               clk,
    input               rst_n,
    input  [DW-1:0]     data11, data12, data13,
    input  [DW-1:0]     data21, data22, data23,
    input  [DW-1:0]     data31, data32, data33,
    output [DW-1:0]     target_data
);
wire [DW-1:0] max1, mid1, min1;
wire [DW-1:0] max2, mid2, min2;
wire [DW-1:0] max3, mid3, min3;
wire [DW-1:0] max_min, mid_mid, min_max;

// stage 1: sort each row
sort3_n #(.DW(DW)) s1 (.clk(clk),.rst_n(rst_n),.data1(data11),.data2(data12),.data3(data13),
                        .max_data(max1),.mid_data(mid1),.min_data(min1));
sort3_n #(.DW(DW)) s2 (.clk(clk),.rst_n(rst_n),.data1(data21),.data2(data22),.data3(data23),
                        .max_data(max2),.mid_data(mid2),.min_data(min2));
sort3_n #(.DW(DW)) s3 (.clk(clk),.rst_n(rst_n),.data1(data31),.data2(data32),.data3(data33),
                        .max_data(max3),.mid_data(mid3),.min_data(min3));
// stage 2
sort3_n #(.DW(DW)) s4 (.clk(clk),.rst_n(rst_n),.data1(max1),.data2(max2),.data3(max3),
                        .max_data(),.mid_data(),.min_data(max_min));
sort3_n #(.DW(DW)) s5 (.clk(clk),.rst_n(rst_n),.data1(mid1),.data2(mid2),.data3(mid3),
                        .max_data(),.mid_data(mid_mid),.min_data());
sort3_n #(.DW(DW)) s6 (.clk(clk),.rst_n(rst_n),.data1(min1),.data2(min2),.data3(min3),
                        .max_data(min_max),.mid_data(),.min_data());
// stage 3
sort3_n #(.DW(DW)) s7 (.clk(clk),.rst_n(rst_n),.data1(max_min),.data2(mid_mid),.data3(min_max),
                        .max_data(),.mid_data(target_data),.min_data());
endmodule
