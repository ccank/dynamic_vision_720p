//==============================================================================
// File        : ov5640_dri.v
// Module      : ov5640_dri
// Description :
//   OV5640 camera driver top. It wraps the DVP capture block and the SCCB register
//   configuration block, drives camera reset/power-down and outputs synchronized
//   RGB565 frame data together with frame timing.
//==============================================================================
module ov5640_dri (
    input           clk             ,  // clock
    input           rst_n           ,  // reset, active low
    // camera interface
    input           cam_pclk        ,  // CMOS pixel clock
    input           cam_vsync       ,  // CMOS frame (vertical) sync
    input           cam_href        ,  // CMOS line (horizontal reference) sync
    input    [7:0]  cam_data        ,  // CMOS data
    output          cam_rst_n       ,  // CMOS reset, active low
    output          cam_pwdn        ,  // CMOS power-down / sleep mode select
    output          cam_scl         ,  // CMOS SCCB SCL
    inout           cam_sda         ,  // CMOS SCCB SDA
    
    // camera resolution configuration interface
    input    [12:0] cmos_h_pixel    ,  // horizontal resolution (active pixels)
    input    [12:0] cmos_v_pixel    ,  // vertical resolution (active lines)
    input    [12:0] total_h_pixel   ,  // total horizontal pixel count
    input    [12:0] total_v_pixel   ,  // total vertical pixel count
    input           capture_start   ,  // image capture start signal
    output          cam_init_done   ,  // camera initialization complete
    
    // user interface
    output          cmos_frame_vsync,  // frame valid signal
    output          cmos_frame_href ,  // line valid signal
    output          cmos_frame_valid,  // data valid enable
    output  [15:0]  cmos_frame_data    // valid pixel data
);

// parameter definitions
parameter SLAVE_ADDR = 7'h3c          ; // OV5640 device address 7h3c
parameter BIT_CTRL   = 1'b1           ; // OV5640 register address width: 0 = 8-bit, 1 = 16-bit
parameter CLK_FREQ   = 27'd50_000_000 ; // driving clock frequency of the i2c_dri module
parameter I2C_FREQ   = 18'd250_000    ; // I2C SCL frequency, no higher than 400 kHz

// wire definitions
wire        i2c_exec       ;  // I2C execution trigger
wire [23:0] i2c_data       ;  // I2C address/data to program (upper 8 bits address, low 8 bits data)
wire        i2c_done       ;  // I2C register-configuration done flag
wire        i2c_dri_clk    ;  // I2C operating clock
wire [ 7:0] i2c_data_r     ;  // data read back over I2C
wire        i2c_rh_wl      ;  // I2C read/write control

//*****************************************************
//**                    main code                      
//*****************************************************

// power-down mode select: 0 = normal mode, 1 = sleep mode
assign  cam_pwdn  = 1'b0;
assign  cam_rst_n = 1'b1;
    
// I2C configuration module
i2c_ov5640_rgb565_cfg u_i2c_cfg(
    .clk                (i2c_dri_clk),
    .rst_n              (rst_n),
            
    .i2c_exec           (i2c_exec),
    .i2c_data           (i2c_data),
    .i2c_rh_wl          (i2c_rh_wl),        // I2C read/write control
    .i2c_done           (i2c_done), 
    .i2c_data_r         (i2c_data_r),   
                
    .cmos_h_pixel       (cmos_h_pixel),     // CMOS horizontal active pixel count
    .cmos_v_pixel       (cmos_v_pixel) ,    // CMOS vertical active line count
    .total_h_pixel      (total_h_pixel),    // total horizontal pixel count
    .total_v_pixel      (total_v_pixel),    // total vertical pixel count
        
    .init_done          (cam_init_done) 
    );    

// I2C driver module
i2c_dri #(
    .SLAVE_ADDR         (SLAVE_ADDR),       // parameter pass-through
    .CLK_FREQ           (CLK_FREQ  ),              
    .I2C_FREQ           (I2C_FREQ  ) 
    )
u_i2c_dr(
    .clk                (clk),
    .rst_n              (rst_n     ),

    .i2c_exec           (i2c_exec  ),   
    .bit_ctrl           (BIT_CTRL  ),   
    .i2c_rh_wl          (i2c_rh_wl),        // tied to 0: only the I2C write operation is used
    .i2c_addr           (i2c_data[23:8]),   
    .i2c_data_w         (i2c_data[7:0]),   
    .i2c_data_r         (i2c_data_r),   
    .i2c_done           (i2c_done  ),
    
    .scl                (cam_scl   ),   
    .sda                (cam_sda   ),   

    .dri_clk            (i2c_dri_clk)       // I2C operating clock
    );

// CMOS image data capture module
cmos_capture_data u_cmos_capture_data(      // capture starts only after system initialization is complete
    .rst_n              (rst_n & capture_start),
    
    .cam_pclk           (cam_pclk),
    .cam_vsync          (cam_vsync),
    .cam_href           (cam_href),
    .cam_data           (cam_data),         
    
    .cmos_frame_vsync   (cmos_frame_vsync),
    .cmos_frame_href    (cmos_frame_href ),
    .cmos_frame_valid   (cmos_frame_valid), // data valid enable
    .cmos_frame_data    (cmos_frame_data )  // valid pixel data
    );

endmodule 
