//==============================================================================
// File        : lcd_rgb_char.v
// Module      : lcd_rgb_char
// Description :
//   RGB LCD display sub-system wrapper. It ties panel timing, character/UI rendering and panel
//   ID handling together and drives the parallel RGB interface of the 800x480 panel.
//==============================================================================
module  lcd_rgb_char(
    input              sys_clk   ,
    input              sys_rst_n ,

    input      [31:0]  data      ,

    output             lcd_hs    ,
    output             lcd_vs    ,
    output             lcd_de    ,
    inout      [23:0]  lcd_rgb   ,
    output             lcd_bl    ,
    output             lcd_clk   ,
    output             lcd_rst_n,
    output     [15:0]  lcd_id,
	output	   [1:0]   mode_switch_signal,
	output     [5:0]   frame_switching_signal,
	output     [2:0]   sens_level,
	output     [15:0]   thresh_lvl,
	output              calc_mode,
	input      [15:0]   amp_pix,
	input               touch_valid
);
wire  [10:0]  pixel_xpos_w ;
wire  [10:0]  pixel_ypos_w ;
wire  [23:0]  pixel_data_w ;
wire  [23:0]  lcd_rgb_o    ;
wire          lcd_pclk     ;
wire  [15:0]  bcd_data_x   ;
wire  [15:0]  bcd_data_y   ;
assign lcd_rgb = lcd_de ? lcd_rgb_o : {24{1'bz}};
rd_id    u_rd_id(
    .clk          (sys_clk  ),
    .rst_n        (sys_rst_n),
    .lcd_rgb      (lcd_rgb  ),
    .lcd_id       (lcd_id   )
);
clk_div  u_clk_div(
    .clk          (sys_clk  ),
    .rst_n        (sys_rst_n),
    .lcd_id       (lcd_id   ),
    .lcd_pclk     (lcd_pclk )
);

binary2bcd u_binary2bcd_x(
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),
    .data            (data[31:16]),
    .bcd_data        (bcd_data_x)
);
binary2bcd u_binary2bcd_y(
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),
    .data            (data[15:0]),
    .bcd_data        (bcd_data_y)
);
lcd_display  u_lcd_display(
    .lcd_pclk       (lcd_pclk    ),
    .sys_rst_n      (sys_rst_n   ),
    .data           ({bcd_data_x,bcd_data_y}),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w),
    .pixel_data     (pixel_data_w),
	.mode_switch_signal(mode_switch_signal),
	.frame_switching_signal(frame_switching_signal),
	.sens_level        (sens_level),
	.thresh_lvl        (thresh_lvl),
	.amp_pix           (amp_pix),
	.calc_mode         (calc_mode),
	.touch_valid       (touch_valid)
);
lcd_driver  u_lcd_driver(
    .lcd_pclk       (lcd_pclk    ),
    .rst_n          (sys_rst_n   ),
    .lcd_id         (lcd_id      ),
    .lcd_hs         (lcd_hs      ),
    .lcd_vs         (lcd_vs      ),
    .lcd_de         (lcd_de      ),
    .lcd_bl         (lcd_bl      ),
    .lcd_clk        (lcd_clk     ),
    .lcd_rgb        (lcd_rgb_o   ),
    .lcd_rst        (lcd_rst_n   ),
    .data_req       (),
    .h_disp         (),
    .v_disp         (),
    .pixel_data     (pixel_data_w),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w)
);
endmodule
