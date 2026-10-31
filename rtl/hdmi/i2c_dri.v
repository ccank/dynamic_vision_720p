//==============================================================================
// File        : i2c_dri.v
// Module      : i2c_dri
// Description :
//   Generic I2C bus master. It generates start/stop/ack and the SCL/SDA waveform used to
//   configure the HDMI transmitter register set.
//==============================================================================
module i2c_dri
    #(
      parameter   SLAVE_ADDR = 7'b1010000   ,  // I2C slave address
      parameter   CLK_FREQ   = 26'd50_000_000, // input clock frequency of the module
      parameter   I2C_FREQ   = 18'd250_000     // I2C SCL clock frequency
    )
   (                                                            
    input                clk        ,    
    input                rst_n      ,   
                                         
    //i2c interface                      
    input                i2c_exec   ,  // I2C execution trigger
    input                bit_ctrl   ,  // word-address width control (16-bit / 8-bit)
    input                i2c_rh_wl  ,  // I2C read/write control
    input        [15:0]  i2c_addr   ,  // internal device address
    input        [7:0]   i2c_data_w ,  // data to write over I2C
    output  reg  [7:0]   i2c_data_r ,  // data read back over I2C
    output  reg          i2c_done   ,  // one I2C operation complete
    output  reg          i2c_ack    ,  // I2C acknowledge flag: 0 = ack, 1 = nack
    output  reg          scl        ,  // I2C SCL clock
    inout                 sda        ,  // I2C SDA signal
//    input                 sda_in,
//    output                sda_out,
//    output                sda_dir,    


                                       
    //user interface                   
    output  reg          dri_clk       // driving clock for the I2C operation
     );

//localparam define
localparam  st_idle     = 8'b0000_0001; // idle state
localparam  st_sladdr   = 8'b0000_0010; // send slave address
localparam  st_addr16   = 8'b0000_0100; // send 16-bit word address
localparam  st_addr8    = 8'b0000_1000; // send 8-bit word address
localparam  st_data_wr  = 8'b0001_0000; // write data (8 bit)
localparam  st_addr_rd  = 8'b0010_0000; // send slave address for read
localparam  st_data_rd  = 8'b0100_0000; // read data (8 bit)
localparam  st_stop     = 8'b1000_0000; // stop: end the I2C operation

//reg define
reg            sda_dir   ; // SDA direction control
reg            sda_out   ; // SDA output
reg            st_done   ; // state-done flag
reg            wr_flag   ; // write flag
reg    [ 6:0]  cnt       ; // counter
reg    [ 7:0]  cur_state ; // FSM current state
reg    [ 7:0]  next_state; // FSM next state
reg    [15:0]  addr_t    ; // address
reg    [ 7:0]  data_r    ; // read data
reg    [ 7:0]  data_wr_t ; // temporary register for the data to write
reg    [ 9:0]  clk_cnt   ; // divided clock counter

//wire define
wire          sda_in     ; // SDA input
wire   [8:0]  clk_divide ; // clock divider factor for the module driving clock

//*****************************************************
//**                    main code
//*****************************************************

// SDA control
assign  sda     = sda_dir ?  sda_out : 1'bz;     // SDA drives data out or goes high-impedance
assign  sda_in  = sda ;                          // SDA input
assign  clk_divide = (CLK_FREQ/I2C_FREQ) >> 2'd2;// clock divider factor for the module driving clock

