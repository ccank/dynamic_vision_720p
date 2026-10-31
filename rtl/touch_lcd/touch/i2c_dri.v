//==============================================================================
// File        : i2c_dri.v
// Module      : touch_i2c_dri
// Description :
//   Dedicated I2C master for the capacitive touch controller. The module is named touch_i2c_dri
//   to distinguish it from the HDMI I2C master; it produces the SCL/SDA waveform for touch reads.
//==============================================================================
module touch_i2c_dri
  #(
    parameter   CLK_FREQ   = 26'd50_000_000,
    parameter   I2C_FREQ   = 18'd250_000   ,
    parameter   WIDTH      = 4'd8
   )(
    input               clk           ,
    input               rst_n         ,

    input        [6:0]  slave_addr    ,
    input               i2c_exec      ,
    input               i2c_rh_wl     ,
    input        [15:0] i2c_addr      ,
    input        [7:0]  i2c_data_w    ,
    input               bit_ctrl      ,
    input   [WIDTH-1:0] reg_num       ,
    output  reg  [7:0]  i2c_data_r    ,
    output  reg         i2c_done      ,
    output  reg         once_byte_done,
    output  reg         scl           ,
    output  reg         ack           ,
    inout               sda           ,

    output  reg         dri_clk
     );
localparam  st_idle     = 8'b0000_0001;
localparam  st_sladdr   = 8'b0000_0010;
localparam  st_addr16   = 8'b0000_0100;
localparam  st_addr8    = 8'b0000_1000;
localparam  st_data_wr  = 8'b0001_0000;
localparam  st_addr_rd  = 8'b0010_0000;
localparam  st_data_rd  = 8'b0100_0000;
localparam  st_stop     = 8'b1000_0000;
reg                      sda_dir     ;
reg                      sda_out     ;
reg                      st_done     ;
reg                      wr_flag     ;
reg    [ 6:0]            cnt         ;
reg    [ 7:0]            cur_state   ;
reg    [ 7:0]            next_state  ;
reg    [15:0]            addr_t      ;
reg    [ 7:0]            data_r      ;
reg    [ 7:0]            data_wr_t   ;
reg    [ 9:0]            clk_cnt     ;
reg    [WIDTH-1'b1:0]    reg_cnt     ;
wire                     sda_in      ;
wire   [8:0]             clk_divide  ;
wire                     reg_done    ;
assign  sda        = sda_dir ?  sda_out : 1'bz;
assign  sda_in     = sda ;
assign  clk_divide = (CLK_FREQ/I2C_FREQ) >> 2'd2;
assign  reg_done   = reg_cnt == reg_num ? 1'b1 : 1'b0;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 1'b0) begin
        dri_clk <=  1'b1;
        clk_cnt <= 10'd0;
    end
    else if(clk_cnt == clk_divide - 10'd1) begin
        clk_cnt <= 10'd0;
        dri_clk <= ~dri_clk;
    end
    else
        clk_cnt <= clk_cnt + 10'd1;
end
always @(posedge dri_clk or negedge rst_n) begin
    if(!rst_n)
        reg_cnt <= 8'd0;
    else if(once_byte_done)
        reg_cnt <= reg_cnt + 8'd1;
    else if(i2c_done)
        reg_cnt <= 8'd0;
end
always @(posedge dri_clk or negedge rst_n) begin
    if(rst_n == 1'b0)
        cur_state <= st_idle;
    else
        cur_state <= next_state;
end
always @( * ) begin
    case(cur_state)
        st_idle: begin
           if(i2c_exec) begin
               next_state = st_sladdr;
           end
           else
               next_state = st_idle;
        end
        st_sladdr: begin
            if(st_done) begin
                if(!ack) begin
                    if(bit_ctrl)
                        next_state = st_addr16;
                    else
                        next_state = st_addr8 ;
                end
                else
                    next_state = st_stop;
            end
            else
                next_state = st_sladdr;
        end
        st_addr16: begin
            if(st_done) begin
                if(!ack)
                    next_state = st_addr8;
                else
                    next_state = st_stop;
            end
            else
                next_state = st_addr16;
        end
        st_addr8: begin
            if(st_done) begin
                if(!ack) begin
                    if(wr_flag==1'b0)
                        next_state = st_data_wr;
                    else
                        next_state = st_addr_rd;
                end
                else
                    next_state = st_stop;
            end
            else
                next_state = st_addr8;
        end
        st_data_wr: begin
            if(st_done) begin
                if(reg_done)
                    next_state = st_stop;
                else
                    next_state = st_data_wr;
            end
            else
                next_state = st_data_wr;
        end
        st_addr_rd: begin
            if(st_done) begin
                if(!ack)
                    next_state = st_data_rd;
                else
                    next_state = st_stop;
            end
            else
                next_state = st_addr_rd;
        end
        st_data_rd: begin
            if(st_done) begin
                if(reg_done)
                    next_state = st_stop;
                else
                    next_state = st_data_rd;
            end
            else
                next_state = st_data_rd;
        end
        st_stop: begin
            if(st_done)
                next_state = st_idle;
            else
                next_state = st_stop ;
        end
        default: next_state= st_idle;
    endcase
end
always @(posedge dri_clk or negedge rst_n) begin

    if(rst_n == 1'b0) begin
        scl             <= 1'b1;
        sda_out         <= 1'b1;
        sda_dir         <= 1'b1;
        i2c_done        <= 1'b0;
        ack             <= 1'b0;
        cnt             <= 7'd0;
        st_done         <= 1'b0;
        once_byte_done  <= 1'b0;
        data_r          <= 8'd0;
        i2c_data_r      <= 8'd0;
        wr_flag         <= 1'b0;
        addr_t          <= 16'd0;
        data_wr_t       <= 8'd0;
    end
    else begin
        st_done        <= 1'b0 ;
        once_byte_done <= 1'b0;
        cnt            <= cnt + 7'd1 ;
        case(cur_state)
             st_idle: begin
                scl     <= 1'b1;
                sda_out <= 1'b1;
                sda_dir <= 1'b1;
                i2c_done<= 1'b0;
                cnt     <= 7'b0;
                if(i2c_exec) begin
                    wr_flag   <= i2c_rh_wl ;
                    addr_t    <= i2c_addr  ;
                    data_wr_t <= i2c_data_w;
                end
            end
            st_sladdr: begin
                case(cnt)
                    7'd1 : begin
                        sda_dir <= 1'b1 ;
                        sda_out <= 1'b0;
                    end
                    7'd3 : scl <= 1'b0;
                    7'd4 : sda_out <= slave_addr[6];
                    7'd5 : scl <= 1'b1;
                    7'd7 : scl <= 1'b0;
                    7'd8 : sda_out <= slave_addr[5];
                    7'd9 : scl <= 1'b1;
                    7'd11: scl <= 1'b0;
                    7'd12: sda_out <= slave_addr[4];
                    7'd13: scl <= 1'b1;
                    7'd15: scl <= 1'b0;
                    7'd16: sda_out <= slave_addr[3];
                    7'd17: scl <= 1'b1;
                    7'd19: scl <= 1'b0;
                    7'd20: sda_out <= slave_addr[2];
                    7'd21: scl <= 1'b1;
                    7'd23: scl <= 1'b0;
                    7'd24: sda_out <= slave_addr[1];
                    7'd25: scl <= 1'b1;
                    7'd27: scl <= 1'b0;
                    7'd28: sda_out <= slave_addr[0];
                    7'd29: scl <= 1'b1;
                    7'd31: scl <= 1'b0;
                    7'd32: sda_out <= 1'b0;
                    7'd33: scl <= 1'b1;
                    7'd35: scl <= 1'b0;
                    7'd36: begin
                        sda_dir <= 1'b0;
                        sda_out <= 1'b1;
                    end
                    7'd37: begin
                        scl <= 1'b1;
                        ack <= sda_in;
                    end
                    7'd42: st_done <= 1'b1;
                    7'd43: begin
                        scl <= 1'b0;
                        cnt <= 7'd0;
                    end
                    default :  ;
                endcase
            end
            st_addr16: begin
                case(cnt)
                    7'd0 : begin
                        sda_dir <= 1'b1 ;
                        sda_out <= addr_t[15];
                    end
                    7'd1 : scl <= 1'b1;
                    7'd3 : scl <= 1'b0;
                    7'd4 : sda_out <= addr_t[14];
                    7'd5 : scl <= 1'b1;
                    7'd7 : scl <= 1'b0;
                    7'd8 : sda_out <= addr_t[13];
                    7'd9 : scl <= 1'b1;
                    7'd11: scl <= 1'b0;
                    7'd12: sda_out <= addr_t[12];
                    7'd13: scl <= 1'b1;
                    7'd15: scl <= 1'b0;
                    7'd16: sda_out <= addr_t[11];
                    7'd17: scl <= 1'b1;
                    7'd19: scl <= 1'b0;
                    7'd20: sda_out <= addr_t[10];
                    7'd21: scl <= 1'b1;
                    7'd23: scl <= 1'b0;
                    7'd24: sda_out <= addr_t[9];
                    7'd25: scl <= 1'b1;
                    7'd27: scl <= 1'b0;
                    7'd28: sda_out <= addr_t[8];
                    7'd29: scl <= 1'b1;
                    7'd31: scl <= 1'b0;
                    7'd32: begin
                        sda_dir <= 1'b0;
                        sda_out <= 1'b1;
                    end
                    7'd33:  begin
                        scl <= 1'b1;
                        ack <= sda_in;
                    end
                    7'd38: st_done <= 1'b1;
                    7'd39: begin
                        scl <= 1'b0;
                        cnt <= 7'd0;
                    end
                    default :  ;
                endcase
            end
            st_addr8: begin
                case(cnt)
                    7'd0: begin
                       sda_dir <= 1'b1 ;
                       sda_out <= addr_t[7];
                    end
                    7'd1 : scl <= 1'b1;
                    7'd3 : scl <= 1'b0;
                    7'd4 : sda_out <= addr_t[6];
                    7'd5 : scl <= 1'b1;
                    7'd7 : scl <= 1'b0;
                    7'd8 : sda_out <= addr_t[5];
                    7'd9 : scl <= 1'b1;
                    7'd11: scl <= 1'b0;
                    7'd12: sda_out <= addr_t[4];
                    7'd13: scl <= 1'b1;
                    7'd15: scl <= 1'b0;
                    7'd16: sda_out <= addr_t[3];
                    7'd17: scl <= 1'b1;
                    7'd19: scl <= 1'b0;
                    7'd20: sda_out <= addr_t[2];
                    7'd21: scl <= 1'b1;
                    7'd23: scl <= 1'b0;
                    7'd24: sda_out <= addr_t[1];
                    7'd25: scl <= 1'b1;
                    7'd27: scl <= 1'b0;
                    7'd28: sda_out <= addr_t[0];
                    7'd29: scl <= 1'b1;
                    7'd31: scl <= 1'b0;
                    7'd32: begin
                        sda_dir <= 1'b0;
                        sda_out <= 1'b1;
                    end
                    7'd33:  begin
                        scl <= 1'b1;
                        ack <= sda_in;
                    end
                    7'd38: st_done <= 1'b1;
                    7'd39: begin
                        scl <= 1'b0;
                        cnt <= 7'd0;
                    end
                    default :  ;
                endcase
            end
            st_data_wr: begin
                case(cnt)
                    7'd0: begin
                        sda_out <= i2c_data_w[7];
                        data_wr_t <= i2c_data_w;
                        sda_dir <= 1'b1;
                    end
                    7'd1 : scl <= 1'b1;
                    7'd3 : scl <= 1'b0;
                    7'd4 : sda_out <= data_wr_t[6];
                    7'd5 : scl <= 1'b1;
                    7'd7 : scl <= 1'b0;
                    7'd8 : sda_out <= data_wr_t[5];
                    7'd9 : scl <= 1'b1;
                    7'd11: scl <= 1'b0;
                    7'd12: sda_out <= data_wr_t[4];
                    7'd13: scl <= 1'b1;
                    7'd15: scl <= 1'b0;
                    7'd16: sda_out <= data_wr_t[3];
                    7'd17: scl <= 1'b1;
                    7'd19: scl <= 1'b0;
                    7'd20: sda_out <= data_wr_t[2];
                    7'd21: scl <= 1'b1;
                    7'd23: scl <= 1'b0;
                    7'd24: sda_out <= data_wr_t[1];
                    7'd25: scl <= 1'b1;
                    7'd27: scl <= 1'b0;
                    7'd28: sda_out <= data_wr_t[0];
                    7'd29: scl <= 1'b1;
                    7'd31: scl <= 1'b0;
                    7'd32: begin
                        sda_dir        <= 1'b0;
                        sda_out        <= 1'b1;
                        once_byte_done <= 1'b1;
                    end
                    7'd33:  begin
                        scl <= 1'b1;
                        ack <= sda_in;
                    end
                    7'd38: st_done <= 1'b1;
                    7'd39: begin
                        scl  <= 1'b0;
                        cnt  <= 7'd0;
                    end
                    default  :  ;
                endcase
            end
            st_addr_rd: begin
                case(cnt)
                    7'd0 : begin
                        sda_dir <= 1'b1;
                        sda_out <= 1'b1;
                    end
                    7'd1 : scl <= 1'b1;
                    7'd2 : sda_out <= 1'b0;
                    7'd3 : scl <= 1'b0;
                    7'd4 : sda_out <= slave_addr[6];
                    7'd5 : scl <= 1'b1;
                    7'd7 : scl <= 1'b0;
                    7'd8 : sda_out <= slave_addr[5];
                    7'd9 : scl <= 1'b1;
                    7'd11: scl <= 1'b0;
                    7'd12: sda_out <= slave_addr[4];
                    7'd13: scl <= 1'b1;
                    7'd15: scl <= 1'b0;
                    7'd16: sda_out <= slave_addr[3];
                    7'd17: scl <= 1'b1;
                    7'd19: scl <= 1'b0;
                    7'd20: sda_out <= slave_addr[2];
                    7'd21: scl <= 1'b1;
                    7'd23: scl <= 1'b0;
                    7'd24: sda_out <= slave_addr[1];
                    7'd25: scl <= 1'b1;
                    7'd27: scl <= 1'b0;
                    7'd28: sda_out <= slave_addr[0];
                    7'd29: scl <= 1'b1;
                    7'd31: scl <= 1'b0;
                    7'd32: sda_out <= 1'b1;
                    7'd33: scl <= 1'b1;
                    7'd35: scl <= 1'b0;
                    7'd36: begin
                        sda_dir <= 1'b0;
                        sda_out <= 1'b1;
                    end
                    7'd37:  begin
                        scl <= 1'b1;
                        ack <= sda_in;
                    end
                    7'd42: st_done <= 1'b1;
                    7'd43: begin
                        scl <= 1'b0;
                        cnt <= 7'd0;
                    end
                    default : ;
                endcase
            end
            st_data_rd: begin
                case(cnt)
                    7'd0: sda_dir <= 1'b0;
                    7'd1: begin
                        data_r[7] <= sda_in;
                        scl       <= 1'b1;
                    end
                    7'd3: scl  <= 1'b0;
                    7'd5: begin
                        data_r[6] <= sda_in ;
                        scl       <= 1'b1   ;
                    end
                    7'd7: scl  <= 1'b0;
                    7'd9: begin
                        data_r[5] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd11: scl  <= 1'b0;
                    7'd13: begin
                        data_r[4] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd15: scl  <= 1'b0;
                    7'd17: begin
                        data_r[3] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd19: scl  <= 1'b0;
                    7'd21: begin
                        data_r[2] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd23: scl  <= 1'b0;
                    7'd25: begin
                        data_r[1] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd27: scl  <= 1'b0;
                    7'd29: begin
                        data_r[0] <= sda_in;
                        scl       <= 1'b1  ;
                    end
                    7'd31: scl  <= 1'b0;
                    7'd32: begin
                        if(reg_cnt == reg_cnt - 1'b1) begin
                            sda_dir <= 1'b1;
                            sda_out <= 1'b1;
                        end
                        else begin
                            sda_dir <= 1'b1;
                            sda_out <= 1'b0;
                        end
                    end
                    7'd33: begin
                        scl             <= 1'b1;
                        once_byte_done  <= 1'b1;
                        i2c_data_r      <= data_r;
                    end
                    7'd38: st_done <= 1'b1;
                    7'd39: begin
                        scl <= 1'b0;
                        cnt <= 7'd0;
                    end
                    default  :  ;
                endcase
            end
            st_stop: begin
                case(cnt)
                    7'd0: begin
                        sda_dir <= 1'b1;
                        sda_out <= 1'b0;
                    end
                    7'd1: scl     <= 1'b1;
                    7'd3: sda_out <= 1'b1;
                    7'd5: st_done <= 1'b1;
                    7'd6: begin
                        cnt      <= 7'd0;
                        i2c_done <= 1'b1;
                    end
                    default  : ;
                endcase
            end
        endcase
    end
end
endmodule
