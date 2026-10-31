// 16-bit (RGB565) line delay, same timing structure as line_shift_ram_8bit.
// Requires blk_mem_gen_0 re-configured to 16-bit width, depth 2048.

//==============================================================================
// File        : line_shift_ram_16bit.v
// Module      : line_shift_ram_16bit
// Description :
//   16-bit (RGB565) line delay built on block RAM. It stores previous image rows
//   and provides the delayed tap rows needed to build the 3x3 processing window.
//==============================================================================
module line_shift_ram_16bit(
    input           clock,
    input           clken,
    input           pre_frame_href,
    input   [15:0]  shiftin,
    output  [15:0]  taps0x,
    output  [15:0]  taps1x
);
reg  [2:0]  clken_dly;
reg  [10:0] ram_rd_addr;
reg  [10:0] ram_rd_addr_d0;
reg  [10:0] ram_rd_addr_d1;
reg  [15:0] shiftin_d0;
reg  [15:0] shiftin_d1;
reg  [15:0] shiftin_d2;
reg  [15:0] taps0x_d0;

always @(posedge clock) begin
    if(pre_frame_href) begin
        if(clken) ram_rd_addr <= ram_rd_addr + 1;
        else      ram_rd_addr <= ram_rd_addr;
    end
    else ram_rd_addr <= 0;
end

always @(posedge clock) begin
    clken_dly <= {clken_dly[1:0], clken};
end

always @(posedge clock) begin
    ram_rd_addr_d0 <= ram_rd_addr;
    ram_rd_addr_d1 <= ram_rd_addr_d0;
end

always @(posedge clock) begin
    shiftin_d0 <= shiftin;
    shiftin_d1 <= shiftin_d0;
    shiftin_d2 <= shiftin_d1;
end

blk_mem_gen_0 u_ram_2048x16_0(
    .clka  (clock),
    .wea   (clken_dly[2]),
    .addra (ram_rd_addr_d1),
    .dina  (shiftin_d2),
    .clkb  (clock),
    .addrb (ram_rd_addr),
    .doutb (taps0x)
);

always @(posedge clock) begin
    taps0x_d0 <= taps0x;
end

blk_mem_gen_0 u_ram_2048x16_1(
    .clka  (clock),
    .wea   (clken_dly[1]),
    .addra (ram_rd_addr_d0),
    .dina  (taps0x_d0),
    .clkb  (clock),
    .addrb (ram_rd_addr),
    .doutb (taps1x)
);
endmodule
