//==============================================================================
// File        : binary2bcd.v
// Module      : binary2bcd
// Description :
//   Binary-to-BCD converter. It translates a binary value into packed binary-coded decimal digits
//   so that parameter values can be rendered as decimal numbers on the LCD.
//==============================================================================
module binary2bcd(
    input   wire             sys_clk,
    input   wire             sys_rst_n,
    input   wire    [29:0]   data,

    output  reg     [35:0]   bcd_data
);
parameter   CNT_SHIFT_NUM = 7'd30;
reg [6:0]       cnt_shift;
reg [65:0]      data_shift;
reg             shift_flag;
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        cnt_shift <= 7'd0;
    else if((cnt_shift == CNT_SHIFT_NUM + 7'd1) && (shift_flag))
        cnt_shift <= 7'd0;
    else if(shift_flag)
        cnt_shift <= cnt_shift + 7'd1;
    else
        cnt_shift <= cnt_shift;
end
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        data_shift <= 66'd0;
    else if(cnt_shift == 7'd0)
        data_shift <= {36'b0,data};
    else if((cnt_shift <= CNT_SHIFT_NUM)&&(!shift_flag))begin
        data_shift[33:30] <= (data_shift[33:30] > 4) ? (data_shift[33:30] + 2'd3):(data_shift[33:30]);
        data_shift[37:34] <= (data_shift[37:34] > 4) ? (data_shift[37:34] + 2'd3):(data_shift[37:34]);
        data_shift[41:38] <= (data_shift[41:38] > 4) ? (data_shift[41:38] + 2'd3):(data_shift[41:38]);
        data_shift[45:42] <= (data_shift[45:42] > 4) ? (data_shift[45:42] + 2'd3):(data_shift[45:42]);
        data_shift[49:46] <= (data_shift[49:46] > 4) ? (data_shift[49:46] + 2'd3):(data_shift[49:46]);
        data_shift[53:50] <= (data_shift[53:50] > 4) ? (data_shift[53:50] + 2'd3):(data_shift[53:50]);
        data_shift[57:54] <= (data_shift[57:54] > 4) ? (data_shift[57:54] + 2'd3):(data_shift[57:54]);
        data_shift[61:58] <= (data_shift[61:58] > 4) ? (data_shift[61:58] + 2'd3):(data_shift[61:58]);
        data_shift[65:62] <= (data_shift[65:62] > 4) ? (data_shift[65:62] + 2'd3):(data_shift[65:62]);
        end
    else if((cnt_shift <= CNT_SHIFT_NUM)&&(shift_flag))
        data_shift <= data_shift << 1;
    else
        data_shift <= data_shift;
end
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        shift_flag <= 1'b0;
    else
        shift_flag <= ~shift_flag;
end
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        bcd_data <= 36'd0;
    else if(cnt_shift == CNT_SHIFT_NUM + 36'd1)
        bcd_data <= data_shift[65:30];
    else
        bcd_data <= bcd_data;
end
endmodule
