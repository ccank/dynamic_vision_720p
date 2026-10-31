//==============================================================================
// File        : video_driver.v
// Module      : video_driver
// Description :
//   720P60 display timing generator. It produces horizontal/vertical sync and data-enable
//   signals, tracks the pixel coordinate and requests frame-buffer pixels through data_req.
//==============================================================================
module video_driver(
    input           	pixel_clk	,
    input           	sys_rst_n	,
		
    // RGB interface
    output          	video_hs	,     // horizontal sync
    output          	video_vs	,     // vertical sync
    output          	video_de	,     // data enable
    output  	[23:0]  video_rgb	,     // RGB888 color data
    output	reg			data_req 	,
	
    input   	[15:0]  pixel_data	,     // pixel data
    output  reg	[12:0]  pixel_xpos	,     // pixel x coordinate
    output  reg	[12:0]  pixel_ypos        // pixel y coordinate
);
// 1280x720 timing parameters (75 MHz pixel clock)
parameter  H_SYNC   =  11'd40;   // horizontal sync width
parameter  H_BACK   =  11'd220;  // horizontal back porch
parameter  H_DISP   =  11'd1280; // horizontal active pixels
parameter  H_FRONT  =  11'd110;  // horizontal front porch
parameter  H_TOTAL  =  11'd1650; // horizontal total line period

parameter  V_SYNC   =  11'd5;    // vertical sync width
parameter  V_BACK   =  11'd20;   // vertical back porch
parameter  V_DISP   =  11'd720;  // vertical active lines
parameter  V_FRONT  =  11'd5;    // vertical front porch
parameter  V_TOTAL  =  11'd750;  // vertical total frame period

// reg definitions
reg  [12:0] cnt_h;
reg  [12:0] cnt_v;
reg         video_en;

//*****************************************************
//**                    main code
//*****************************************************

assign video_de  = video_en;
assign video_hs  = ( cnt_h < H_SYNC ) ? 1'b0 : 1'b1;  // horizontal sync assignment
assign video_vs  = ( cnt_v < V_SYNC ) ? 1'b0 : 1'b1;  // vertical sync assignment
// RGB888 data output
assign video_rgb = video_de ? {pixel_data[15:11],3'b000,pixel_data[10:5],2'b00,pixel_data[4:0],3'b000} : 24'd0; 

// enable RGB data output
always @(posedge pixel_clk or negedge sys_rst_n) begin
	if(!sys_rst_n)
		video_en <= 1'b0;
	else
		video_en <= data_req;
end

// request input pixel color data
always @(posedge pixel_clk or negedge sys_rst_n) begin
	if(!sys_rst_n)
		data_req <= 1'b0;
	else if(((cnt_h >= H_SYNC + H_BACK - 2'd2) && (cnt_h < H_SYNC + H_BACK + H_DISP - 2'd2))
                  && ((cnt_v >= V_SYNC + V_BACK) && (cnt_v < V_SYNC + V_BACK+V_DISP)))
		data_req <= 1'b1;
	else
		data_req <= 1'b0;
end

// pixel x coordinate
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_xpos <= 13'd0;
    else if(data_req)
        pixel_xpos <= cnt_h + 2'd2 - H_SYNC - H_BACK ;
    else 
        pixel_xpos <= 13'd0;
end
    
// pixel y coordinate
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_ypos <= 13'd0;
    else if((cnt_v >= (V_SYNC + V_BACK)) && (cnt_v < (V_SYNC + V_BACK + V_DISP)))
        pixel_ypos <= cnt_v + 1'b1 - (V_SYNC + V_BACK) ;
    else 
        pixel_ypos <= 13'd0;
end

// horizontal counter, counting pixel clocks
always @(posedge pixel_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        cnt_h <= 13'd0;
    else begin
        if(cnt_h < H_TOTAL - 1'b1)
            cnt_h <= cnt_h + 1'b1;
        else 
            cnt_h <= 13'd0;
    end
end

// vertical counter, counting lines
always @(posedge pixel_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        cnt_v <= 13'd0;
    else if(cnt_h == H_TOTAL - 1'b1) begin
        if(cnt_v < V_TOTAL - 1'b1)
            cnt_v <= cnt_v + 1'b1;
        else 
            cnt_v <= 13'd0;
    end
end

endmodule
