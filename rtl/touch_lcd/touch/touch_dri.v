//==============================================================================
// File        : touch_dri.v
// Module      : touch_dri
// Description :
//   Capacitive touch controller (GT9147 class). It manages the register reads over I2C and
//   parses the active touch point coordinates and press/release status.
//==============================================================================
module touch_dri #(parameter   WIDTH = 4'd8)
(
    input                   clk           ,
    input                   rst_n         ,

    output  reg [6:0]       slave_addr    ,
    output  reg             i2c_exec      ,
    output  reg             i2c_rh_wl     ,
    output  reg [15:0]      i2c_addr      ,
    output  reg [7:0]       i2c_data_w    ,
    output  reg             bit_ctrl      ,
    output  reg [WIDTH-1:0] reg_num       ,

    input       [7:0]       i2c_data_r    ,
    input                   i2c_ack       ,
    input                   i2c_done      ,
    input                   once_byte_done,

    input       [15:0]      lcd_id        ,
    output  reg [31:0]      data          ,
    output  reg             touch_rst_n   ,
    output  reg             touch_valid   ,
    inout                   touch_int
 );
localparam FT_SLAVE_ADDR    = 7'h38;
localparam FT_BIT_CTRL      = 1'b0;

localparam FT_ID_LIB_VERSION= 8'hA1;
localparam FT_DEVIDE_MODE   = 8'h00;
localparam FT_ID_MODE       = 8'hA4;
localparam FT_ID_THGROUP    = 8'h80;
localparam FT_ID_PERIOD_ACT = 8'h88;
localparam FT_STATE_REG     = 8'h02;
localparam FT_TP1_REG       = 8'h03;
localparam GT_SLAVE_ADDR    = 7'h14;
localparam GT_BIT_CTRL      = 1'b1;
localparam GT_STATE_REG     = 16'h814E;
localparam GT_TP1_REG       = 16'h8150;
localparam st_idle          = 7'b000_0001;
localparam st_init          = 7'b000_0010;
localparam st_get_id        = 7'b000_0100;
localparam st_cfg_reg       = 7'b000_1000;
localparam st_check_touch   = 7'b001_0000;
localparam st_get_coord     = 7'b010_0000;
localparam st_coord_handle  = 7'b100_0000;
reg                 touch_int_dir;
reg                 touch_int_out;
reg    [6:0]        cur_state   ;
reg    [6:0]        next_state  ;
reg                 cnt_time_en ;
reg    [19:0]       cnt_time    ;
reg    [15:0]       chip_version;
reg                 ft_flag     ;
reg    [15:0]       touch_s_reg ;
reg    [15:0]       coord_reg   ;
reg    [15:0]       tp_x_coord_t;
reg    [15:0]       tp_y_coord_t;
reg    [3:0]        flow_cnt    ;
reg                 st_done     ;
reg    [15:0]       tp_x_coord  ;
reg    [15:0]       tp_y_coord  ;
wire          touch_int_in ;
assign touch_int = touch_int_dir ? touch_int_out : 1'bz;
assign touch_int_in = touch_int;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt_time <= 20'd0;
    end
    else if(cnt_time_en)
        cnt_time <= cnt_time + 20'd1;
    else
        cnt_time <= 20'd0;
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        data <= 32'd0;
    end
    else if(touch_valid)
        data <= {tp_x_coord,tp_y_coord};
    else
        data <= data;
end
always @ (posedge clk or negedge rst_n) begin
    if(!rst_n)
        cur_state <= st_idle;
    else
        cur_state <= next_state;
end
always @(*) begin
    case(cur_state)
        st_idle : begin
            if(st_done)
                next_state = st_init;
            else
                next_state = st_idle;
        end
        st_init : begin
            if(st_done)
                next_state = st_get_id;
            else
                next_state = st_init;
        end
        st_get_id : begin
            if(st_done) begin
                if(ft_flag)
                    next_state = st_cfg_reg;
                else
                    next_state = st_check_touch;
            end
            else
                next_state = st_get_id;
        end
        st_cfg_reg : begin
            if(st_done)
                next_state = st_check_touch;
            else
                next_state = st_cfg_reg;
        end
        st_check_touch: begin
            if(st_done)
                next_state = st_get_coord;
            else
                next_state = st_check_touch;
        end
        st_get_coord : begin
            if(st_done)
                next_state = st_coord_handle;
            else
                next_state = st_get_coord;
        end
        st_coord_handle : begin
            if(st_done)
                next_state = st_check_touch;
            else
                next_state = st_coord_handle;
        end
        default: next_state = st_idle;
    endcase
