//==============================================================================
// File        : touch_top.v
// Module      : touch_top
// Description :
//   Capacitive-touch sub-system wrapper. It connects the dedicated I2C master and the touch
//   controller and presents the parsed touch point and press flag to the UI logic.
//==============================================================================
module touch_top(
    input             clk        ,
    input             rst_n      ,

    output            touch_rst_n,
    inout             touch_int  ,
    output            touch_scl  ,
    inout             touch_sda  ,

    input     [15:0]  lcd_id     ,
    output    [31:0]  data         ,
    output            touch_valid
);
parameter CLK_FREQ = 50_000_000   ;
parameter I2C_FREQ = 250_000      ;
parameter REG_NUM_WID = 8         ;

wire  [6:0]             slave_addr     ;
wire                    i2c_exec       ;
wire                    i2c_rh_wl      ;
wire  [15:0]            i2c_addr       ;
wire  [7:0]             i2c_data_w     ;
wire                    bit_ctrl       ;
wire  [REG_NUM_WID-1:0] reg_num        ;
wire  [7:0]             i2c_data_r     ;
wire                    i2c_done       ;
wire                    once_byte_done ;
wire                    i2c_ack        ;
wire                    dri_clk        ;
touch_i2c_dri  #(
    .CLK_FREQ      (CLK_FREQ     ),
    .I2C_FREQ      (I2C_FREQ     ),
    .WIDTH         (REG_NUM_WID  )
    )
    u_i2c_dri(
    .clk           (clk          ),
    .rst_n         (rst_n        ),

    .slave_addr    (slave_addr    ),
    .i2c_exec      (i2c_exec      ),
    .i2c_rh_wl     (i2c_rh_wl     ),
    .i2c_addr      (i2c_addr      ),
    .i2c_data_w    (i2c_data_w    ),
    .bit_ctrl      (bit_ctrl      ),
    .reg_num       (reg_num       ),
    .i2c_data_r    (i2c_data_r    ),
    .i2c_done      (i2c_done      ),
    .once_byte_done(once_byte_done),
    .scl           (touch_scl     ),
    .sda           (touch_sda     ),
    .ack           (i2c_ack       ),
    .dri_clk       (dri_clk       )
    );
touch_dri  #(
    .WIDTH         (REG_NUM_WID   )
     )
    u_touch_dri(
    .clk           (dri_clk       ),
    .rst_n         (rst_n         ),

    .slave_addr    (slave_addr    ),
    .i2c_exec      (i2c_exec      ),
    .i2c_rh_wl     (i2c_rh_wl     ),
    .i2c_addr      (i2c_addr      ),
    .i2c_data_w    (i2c_data_w    ),
    .bit_ctrl      (bit_ctrl      ),
    .reg_num       (reg_num       ),

    .i2c_data_r    (i2c_data_r    ),
    .i2c_ack       (i2c_ack       ),
    .i2c_done      (i2c_done      ),
    .once_byte_done(once_byte_done),

    .lcd_id        (lcd_id        ),
    .data          (data          ),
    .touch_rst_n   (touch_rst_n   ),
    .touch_int     (touch_int     ),
    .touch_valid   (touch_valid   )
    );
endmodule