// Generate a driving clock at four times the I2C SCL frequency to run the I2C operation
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dri_clk <=  1'b0;
        clk_cnt <= 10'd0;
    end
    else if(clk_cnt == clk_divide[8:1] - 1'd1) begin
        clk_cnt <= 10'd0;
        dri_clk <= ~dri_clk;
    end
    else
        clk_cnt <= clk_cnt + 1'b1;
end

// (three-process FSM) sequential process: state transition
always @(posedge dri_clk or negedge rst_n) begin
    if(!rst_n)
        cur_state <= st_idle;
    else
        cur_state <= next_state;
end

// combinational process: state transition conditions
always @(*) begin
    next_state = st_idle;
    case(cur_state)
        st_idle: begin                          // idle state
           if(i2c_exec) begin
               next_state = st_sladdr;
           end
           else
               next_state = st_idle;
        end
        st_sladdr: begin
            if(st_done) begin
                if(bit_ctrl)                    // select 16-bit or 8-bit word address
                   next_state = st_addr16;
                else
                   next_state = st_addr8 ;
            end
            else
                next_state = st_sladdr;
        end
        st_addr16: begin                        // write 16-bit word address
            if(st_done) begin
                next_state = st_addr8;
            end
            else begin
                next_state = st_addr16;
            end
        end
        st_addr8: begin                         // 8-bit word address
            if(st_done) begin
                if(wr_flag==1'b0)               // read/write decision
                    next_state = st_data_wr;
                else
                    next_state = st_addr_rd;
            end
            else begin
                next_state = st_addr8;
            end
        end
        st_data_wr: begin                       // write data (8 bit)
            if(st_done)
                next_state = st_stop;
            else
                next_state = st_data_wr;
        end
        st_addr_rd: begin                       // write address in order to read data
            if(st_done) begin
                next_state = st_data_rd;
            end
            else begin
                next_state = st_addr_rd;
            end
        end
        st_data_rd: begin                       // read data (8 bit)
            if(st_done)
                next_state = st_stop;
            else
                next_state = st_data_rd;
        end
        st_stop: begin                          // stop: end the I2C operation
            if(st_done)
                next_state = st_idle;
            else
                next_state = st_stop ;
        end
        default: next_state= st_idle;
    endcase
end

// sequential process: state outputs
always @(posedge dri_clk or negedge rst_n) begin
    // reset initialization
    if(!rst_n) begin
        scl       <= 1'b1;
        sda_out   <= 1'b1;
        sda_dir   <= 1'b1;                          
        i2c_done  <= 1'b0;                          
        i2c_ack   <= 1'b0;                          
        cnt       <= 1'b0;                          
        st_done   <= 1'b0;                          
        data_r    <= 1'b0;                          
        i2c_data_r<= 1'b0;                          
        wr_flag   <= 1'b0;                          
        addr_t    <= 1'b0;                          
        data_wr_t <= 1'b0;                          
    end                                              
    else begin                                       
        st_done <= 1'b0 ;                            
        cnt     <= cnt +1'b1 ;                       
        case(cur_state)                              
             st_idle: begin                          // idle state
                scl     <= 1'b1;                     
                sda_out <= 1'b1;                     
                sda_dir <= 1'b1;                     
                i2c_done<= 1'b0;                     
                cnt     <= 7'b0;               
                if(i2c_exec) begin                   
                    wr_flag   <= i2c_rh_wl ;         
                    addr_t    <= i2c_addr  ;         
                    data_wr_t <= i2c_data_w;  
                    i2c_ack <= 1'b0;                      
                end                                  
            end                                      
            st_sladdr: begin                         // write address (slave address and word address)
                case(cnt)                            
                    7'd1 : sda_out <= 1'b0;          // start I2C
                    7'd3 : scl <= 1'b0;              
                    7'd4 : sda_out <= SLAVE_ADDR[6]; // send slave address
                    7'd5 : scl <= 1'b1;              
                    7'd7 : scl <= 1'b0;              
                    7'd8 : sda_out <= SLAVE_ADDR[5]; 
                    7'd9 : scl <= 1'b1;              
                    7'd11: scl <= 1'b0;              
                    7'd12: sda_out <= SLAVE_ADDR[4]; 
                    7'd13: scl <= 1'b1;              
                    7'd15: scl <= 1'b0;              
                    7'd16: sda_out <= SLAVE_ADDR[3]; 
                    7'd17: scl <= 1'b1;              
                    7'd19: scl <= 1'b0;              
                    7'd20: sda_out <= SLAVE_ADDR[2]; 
                    7'd21: scl <= 1'b1;              
                    7'd23: scl <= 1'b0;              
                    7'd24: sda_out <= SLAVE_ADDR[1]; 
                    7'd25: scl <= 1'b1;              
                    7'd27: scl <= 1'b0;              
                    7'd28: sda_out <= SLAVE_ADDR[0]; 
                    7'd29: scl <= 1'b1;              
                    7'd31: scl <= 1'b0;              
                    7'd32: sda_out <= 1'b0;          // 0: write
                    7'd33: scl <= 1'b1;              
                    7'd35: scl <= 1'b0;              
                    7'd36: begin                     
                        sda_dir <= 1'b0;             
                        sda_out <= 1'b1;                         
                    end                              
                    7'd37: scl     <= 1'b1;            
                    7'd38: begin                     // slave acknowledge
                        st_done <= 1'b1;
                        if(sda_in == 1'b1)           // high level means not acknowledged
                            i2c_ack <= 1'b1;         // raise the acknowledge flag
                    end                                          
                    7'd39: begin                     
                        scl <= 1'b0;                 
                        cnt <= 1'b0;                 
                    end                              
                    default :  ;                     
                endcase                              
            end                                      
            st_addr16: begin                         
                case(cnt)                            
                    7'd0 : begin                     
                        sda_dir <= 1'b1 ;            
                        sda_out <= addr_t[15];       // send word address
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
                    7'd33: scl  <= 1'b1;             
                    7'd34: begin                     // slave acknowledge
                        st_done <= 1'b1;     
                        if(sda_in == 1'b1)           // high level means not acknowledged
                            i2c_ack <= 1'b1;         // raise the acknowledge flag
                    end        
                    7'd35: begin                     
                        scl <= 1'b0;                 
                        cnt <= 1'b0;                 
                    end                              
                    default :  ;                     
                endcase                              
            end                                      
            st_addr8: begin                          
                case(cnt)                            
                    7'd0: begin                      
                       sda_dir <= 1'b1 ;             
                       sda_out <= addr_t[7];         // word address
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
                    7'd33: scl     <= 1'b1;          
                    7'd34: begin                     // slave acknowledge
                        st_done <= 1'b1;     
                        if(sda_in == 1'b1)           // high level means not acknowledged
                            i2c_ack <= 1'b1;         // raise the acknowledge flag
                    end   
                    7'd35: begin                     
                        scl <= 1'b0;                 
                        cnt <= 1'b0;                 
                    end                              
                    default :  ;                     
                endcase                              
            end                                      
            st_data_wr: begin                        // write data (8 bit)
                case(cnt)                            
                    7'd0: begin                      
                        sda_out <= data_wr_t[7];     // I2C writes 8 bits of data
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
                        sda_dir <= 1'b0;           
                        sda_out <= 1'b1;                              
                    end                              
                    7'd33: scl <= 1'b1;              
                    7'd34: begin                     // slave acknowledge
                        st_done <= 1'b1;     
                        if(sda_in == 1'b1)           // high level means not acknowledged
                            i2c_ack <= 1'b1;         // raise the acknowledge flag
                    end          
                    7'd35: begin                     
                        scl  <= 1'b0;                
                        cnt  <= 1'b0;                
                    end                              
                    default  :  ;                    
                endcase                              
            end                                      
            st_addr_rd: begin                        // write address in order to read data
                case(cnt)                            
                    7'd0 : begin                     
                        sda_dir <= 1'b1;             
                        sda_out <= 1'b1;             
                    end                              
                    7'd1 : scl <= 1'b1;              
                    7'd2 : sda_out <= 1'b0;          // restart
                    7'd3 : scl <= 1'b0;              
                    7'd4 : sda_out <= SLAVE_ADDR[6]; // send slave address
                    7'd5 : scl <= 1'b1;              
                    7'd7 : scl <= 1'b0;              
                    7'd8 : sda_out <= SLAVE_ADDR[5]; 
                    7'd9 : scl <= 1'b1;              
                    7'd11: scl <= 1'b0;              
                    7'd12: sda_out <= SLAVE_ADDR[4]; 
                    7'd13: scl <= 1'b1;              
                    7'd15: scl <= 1'b0;              
                    7'd16: sda_out <= SLAVE_ADDR[3]; 
                    7'd17: scl <= 1'b1;              
                    7'd19: scl <= 1'b0;              
                    7'd20: sda_out <= SLAVE_ADDR[2]; 
                    7'd21: scl <= 1'b1;              
                    7'd23: scl <= 1'b0;              
                    7'd24: sda_out <= SLAVE_ADDR[1]; 
                    7'd25: scl <= 1'b1;              
                    7'd27: scl <= 1'b0;              
                    7'd28: sda_out <= SLAVE_ADDR[0]; 
                    7'd29: scl <= 1'b1;              
                    7'd31: scl <= 1'b0;              
                    7'd32: sda_out <= 1'b1;          // 1: read
                    7'd33: scl <= 1'b1;              
                    7'd35: scl <= 1'b0;              
                    7'd36: begin                     
                        sda_dir <= 1'b0;            
                        sda_out <= 1'b1;                    
                    end
                    7'd37: scl     <= 1'b1;
                    7'd38: begin                     // slave acknowledge
                        st_done <= 1'b1;     
                        if(sda_in == 1'b1)           // high level means not acknowledged
                            i2c_ack <= 1'b1;         // raise the acknowledge flag
                    end   
                    7'd39: begin
                        scl <= 1'b0;
                        cnt <= 1'b0;
                    end
                    default : ;
                endcase
            end
            st_data_rd: begin                        // read data (8 bit)
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
                        sda_dir <= 1'b1;             
                        sda_out <= 1'b1;
                    end
                    7'd33: scl     <= 1'b1;
                    7'd34: st_done <= 1'b1;          // not acknowledged (nack)
                    7'd35: begin
                        scl <= 1'b0;
                        cnt <= 1'b0;
                        i2c_data_r <= data_r;
                    end
                    default  :  ;
                endcase
            end
            st_stop: begin                           // stop: end the I2C operation
                case(cnt)
                    7'd0: begin
                        sda_dir <= 1'b1;             // end the I2C operation
                        sda_out <= 1'b0;
                    end
                    7'd1 : scl     <= 1'b1;
                    7'd3 : sda_out <= 1'b1;
                    7'd15: st_done <= 1'b1;
                    7'd16: begin
                        cnt      <= 1'b0;
                        i2c_done <= 1'b1;            // pass the I2C-done signal to the upper module
                    end
                    default  : ;
                endcase
            end
        endcase
    end
end

endmodule
