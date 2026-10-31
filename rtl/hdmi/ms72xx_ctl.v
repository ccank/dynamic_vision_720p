`timescale 1ns / 1ps


//==============================================================================
// File        : ms72xx_ctl.v
// Module      : ms72xx_ctl
// Description :
//   MS72xx HDMI chip reset and initialization controller. It runs the I2C configuration
//   sequence and asserts init_over once every register has been written.
//==============================================================================
module ms72xx_ctl(
    input       clk,
    input       rst_n,
    
    output      rstn_out,    // chip reset, active low
    output      init_over,   // flag: all configuration registers done
    output      iic_scl ,   
    inout       iic_sda 
);


// parameter definitions
parameter SLAVE_ADDR = 7'h2b          ; // device I2C slave address
parameter BIT_CTRL   = 1'b1           ; // register address width: 0 = 8-bit, 1 = 16-bit
parameter CLK_FREQ   = 27'd10_000_000 ; // driving clock frequency of the i2c_dri module
parameter I2C_FREQ   = 18'd250_000    ; // I2C SCL frequency, no higher than 400 kHz
// wire definitions
wire        i2c_exec       ;  // I2C execution trigger
wire [23:0] i2c_data       ;  // I2C address/data to program (upper 16 bits address, low 8 bits data)
wire        i2c_done       ;  // I2C register-configuration done flag
wire        i2c_dri_clk    ;  // I2C operating clock
wire [ 7:0] i2c_data_r     ;  // data read back over I2C
wire        i2c_rh_wl      ;  // I2C read/write control

//*****************************************************
//**                    main code
//*****************************************************

// I2C configuration module
i2c_ms7210_cfg u_i2c_ms7210_cfg(
    .clk                (i2c_dri_clk),
    .rst_n              (rst_n),
            
    .i2c_exec           (i2c_exec),
    .i2c_data           (i2c_data),
    .i2c_rh_wl          (i2c_rh_wl),        // I2C read/write control
    .i2c_done           (i2c_done), 
    .i2c_data_r         (i2c_data_r),   
    .rstn_out           (rstn_out),       
    .init_done          (init_over)         // flag: all configuration done
    );    

// I2C driver module
i2c_dri #(
    .SLAVE_ADDR         (SLAVE_ADDR),       // parameter pass-through
    .CLK_FREQ           (CLK_FREQ  ),              
    .I2C_FREQ           (I2C_FREQ  ) 
    )
u_i2c_dri(
    .clk                (clk),
    .rst_n              (rst_n     ),

    .i2c_exec           (i2c_exec  ),   
    .bit_ctrl           (BIT_CTRL ),   
    .i2c_rh_wl          (i2c_rh_wl),        // tied to 0: only the I2C write operation is used
    .i2c_addr           ({i2c_data[15:8],i2c_data[23:16]}),   
    .i2c_data_w         (i2c_data[7:0]),   
    .i2c_data_r         (i2c_data_r),   
    .i2c_done           (i2c_done  ),
    
    .scl                (iic_scl   ),   
    .sda                (iic_sda   ),   

    .dri_clk            (i2c_dri_clk)       // I2C operating clock
    );	

    
endmodule
