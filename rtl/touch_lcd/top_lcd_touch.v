//==============================================================================
// File        : top_lcd_touch.v
// Module      : top_lcd_touch
// Description :
//   LCD and capacitive-touch user-interface top. It integrates panel timing, on-screen UI
//   rendering and the touch controller, and outputs the selected mode, frame delay, threshold
//   and sensitivity parameters to the video core.
//==============================================================================
module top_lcd_touch(

    input            sys_clk    ,
    input            rst_n  ,

    inout            touch_sda  ,
    output           touch_scl  ,
    inout            touch_int  ,
    output           touch_rst_n,

    output           lcd_de     ,
    output           lcd_hs     ,
    output           lcd_vs     ,
    output           lcd_bl     ,
    output           lcd_clk    ,
    output           lcd_rst_n  ,
    inout    [23:0]  lcd_rgb    ,
	output	 [1:0]   mode_switch_signal,
	output   [5:0]   frame_switching_signal,
	output   [2:0]   sens_level,
	output   [15:0]   thresh_lvl,
	output            calc_mode,
	input    [15:0]   amp_pix
);
wire  [15:0]  lcd_id     ;
wire  [31:0]  data       ;
wire          touch_valid;
touch_top  u_touch_top(
    .clk            (sys_clk    ),
    .rst_n          (rst_n  ),
    .touch_rst_n    (touch_rst_n),
    .touch_int      (touch_int  ),
    .touch_scl      (touch_scl  ),
    .touch_sda      (touch_sda  ),

    .lcd_id         (lcd_id     ),
    .data           (data       ),
    .touch_valid    (touch_valid)
);

lcd_rgb_char  u_lcd_rgb_char
(
   .sys_clk         (sys_clk  ),
   .sys_rst_n       (rst_n),
   .data            (data     ),

   .lcd_id          (lcd_id   ),
   .lcd_hs          (lcd_hs   ),
   .lcd_vs          (lcd_vs   ),
   .lcd_de          (lcd_de   ),
   .lcd_rgb         (lcd_rgb  ),
   .lcd_bl          (lcd_bl   ),
   .lcd_rst_n       (lcd_rst_n),
   .lcd_clk         (lcd_clk  ),
   .mode_switch_signal(mode_switch_signal),
   .frame_switching_signal(frame_switching_signal),
   .sens_level        (sens_level),
   .thresh_lvl        (thresh_lvl),
   .amp_pix           (amp_pix),
   .calc_mode         (calc_mode),
   .touch_valid       (touch_valid)
);
endmodule
