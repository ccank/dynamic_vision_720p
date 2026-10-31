//==============================================================================
// File        : lcd_driver.v
// Module      : lcd_driver
// Description :
//   RGB LCD parallel timing driver. It generates the panel horizontal/vertical sync, data-enable
//   and pixel clock according to the timing parameters selected by the detected panel ID.
//==============================================================================
module lcd_driver(
    input                lcd_pclk,
    input                rst_n,
    input        [15:0]  lcd_id,
    input        [23:0]  pixel_data,
    output  reg  [10:0]  pixel_xpos,
    output  reg  [10:0]  pixel_ypos,
    output  reg  [10:0]  h_disp,
    output  reg  [10:0]  v_disp,
    output  reg          data_req,

    output  reg          lcd_de,
    output               lcd_hs,
    output               lcd_vs,
    output               lcd_bl,
    output               lcd_clk,
    output               lcd_rst,
    output       [23:0]  lcd_rgb
    );
parameter  H_SYNC_4342   =  11'd41;
parameter  H_BACK_4342   =  11'd2;
parameter  H_DISP_4342   =  11'd480;
parameter  H_FRONT_4342  =  11'd2;
parameter  H_TOTAL_4342  =  11'd525;

parameter  V_SYNC_4342   =  11'd10;
parameter  V_BACK_4342   =  11'd2;
parameter  V_DISP_4342   =  11'd272;
parameter  V_FRONT_4342  =  11'd2;
parameter  V_TOTAL_4342  =  11'd286;

parameter  H_SYNC_7084   =  11'd128;
parameter  H_BACK_7084   =  11'd88;
parameter  H_DISP_7084   =  11'd800;
parameter  H_FRONT_7084  =  11'd40;
parameter  H_TOTAL_7084  =  11'd1056;

parameter  V_SYNC_7084   =  11'd2;
parameter  V_BACK_7084   =  11'd33;
parameter  V_DISP_7084   =  11'd480;
parameter  V_FRONT_7084  =  11'd10;
parameter  V_TOTAL_7084  =  11'd525;

parameter  H_SYNC_7016   =  11'd20;
parameter  H_BACK_7016   =  11'd140;
parameter  H_DISP_7016   =  11'd1024;
parameter  H_FRONT_7016  =  11'd160;
parameter  H_TOTAL_7016  =  11'd1344;

parameter  V_SYNC_7016   =  11'd3;
parameter  V_BACK_7016   =  11'd20;
parameter  V_DISP_7016   =  11'd600;
parameter  V_FRONT_7016  =  11'd12;
parameter  V_TOTAL_7016  =  11'd635;

parameter  H_SYNC_1018   =  11'd10;
parameter  H_BACK_1018   =  11'd80;
parameter  H_DISP_1018   =  11'd1280;
parameter  H_FRONT_1018  =  11'd70;
parameter  H_TOTAL_1018  =  11'd1440;

parameter  V_SYNC_1018   =  11'd3;
parameter  V_BACK_1018   =  11'd10;
parameter  V_DISP_1018   =  11'd800;
parameter  V_FRONT_1018  =  11'd10;
parameter  V_TOTAL_1018  =  11'd823;
parameter  H_SYNC_4384   =  11'd128;
parameter  H_BACK_4384   =  11'd88;
parameter  H_DISP_4384   =  11'd800;
parameter  H_FRONT_4384  =  11'd40;
parameter  H_TOTAL_4384  =  11'd1056;

parameter  V_SYNC_4384   =  11'd2;
parameter  V_BACK_4384   =  11'd33;
parameter  V_DISP_4384   =  11'd480;
parameter  V_FRONT_4384  =  11'd10;
parameter  V_TOTAL_4384  =  11'd525;
reg  [10:0] h_sync ;
reg  [10:0] h_back ;
reg  [10:0] h_total;
reg  [10:0] v_sync ;
reg  [10:0] v_back ;
reg  [10:0] v_total;
reg  [10:0] h_cnt  ;
reg  [10:0] v_cnt  ;
assign  lcd_hs = 1'b1;
assign  lcd_vs = 1'b1;
assign  lcd_bl = 1'b1;
assign  lcd_clk = lcd_pclk;
assign  lcd_rst= 1'b1;
assign lcd_rgb = lcd_de ? pixel_data : 24'd0;
always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        pixel_xpos <= 11'd0;
    else if(data_req)
        pixel_xpos <= h_cnt + 11'd2 - h_sync - h_back ;
    else
        pixel_xpos <= 11'd0;
