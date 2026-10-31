// ddr3_fifo_ctrl.v
// Pack 32x RGB565 pixels into one 512-bit write word (source -> DDR).
// TWO read unpack paths share the same rdata_req so their pixels stay aligned:
//   A (current) : rd_fifo     -> rddata
//   B (delayed) : rd_fifo_dly -> rddata_dly
// Both read FIFOs must be First-Word-Fall-Through (FWFT); the returned 512-bit
// bus is wired to both and only the channel selected by the ring write-enable
// actually stores it.
`timescale 1ns / 1ps

//==============================================================================
// File        : ddr3_fifo_ctrl.v
// Module      : ddr3_fifo_ctrl
// Description :
//   Asynchronous pack/unpack FIFO control between the video clocks and the MIG ui_clk.
//   It packs 32 RGB565 pixels into one 512-bit MIG write word and unpacks both current and
//   delayed read channels into the display and extraction streams.
//==============================================================================
module ddr3_fifo_ctrl(
    input               rst_n,
    input               wr_clk,
    input               rd_clk,
    input               ui_clk,
    input               wr_en,
    input       [15:0]  wrdata,
    input       [511:0] rfifo_din,
    input               rdata_req,
    input               rfifo_wren,        // channel A write enable
    input               rfifo_wren_dly,    // channel B write enable
    input               wfifo_rden,
    input               rd_load,
    input               wr_load,

    output      [511:0] wfifo_dout,
    output      [15:0]  rfifo_wcount,      // channel A level
    output      [15:0]  rfifo_wcount_dly,  // channel B level
    output      [15:0]  wfifo_rcount,
    output  reg [15:0]  rddata,
    output  reg [15:0]  rddata_dly
);
//reg define
reg  [511:0] wrdata_t;
reg  [9:0]   byte_cnt;
reg  [9:0]   i, id;
reg          wfifo_wren;
reg          rdfifo_rst_h;
reg          wfifo_rst_h;
reg  [31:0]  rd_load_d;
reg  [15:0]  wr_load_d;
reg          rd_load_d0;
reg          wr_load_d0;

//wire define
wire [511:0] dout, dout_dly;
wire [511:0] wfifo_din;
wire [15:0]  dataout    [0:31];
wire [15:0]  dataout_dly[0:31];
wire         rfifo_rden, rfifo_rden_dly;
wire [11:0]  wcount, wcount_dly;
wire [11:0]  wfifo_rcount_fifo;

assign rfifo_wcount     = {4'b0,wcount};
assign rfifo_wcount_dly = {4'b0,wcount_dly};
assign wfifo_rcount     = {4'b0,wfifo_rcount_fifo};

//---------------- channel A byte slicing
assign dataout[0]  = dout[511:496];
assign dataout[1]  = dout[495:480];
assign dataout[2]  = dout[479:464];
assign dataout[3]  = dout[463:448];
assign dataout[4]  = dout[447:432];
assign dataout[5]  = dout[431:416];
assign dataout[6]  = dout[415:400];
assign dataout[7]  = dout[399:384];
assign dataout[8]  = dout[383:368];
assign dataout[9]  = dout[367:352];
assign dataout[10] = dout[351:336];
assign dataout[11] = dout[335:320];
assign dataout[12] = dout[319:304];
assign dataout[13] = dout[303:288];
assign dataout[14] = dout[287:272];
assign dataout[15] = dout[271:256];
assign dataout[16] = dout[255:240];
assign dataout[17] = dout[240:224];
assign dataout[18] = dout[223:208];
assign dataout[19] = dout[207:192];
assign dataout[20] = dout[191:176];
assign dataout[21] = dout[175:160];
assign dataout[22] = dout[159:144];
assign dataout[23] = dout[143:128];
assign dataout[24] = dout[127:112];
assign dataout[25] = dout[111:96];
assign dataout[26] = dout[95:80];
assign dataout[27] = dout[79:64];
assign dataout[28] = dout[63:48];
assign dataout[29] = dout[47:32];
assign dataout[30] = dout[31:16];
assign dataout[31] = dout[15:0];

//---------------- channel B byte slicing
assign dataout_dly[0]  = dout_dly[511:496];
assign dataout_dly[1]  = dout_dly[495:480];
assign dataout_dly[2]  = dout_dly[479:464];
assign dataout_dly[3]  = dout_dly[463:448];
assign dataout_dly[4]  = dout_dly[447:432];
assign dataout_dly[5]  = dout_dly[431:416];
assign dataout_dly[6]  = dout_dly[415:400];
assign dataout_dly[7]  = dout_dly[399:384];
assign dataout_dly[8]  = dout_dly[383:368];
assign dataout_dly[9]  = dout_dly[367:352];
assign dataout_dly[10] = dout_dly[351:336];
assign dataout_dly[11] = dout_dly[335:320];
assign dataout_dly[12] = dout_dly[319:304];
assign dataout_dly[13] = dout_dly[303:288];
assign dataout_dly[14] = dout_dly[287:272];
assign dataout_dly[15] = dout_dly[271:256];
assign dataout_dly[16] = dout_dly[255:240];
assign dataout_dly[17] = dout_dly[240:224];
assign dataout_dly[18] = dout_dly[223:208];
assign dataout_dly[19] = dout_dly[207:192];
assign dataout_dly[20] = dout_dly[191:176];
assign dataout_dly[21] = dout_dly[175:160];
assign dataout_dly[22] = dout_dly[159:144];
assign dataout_dly[23] = dout_dly[143:128];
assign dataout_dly[24] = dout_dly[127:112];
assign dataout_dly[25] = dout_dly[111:96];
assign dataout_dly[26] = dout_dly[95:80];
assign dataout_dly[27] = dout_dly[79:64];
assign dataout_dly[28] = dout_dly[63:48];
assign dataout_dly[29] = dout_dly[47:32];
assign dataout_dly[30] = dout_dly[31:16];
assign dataout_dly[31] = dout_dly[15:0];

assign wfifo_din    = wrdata_t;
assign rfifo_rden     = (rdata_req && (i==31))  ? 1'b1 : 1'b0;
assign rfifo_rden_dly = (rdata_req && (id==31)) ? 1'b1 : 1'b0;

//16bit source -> 512bit packed
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n) begin
        wrdata_t <= 0;
        byte_cnt <= 0;
    end
    else if(wr_en) begin
        if(byte_cnt == 31) begin
            byte_cnt <= 0;
            wrdata_t <= {wrdata_t[495:0],wrdata};
        end
        else begin
            byte_cnt <= byte_cnt + 1;
            wrdata_t <= {wrdata_t[495:0],wrdata};
        end
    end
end

//wfifo write pulse
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)
        wfifo_wren <= 0;
    else if(wfifo_wren == 1)
        wfifo_wren <= 0;
    else if(byte_cnt == 31 && wr_en)
        wfifo_wren <= 1;
    else
        wfifo_wren <= 0;
end

//channel A unpack 512bit -> 16bit pixels
always @(posedge rd_clk or negedge rst_n) begin
    if(!rst_n) begin
        rddata <= 16'b0;
        i      <= 10'd0;
    end
    else if(rdata_req) begin
        rddata <= dataout[i];
        if(i == 31) i <= 10'd0;
        else        i <= i + 1'b1;
    end
    else
        i <= 10'd0;
end

//channel B unpack 512bit -> 16bit pixels
always @(posedge rd_clk or negedge rst_n) begin
    if(!rst_n) begin
        rddata_dly <= 16'b0;
        id         <= 10'd0;
    end
    else if(rdata_req) begin
        rddata_dly <= dataout_dly[id];
        if(id == 31) id <= 10'd0;
        else         id <= id + 1'b1;
    end
    else
        id <= 10'd0;
end

//rd_load edge into ui domain (resets BOTH read FIFOs)
always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n) rd_load_d0 <= 1'b0;
    else       rd_load_d0 <= rd_load;
end
always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n) rd_load_d <= 32'b0;
    else       rd_load_d <= {rd_load_d[14:0],rd_load_d0};
end
always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n) rdfifo_rst_h <= 1'b0;
    else if(rd_load_d[0] && !rd_load_d[14]) rdfifo_rst_h <= 1'b1;
    else rdfifo_rst_h <= 1'b0;
end

//wr_load edge into wr_clk domain
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n) begin wr_load_d0<=1'b0; wr_load_d<=16'b0; end
    else begin
        wr_load_d0 <= wr_load;
        wr_load_d  <= {wr_load_d[14:0],wr_load_d0};
    end
end
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n) wfifo_rst_h <= 1'b0;
    else if(wr_load_d[0] && !wr_load_d[15]) wfifo_rst_h <= 1'b1;
    else wfifo_rst_h <= 1'b0;
end

//read FIFO A (current)
rd_fifo u_rd_fifo (
  .rst               (~rst_n|rdfifo_rst_h),
  .wr_clk            (ui_clk),
  .rd_clk            (rd_clk),
  .din               (rfifo_din),
  .wr_en             (rfifo_wren),
  .rd_en             (rfifo_rden),
  .dout              (dout),
  .full              (),
  .empty             (),
  .rd_data_count     (),
  .wr_data_count     (wcount),
  .wr_rst_busy       (),
  .rd_rst_busy       ()
);

//read FIFO B (delayed)
rd_fifo_dly u_rd_fifo_dly (
  .rst               (~rst_n|rdfifo_rst_h),
  .wr_clk            (ui_clk),
  .rd_clk            (rd_clk),
  .din               (rfifo_din),
  .wr_en             (rfifo_wren_dly),
  .rd_en             (rfifo_rden_dly),
  .dout              (dout_dly),
  .full              (),
  .empty             (),
  .rd_data_count     (),
  .wr_data_count     (wcount_dly),
  .wr_rst_busy       (),
  .rd_rst_busy       ()
);

wr_fifo u_wr_fifo (
  .rst               (~rst_n|wfifo_rst_h),
  .wr_clk            (wr_clk),
  .rd_clk            (ui_clk),
  .din               (wfifo_din),
  .wr_en             (wfifo_wren),
  .rd_en             (wfifo_rden),
  .dout              (wfifo_dout),
  .full              (),
  .empty             (),
  .rd_data_count     (wfifo_rcount_fifo),
  .wr_data_count     (),
  .wr_rst_busy       (),
  .rd_rst_busy       ()
);

endmodule
