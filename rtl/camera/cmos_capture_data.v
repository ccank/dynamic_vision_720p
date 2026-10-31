//==============================================================================
// File        : cmos_capture_data.v
// Module      : cmos_capture_data
// Description :
//   CMOS (OV5640) DVP capture front-end. It receives the 8-bit DVP stream
//   with href/vsync in the cam_pclk domain and assembles RGB565 frame pixels,
//   emitting the frame valid/data handshake used by the rest of the pipeline.
//==============================================================================
module cmos_capture_data(
    input                 rst_n            ,  // reset, active low
    // camera interface
    input                 cam_pclk         ,  // CMOS pixel clock
    input                 cam_vsync        ,  // CMOS frame (vertical) sync
    input                 cam_href         ,  // CMOS line (horizontal reference) sync
    input  [7:0]          cam_data         ,                      
    // user interface
    output                cmos_frame_vsync ,  // frame valid signal
    output                cmos_frame_href  ,  // line valid signal
    output                cmos_frame_valid ,  // data valid enable
    output       [15:0]   cmos_frame_data     // valid pixel data
    );

// After all registers are configured, wait for WAIT_FRAME frames first
// so capture starts only once the register settings have taken effect
parameter  WAIT_FRAME = 4'd10    ;            // number of frames waited for the register data to stabilize
							     
// reg definitions
reg             cam_vsync_d0     ;
reg             cam_vsync_d1     ;
reg             cam_href_d0      ;
reg             cam_href_d1      ;
reg    [3:0]    cmos_ps_cnt      ;            // counter counting the stabilization frames
reg    [7:0]    cam_data_d0      ;            
reg    [15:0]   cmos_data_t      ;            // temporary register assembling 8-bit bytes into a 16-bit word
reg             byte_flag        ;            // flag: a 16-bit RGB word is complete
reg             byte_flag_d0     ;
reg             frame_val_flag   ;            // frame valid flag

wire            pos_vsync        ;            // rising edge of the input frame sync

//*****************************************************
//**                    main code
//*****************************************************

// detect the rising edge of the input frame sync
assign pos_vsync = (~cam_vsync_d1) & cam_vsync_d0; 

// output frame valid signal
assign  cmos_frame_vsync = frame_val_flag  ?  cam_vsync_d1  :  1'b0; 

// output line valid signal
assign  cmos_frame_href  = frame_val_flag  ?  cam_href_d1   :  1'b0; 

// output data valid enable
assign  cmos_frame_valid = frame_val_flag  ?  byte_flag_d0  :  1'b0; 

// output pixel data
assign  cmos_frame_data  = frame_val_flag  ?  cmos_data_t   :  1'b0; 
       
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        cam_vsync_d0 <= 1'b0;
        cam_vsync_d1 <= 1'b0;
        cam_href_d0 <= 1'b0;
        cam_href_d1 <= 1'b0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;
        cam_vsync_d1 <= cam_vsync_d0;
        cam_href_d0 <= cam_href;
        cam_href_d1 <= cam_href_d0;
    end
end

// count frames
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        cmos_ps_cnt <= 4'd0;
    else if(pos_vsync && (cmos_ps_cnt < WAIT_FRAME))
        cmos_ps_cnt <= cmos_ps_cnt + 4'd1;
end

// frame valid flag
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        frame_val_flag <= 1'b0;
    else if((cmos_ps_cnt == WAIT_FRAME) && pos_vsync)
        frame_val_flag <= 1'b1;
    else;    
end            

// assemble 8-bit data into 16-bit RGB565 words
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        cmos_data_t <= 16'd0;
        cam_data_d0 <= 8'd0;
        byte_flag <= 1'b0;
    end
    else if(cam_href) begin
        byte_flag <= ~byte_flag;
        cam_data_d0 <= cam_data;
        if(byte_flag)
            cmos_data_t <= {cam_data_d0,cam_data};
        else;   
    end
    else begin
        byte_flag <= 1'b0;
        cam_data_d0 <= 8'b0;
    end    
end        

// generate the output data valid signal (cmos_frame_valid)
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        byte_flag_d0 <= 1'b0;
    else
        byte_flag_d0 <= byte_flag;	
end 
       
endmodule