end

always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        pixel_ypos <= 11'd0;
    else if(v_cnt >= (v_sync + v_back)&&v_cnt < (v_sync + v_back + v_disp))
        pixel_ypos <= v_cnt + 11'd1 - (v_sync + v_back) ;
    else
        pixel_ypos <= 11'd0;
end
always @(*) begin
    case(lcd_id)
        16'h4342 : begin
            h_sync  = H_SYNC_4342;
            h_back  = H_BACK_4342;
            h_disp  = H_DISP_4342;
            h_total = H_TOTAL_4342;
            v_sync  = V_SYNC_4342;
            v_back  = V_BACK_4342;
            v_disp  = V_DISP_4342;
            v_total = V_TOTAL_4342;
        end
        16'h7084 : begin
            h_sync  = H_SYNC_7084;
            h_back  = H_BACK_7084;
            h_disp  = H_DISP_7084;
            h_total = H_TOTAL_7084;
            v_sync  = V_SYNC_7084;
            v_back  = V_BACK_7084;
            v_disp  = V_DISP_7084;
            v_total = V_TOTAL_7084;
        end
        16'h7016 : begin
            h_sync  = H_SYNC_7016;
            h_back  = H_BACK_7016;
            h_disp  = H_DISP_7016;
            h_total = H_TOTAL_7016;
            v_sync  = V_SYNC_7016;
            v_back  = V_BACK_7016;
            v_disp  = V_DISP_7016;
            v_total = V_TOTAL_7016;
        end
        16'h4384 : begin
            h_sync  = H_SYNC_4384;
            h_back  = H_BACK_4384;
            h_disp  = H_DISP_4384;
            h_total = H_TOTAL_4384;
            v_sync  = V_SYNC_4384;
            v_back  = V_BACK_4384;
            v_disp  = V_DISP_4384;
            v_total = V_TOTAL_4384;
        end
        16'h1018 : begin
            h_sync  = H_SYNC_1018;
            h_back  = H_BACK_1018;
            h_disp  = H_DISP_1018;
            h_total = H_TOTAL_1018;
            v_sync  = V_SYNC_1018;
            v_back  = V_BACK_1018;
            v_disp  = V_DISP_1018;
            v_total = V_TOTAL_1018;
        end
        default : begin
            h_sync  = H_SYNC_4342;
            h_back  = H_BACK_4342;
            h_disp  = H_DISP_4342;
            h_total = H_TOTAL_4342;
            v_sync  = V_SYNC_4342;
            v_back  = V_BACK_4342;
            v_disp  = V_DISP_4342;
            v_total = V_TOTAL_4342;
        end
    endcase
end

always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        lcd_de <= 1'b0;
    else
        lcd_de <= data_req;
end

always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        data_req <= 1'b0;
    else if((h_cnt >= h_sync + h_back - 11'd2) && (h_cnt < h_sync + h_back + h_disp - 11'd2)
             && (v_cnt >= v_sync + v_back) && (v_cnt < v_sync + v_back + v_disp))
        data_req <= 1'b1;
    else
        data_req <= 1'b0;
end

always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        h_cnt <= 11'd0;
    else begin
        if(h_cnt == h_total - 11'd1)
            h_cnt <= 11'd0;
        else
            h_cnt <= h_cnt + 11'd1;
    end
end
always@ (posedge lcd_pclk or negedge rst_n) begin
    if(!rst_n)
        v_cnt <= 11'd0;
    else begin
        if(h_cnt == h_total - 11'd1) begin
            if(v_cnt == v_total - 11'd1)
                v_cnt <= 11'd0;
            else
                v_cnt <= v_cnt + 11'd1;
        end
    end
end
endmodule