end
always @ (posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt_time_en  <= 1'b0;
        chip_version <= 16'd0;
        ft_flag      <= 1'b0;
        touch_s_reg  <= 16'd0;
        coord_reg    <= 16'd0;
        tp_x_coord_t <= 16'd0;
        tp_y_coord_t <= 16'd0;
        flow_cnt     <= 4'd0;
        st_done      <= 1'b0;
        touch_int_dir<= 1'b0;
        touch_int_out<= 1'b0;

        slave_addr   <= 7'd0;
        i2c_exec     <= 1'b0;
        i2c_rh_wl    <= 1'b0;
        i2c_addr     <= 16'd0;
        i2c_data_w   <= 8'd0;
        bit_ctrl     <= 1'b0;
        reg_num      <= 8'd0;

        touch_valid  <= 1'b0;
        tp_x_coord   <= 16'd0;
        tp_y_coord   <= 16'd0;
        touch_rst_n  <= 1'b0;
    end
    else begin
        i2c_exec <= 1'b0;
        st_done <= 1'b0;
        case(next_state)
            st_idle : begin
                cnt_time_en   <= 1'b1;
                touch_int_dir <= 1'b1;
                touch_int_out <= 1'b1;
                if(cnt_time >= 10) begin
                    st_done     <= 1'b1;
                    cnt_time_en <= 1'b0;
                end
            end
            st_init : begin
                cnt_time_en <= 1'b1;
                if(cnt_time < 10_000)
                    touch_rst_n <= 1'b0;
                else if(cnt_time == 10_000)
                    touch_rst_n <= 1'b1;
                else if(cnt_time == 60_000) begin
                    touch_int_dir <= 1'b0;
                    cnt_time_en   <= 1'b0;
                    st_done       <= 1'b1;
                    flow_cnt      <= 4'd0;
                end
            end
            st_get_id : begin
                case(flow_cnt)
                    'd0 : begin

                        if(lcd_id == 16'h4384 || lcd_id == 16'h4342 ||
                        lcd_id == 16'h1018) begin
                            flow_cnt <= 4'd5;
                            ft_flag  <= 1'b0;
                        end
                        else
                            flow_cnt <= flow_cnt + 4'd1;
                    end
                    'd1 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b1;
                        i2c_addr   <= FT_ID_LIB_VERSION;
                        reg_num    <= 8'd2;
                        slave_addr <= FT_SLAVE_ADDR;
                        bit_ctrl   <= FT_BIT_CTRL;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd2 : begin
                        if(once_byte_done) begin
                            chip_version[15:8] <= i2c_data_r;
                            flow_cnt <= flow_cnt + 4'd1;
                        end
                        else if(i2c_done && i2c_ack) begin
                            chip_version = "GT";
                            flow_cnt <= 4'd4;
                        end
                    end
                    'd3 : begin
                        if(i2c_done) begin
                            chip_version[7:0] <= i2c_data_r;
                            flow_cnt <= flow_cnt + 4'd1;
                        end
                    end
                    'd4 : begin
                        flow_cnt <= flow_cnt + 4'd1;

                        if(chip_version == 16'h3003 || chip_version == 16'h0001
                        || chip_version == 16'h0002 || chip_version == 16'h0000)
                            ft_flag <= 1'b1;
                        else
                            ft_flag <= 1'b0;
                    end
                    'd5 : begin
                        st_done <= 1'b1;
                        flow_cnt <= 4'd0;
                        if(ft_flag) begin
                            touch_s_reg <= FT_STATE_REG;
                            coord_reg   <= FT_TP1_REG;
                            bit_ctrl    <= FT_BIT_CTRL;
                            slave_addr  <= FT_SLAVE_ADDR;
                        end
                        else begin
                            touch_s_reg <= GT_STATE_REG;
                            coord_reg   <= GT_TP1_REG;
                            bit_ctrl    <= GT_BIT_CTRL;
                            slave_addr  <= GT_SLAVE_ADDR;
                        end
                    end
                    default :;
                endcase
            end
            st_cfg_reg : begin
                case(flow_cnt)

                    'd0 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b0;
                        i2c_addr   <= FT_DEVIDE_MODE;
                        i2c_data_w <= 8'd0;
                        reg_num    <= 8'd1;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd1 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0)
                                flow_cnt <= flow_cnt + 4'd1;
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    'd2 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b0;
                        i2c_addr   <= FT_ID_MODE;
                        i2c_data_w <= 8'd0;
                        reg_num    <= 8'd1;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd3 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0)
                                flow_cnt <= flow_cnt + 4'd1;
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    'd4 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b0;
                        i2c_addr   <= FT_ID_THGROUP;
                        i2c_data_w <= 8'd22;
                        reg_num    <= 8'd1;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd5 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0)
                                flow_cnt <= flow_cnt + 4'd1;
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    'd6 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b0;
                        i2c_addr   <= FT_ID_PERIOD_ACT;
                        i2c_data_w <= 8'd12;
                        reg_num    <= 8'd1;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd7 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0) begin
                                flow_cnt <= 4'd0;
                                st_done  <= 1'b1;
                            end
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    default : ;
                endcase
            end
            st_check_touch : begin
                case(flow_cnt)
                    'd0: begin
                        cnt_time_en <= 1'b1;
                        if(cnt_time == 20_000) begin
                            flow_cnt    <= flow_cnt + 4'd1;
                            cnt_time_en <= 1'b0;
                        end
                    end
                    'd1 : begin
                        i2c_exec  <= 1'b1;
                        i2c_rh_wl <= 1'b1;
                        i2c_addr  <= touch_s_reg;
                        reg_num   <= 8'd1;
                        flow_cnt  <= flow_cnt + 4'd1;
                    end
                    'd2 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0)
                                flow_cnt <= flow_cnt + 4'd1;
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    'd3 : begin
                        flow_cnt <= flow_cnt + 4'd1;
                        if(ft_flag) begin
                            if(i2c_data_r[3:0] > 4'd0 && i2c_data_r[3:0] <= 4'd5)
                                touch_valid <= 1'b1;
                            else
                                touch_valid <= 1'b0;
                        end
                        else begin
                            if(i2c_data_r[7]== 1'b1 && i2c_data_r[3:0] > 4'd0
                            && i2c_data_r[3:0] <= 4'd5) begin
                                touch_valid <= 1'b1;
                            end
                            else
                                touch_valid <= 1'b0;
                        end
                    end
                    'd4 : begin
                        i2c_exec   <= 1'b1;
                        i2c_rh_wl  <= 1'b0;
                        i2c_addr   <= touch_s_reg;
                        i2c_data_w <= 8'd0;
                        reg_num    <= 8'd1;
                        flow_cnt   <= flow_cnt + 4'd1;
                    end
                    'd5 : begin
                        if(i2c_done) begin
                            if(i2c_ack == 1'b0) begin
                                st_done  <= touch_valid;
                                flow_cnt <= 4'd0;
                            end
                            else
                                flow_cnt <= flow_cnt - 4'd1;
                        end
                    end
                    default : ;
                endcase
            end
            st_get_coord : begin
                case(flow_cnt)
                    'd0 : begin
                        i2c_exec  <= 1'b1;
                        i2c_rh_wl <= 1'b1;
                        i2c_addr  <= coord_reg;
                        reg_num   <= 8'd4;
                        flow_cnt  <= flow_cnt + 4'd1;
                    end
                    'd1 : begin
                        if(once_byte_done) begin
                            if(i2c_ack == 1'b0) begin
                                tp_x_coord_t[7:0] <= i2c_data_r;
                                flow_cnt <= flow_cnt + 4'd1;
                            end
                            else
                                flow_cnt <= 4'd0;
                        end
                    end
                    'd2 : begin
                        if(once_byte_done) begin
                            flow_cnt <= flow_cnt + 4'd1;
                            tp_x_coord_t[15:8] <= i2c_data_r;
                        end
                    end
                    'd3 : begin
                        if(once_byte_done) begin
                            flow_cnt <= flow_cnt + 4'd1;
                            tp_y_coord_t[7:0] <= i2c_data_r;
                        end
                    end
                    'd4 : begin
                        if(once_byte_done) begin
                            st_done  <= 1'b1;
                            flow_cnt <= 4'd0;
                            tp_y_coord_t[15:8] <= i2c_data_r;
                        end
                    end
                    default:;
                endcase
            end
            st_coord_handle : begin
                st_done <= 1'b1;
                if(ft_flag) begin
                    tp_x_coord <= {4'd0,tp_y_coord_t[3:0],tp_y_coord_t[15:8]};
                    tp_y_coord <= {4'd0,tp_x_coord_t[3:0],tp_x_coord_t[15:8]};
                end
                else begin
                    tp_x_coord <= tp_x_coord_t;
                    tp_y_coord <= tp_y_coord_t;
                end
            end
            default : ;
        endcase
    end
end
endmodule
