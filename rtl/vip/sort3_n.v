// Parameterized 3-value sorter, 1 clock latency (same structure as sort3).

//==============================================================================
// File        : sort3_n.v
// Module      : sort3_n
// Description :
//   Parameterized three-value sorter with one-cycle latency. Outputs the maximum,
//   median and minimum of three width-DW inputs, used as the building block of the median network.
//==============================================================================
module sort3_n #(parameter DW = 8) (
    input               clk,
    input               rst_n,
    input  [DW-1:0]     data1,
    input  [DW-1:0]     data2,
    input  [DW-1:0]     data3,
    output reg [DW-1:0] max_data,
    output reg [DW-1:0] mid_data,
    output reg [DW-1:0] min_data
);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        max_data <= {DW{1'b0}};
        mid_data <= {DW{1'b0}};
        min_data <= {DW{1'b0}};
    end else begin
        // max
        if(data1 >= data2 && data1 >= data3)
            max_data <= data1;
        else if(data2 >= data1 && data2 >= data3)
            max_data <= data2;
        else
            max_data <= data3;
        // median
        if((data1 >= data2 && data1 <= data3) || (data1 >= data3 && data1 <= data2))
            mid_data <= data1;
        else if((data2 >= data1 && data2 <= data3) || (data2 >= data3 && data2 <= data1))
            mid_data <= data2;
        else
            mid_data <= data3;
        // min
        if(data1 <= data2 && data1 <= data3)
            min_data <= data1;
        else if(data2 <= data1 && data2 <= data3)
            min_data <= data2;
        else
            min_data <= data3;
    end
end
endmodule
