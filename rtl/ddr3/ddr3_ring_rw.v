// ddr3_ring_rw.v
// 64-slot circular frame buffer with ONE write stream and TWO video read
// streams, plus (mode 2 only) a per-pixel EVM temporal-state read/write path.
//   video write : each source frame is stored into slot wptr (advances/vsync)
//   read A (current) : slot wptr-1, highest read priority -> display/EVM
//   read B (delayed) : slot wptr-1-dly_frames, fills spare bandwidth; this
//                      channel is skipped in mode 2 (bandwidth given to state)
//   state read  : prefetch previous-frame {m,q} for the EVM (tag 2)
//   state write : write current-frame {m,q} back (one line accumulated first)
// MIG has a single app port, so commands are arbitrated at BURST granularity.
// A 2-bit routing FIFO (depth 1024) records the channel of every accepted read
// command; returned data is steered by that tag (MIG returns reads in order).
// After a display vsync each video channel holds for a fixed count, purging
// in-flight data from the previous frame (prevents tearing).
`timescale 1ns/1ps

//==============================================================================
// File        : ddr3_ring_rw.v
// Module      : ddr3_ring_rw
// Description :
//   64-slot DDR3 ring-buffer scheduler running in the MIG ui_clk domain. It issues one
//   write and two reads (current and delayed frames), arbitrates MIG commands and tracks
//   the write/read FIFO levels to keep the frame ring free of underflow/overflow.
//==============================================================================
module ddr3_ring_rw(
    input               ui_clk,
    input               ui_clk_sync_rst,
    input               init_calib_complete,
    input               app_rdy,
    input               app_wdf_rdy,
    input               app_rd_data_valid,
    input       [15:0]  wfifo_rcount,          // packed video write words
    input       [15:0]  rfifo_wcount_cur,      // video read FIFO A level
    input       [15:0]  rfifo_wcount_dly,      // video read FIFO B level
    input               rd_load,               // display vsync
    input               wr_load,               // source vsync
    input       [28:0]  frame_addr_size,       // 230400 (64-bit words/frame)
    input       [7:0]   burst_len,             // 160 x512 words per video burst
    input       [5:0]   dly_frames,            // extraction delay (default 20)
    input               ddr3_read_valid,
    // mode-2 EVM state path
    input               evm_en,                // 1 in dynamic enhancement mode
    input       [8:0]   st_wfifo_rcount,       // state write FIFO words available
    input       [10:0]  st_rfifo_wcount,       // state read FIFO fill level
    output              st_wfifo_rden,         // pop one state write word
    output              st_rfifo_wren,         // returned word belongs to state
    output              st_wr_sel,             // 1 during state write (wdf mux)
    output              rfifo_wren_cur,
    output              rfifo_wren_dly,
    output  reg [28:0]  app_addr,
    output              app_en,
    output              app_wdf_wren,
    output              app_wdf_end,
    output      [2:0]   app_cmd,
    output              dly_ready
);
localparam IDLE    = 3'b001;
localparam ARB     = 3'b010;
localparam WRITE   = 3'b100;
localparam RD_CUR  = 3'b011;
localparam RD_DLY  = 3'b101;
localparam ST_RD   = 3'b110;
localparam ST_WR   = 3'b111;
localparam HOLD    = 9'd400;   // purge/wait after display vsync

// EVM state region: placed immediately after the 64 video slots
localparam [23:0] ST_BASE   = 24'd14745600; // 64*230400 (64-bit-word addr)
localparam [7:0]  ST_BL     = 8'd80;        // state burst = 1 line (16 px/word)
localparam [16:0] ST_FRM    = 17'd57600;    // 512-bit words per state frame
// ping-pong group bases (64-bit-word): group0 = ST_BASE, group1 = ST_BASE+ST_FRM*8
localparam [23:0] ST_GRP_GAP= 24'd460800;   // ST_FRM*8 (64-bit words per group)
localparam [10:0] ST_RD_HI  = 11'd800;      // prefetch threshold (800+80<1024)
localparam [10:0] ST_RD_LO  = 11'd160;      // state-read urgent level (2 lines)
localparam [8:0]  RD_CUR_LO = 9'd40;       // video-read urgent level (1 line)
localparam [8:0]  ST_WR_HI  = 9'd200;       // state-write urgent level (FIFO 256)
localparam [8:0]  ST_WR_N   = 9'd80;        // accumulate one line before write

reg  [2:0]  state_cnt;
reg  [23:0] wr_addr_cnt, rd_cur_addr_cnt, rd_dly_addr_cnt;
reg  [23:0] wr_off, rd_cur_off, rd_dly_off;
reg  [7:0]  burst_a;
reg  [28:0] fsize_a;
reg         wr_load_d0, wr_load_d1, rd_load_d0, rd_load_d1;
reg         wr_rst, rd_rst;
reg  [5:0]  wptr, rptr_cur, rptr_dly;
reg  [8:0]  cur_hold_cnt, dly_hold_cnt;
reg  [6:0]  frame_cnt;
reg  [1:0]  route_tag_fixed;
reg  [7:0]  st_rd_ac, st_wr_ac;
reg  [16:0] st_rd_off, st_wr_off;   // in-frame offsets (reset every frame)
reg         st_fp;                  // frame parity: selects ping-pong group
// read group holds the PREVIOUS frame state; write group receives the NEW frame
wire [23:0] st_rd_grp = st_fp ? (ST_BASE+ST_GRP_GAP) : ST_BASE;
wire [23:0] st_wr_grp = st_fp ? ST_BASE : (ST_BASE+ST_GRP_GAP);

wire rst_n = ~ui_clk_sync_rst;
wire [23:0] FRAME_WORDS = fsize_a[23:0]>>3;     // 28800

// registered params
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin fsize_a<=29'd0; burst_a<=8'd0; end
    else        begin fsize_a<=frame_addr_size; burst_a<=burst_len; end
end

// slot base = slot*230400 = slot*(2^18 - 2^15 + 2^10), shift only
function [23:0] slot_base(input [5:0] s);
reg [23:0] e;
begin
    e = s;
    slot_base = (e<<18) - (e<<15) + (e<<10);
end
endfunction

// channel hold (purge in-flight + wait). The OR with rd_rst / its one-cycle
// combinational edge (rd_load_d0 && !rd_load_d1) closes the start-of-frame race:
// on the very first frame after reset, off=0 and the FSM could otherwise enter
// RD_CUR on the same cycle cur_hold is being armed (RD_CUR then runs a full
// 160-command burst without re-checking cur_hold), and that burst's returns
// would all be purged, advancing the offset by 160 and losing one display line.
wire rd_rst_edge = rd_load_d0 && !rd_load_d1;
wire cur_hold = (cur_hold_cnt!=9'd0) || rd_rst || rd_rst_edge;
wire dly_hold = (dly_hold_cnt!=9'd0);
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin cur_hold_cnt<=9'd0; dly_hold_cnt<=9'd0; end
    else if(rd_rst) begin cur_hold_cnt<=HOLD; dly_hold_cnt<=HOLD; end
    else begin
        if(cur_hold_cnt!=9'd0) cur_hold_cnt<=cur_hold_cnt-9'd1;
        if(dly_hold_cnt!=9'd0) dly_hold_cnt<=dly_hold_cnt-9'd1;
    end
end

//------------------------- routing FIFO (2-bit tag, depth 1024)
reg  [1:0]  route_mem [0:1023];
reg  [9:0]  route_wp, route_rp;
wire        route_full = (route_wp+10'd1)==route_rp;
wire        route_push = app_en & app_rdy & (app_cmd==3'd1) & ~route_full;
wire        route_pop  = app_rd_data_valid;
wire [1:0]  route_tag  = route_mem[route_rp];
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) route_wp<=10'd0;
    else if(route_push) begin route_mem[route_wp]<=route_tag_fixed; route_wp<=route_wp+10'd1;
    end
end
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) route_rp<=10'd0;
    else if(route_pop) route_rp<=route_rp+10'd1;
end

// steer returned data: video channels drop while holding (purge); state never
assign rfifo_wren_cur = app_rd_data_valid & (route_tag==2'd0) & ~cur_hold;
assign rfifo_wren_dly = app_rd_data_valid & (route_tag==2'd1) & ~dly_hold;
assign st_rfifo_wren  = app_rd_data_valid & (route_tag==2'd2);

// MIG command/control
wire in_write = (state_cnt==WRITE);
wire in_rdcur = (state_cnt==RD_CUR);
wire in_rddly = (state_cnt==RD_DLY);
wire in_strd  = (state_cnt==ST_RD);
wire in_stwr  = (state_cnt==ST_WR);
assign st_wr_sel    = in_stwr;
assign app_en       = ((in_write||in_stwr) && app_rdy && app_wdf_rdy)
                   || ((in_rdcur||in_rddly||in_strd) && app_rdy && ~route_full);
assign app_wdf_wren = (in_write||in_stwr) && app_rdy && app_wdf_rdy;
assign app_wdf_end  = app_wdf_wren;
assign app_cmd      = (in_write||in_stwr) ? 3'd0 : 3'd1;

// Pop one FWFT state-write word on each accepted state write command. Must be
// combinational on the SAME cycle as app_wdf_wren (matches the video wfifo path),
// otherwise the write data and the FIFO pop would be off by one cycle.
assign st_wfifo_rden = in_stwr && app_rdy && app_wdf_rdy;

// synchronize load pulses
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin
        wr_load_d0<=0; wr_load_d1<=0; rd_load_d0<=0; rd_load_d1<=0;
    end else begin
        wr_load_d0<=wr_load; wr_load_d1<=wr_load_d0;
        rd_load_d0<=rd_load; rd_load_d1<=rd_load_d0;
    end
end
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) wr_rst<=0;
    else if(wr_load_d0 && !wr_load_d1) wr_rst<=1'b1;
    else wr_rst<=1'b0;
end
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) rd_rst<=0;
    else if(rd_load_d0 && !rd_load_d1) rd_rst<=1'b1;
    else rd_rst<=1'b0;
end

// write pointer + total frame count (for delayed readiness)
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin wptr<=6'd0; frame_cnt<=7'd0; end
    else if(wr_rst) begin
        wptr<=wptr+6'd1;
        if(frame_cnt<7'd127) frame_cnt<=frame_cnt+7'd1;
    end
end

// read pointers at display vsync
wire [5:0] dly_slot = wptr - 6'd1 - dly_frames;
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin rptr_cur<=6'd0; rptr_dly<=6'd0; end
    else if(rd_rst) begin rptr_cur<=wptr-6'd1; rptr_dly<=dly_slot; end
end

// frame-locked ping-pong: at every display vsync flip the group parity and
// reset both in-frame offsets to 0. The Gaussian valid flag stays asserted into
// blanking (continuously-enabled line buffers/shift regs), so the algorithm
// produces exactly 720 x 1280 states = 57600 words per frame = 80 words/line.
// Word0 maps to Gaussian row0 (physical line2); physical lines 0,1 are not
// consumed, leaving the read FIFO head at word0. State R/W cover the whole
// group in frame and end exactly at ST_FRM.
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin st_fp<=1'b0; st_rd_off<=17'd0; st_wr_off<=17'd0; end
    else if(rd_rst) begin
        st_fp<=~st_fp; st_rd_off<=17'd0; st_wr_off<=17'd0;
    end
end

// delayed channel is valid once enough frames have been written
assign dly_ready = (frame_cnt >= {1'b0,dly_frames}+7'd1);

// frame offset counters
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) wr_off<=24'd0;
    else if(wr_rst) wr_off<=24'd0;
    else if(in_write && app_rdy && app_wdf_rdy
            && wr_addr_cnt=={16'b0,(burst_a-8'd1)})
        wr_off<=wr_off+{16'b0,burst_a};
end
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) rd_cur_off<=24'd0;
    else if(rd_rst) rd_cur_off<=24'd0;
    else if(in_rdcur && app_rdy
            && rd_cur_addr_cnt=={16'b0,(burst_a-8'd1)})
        rd_cur_off<=rd_cur_off+{16'b0,burst_a};
end
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) rd_dly_off<=24'd0;
    else if(rd_rst) rd_dly_off<=24'd0;
    else if(in_rddly && app_rdy
            && rd_dly_addr_cnt=={16'b0,(burst_a-8'd1)})
        rd_dly_off<=rd_dly_off+{16'b0,burst_a};
end

// main FSM
// priority: video write > video read current > video read delayed (mode!=2)
//           > state read prefetch > state write
always @(posedge ui_clk or negedge rst_n) begin
    if(~rst_n) begin
        state_cnt<=IDLE; app_addr<=0;
        wr_addr_cnt<=0; rd_cur_addr_cnt<=0; rd_dly_addr_cnt<=0;
        route_tag_fixed<=2'd0; st_rd_ac<=8'd0; st_wr_ac<=8'd0;
    end else begin
        case(state_cnt)
            IDLE:
                state_cnt<=init_calib_complete ? ARB : IDLE;
            ARB: begin
                if(wr_rst || rd_rst)
                    state_cnt<=ARB;
                else if(wr_off<FRAME_WORDS
                        && wfifo_rcount >= {8'b0,(burst_a-8'd2)}) begin
                    state_cnt<=WRITE; wr_addr_cnt<=0;
                    app_addr<={5'b0,slot_base(wptr)} + (wr_off<<3);
                end
                // video read current URGENT: its FIFO is within one line of
                // running dry -> protect the displayed picture first
                else if(rd_cur_off<FRAME_WORDS && ddr3_read_valid && !cur_hold
                        && rfifo_wcount_cur < {8'b0,RD_CUR_LO}) begin
                    state_cnt<=RD_CUR; rd_cur_addr_cnt<=0; route_tag_fixed<=2'd0;
                    app_addr<={5'b0,slot_base(rptr_cur)} + (rd_cur_off<<3);
                end
                // state write URGENT: the packed-state FIFO is near full
                // (256 deep). Overflow would permanently lose a state, so this
                // outranks the state-read urgent (a read gap is caught by the
                // empty-hold path, a write overflow is not).
                else if(evm_en && rd_load && (st_wr_off<ST_FRM)
                        && (st_wfifo_rcount>=ST_WR_HI)) begin
                    state_cnt<=ST_WR; st_wr_ac<=8'd0;
                    app_addr<={5'b0,st_wr_grp} + (st_wr_off<<3);
                end
                // state read URGENT: within two lines of underflow -> jump ahead
                // of the normal video read so the 16-state/word boundary never
                // slips (this was the source of the vertical stripes)
                else if(evm_en && rd_load && (st_rd_off<ST_FRM)
                        && (st_rfifo_wcount<ST_RD_LO)) begin
                    state_cnt<=ST_RD; st_rd_ac<=8'd0; route_tag_fixed<=2'd2;
                    app_addr<={5'b0,st_rd_grp} + (st_rd_off<<3);
                end
                else if(rd_cur_off<FRAME_WORDS && ddr3_read_valid && !cur_hold
                        && rfifo_wcount_cur < {8'b0,burst_a}) begin
                    state_cnt<=RD_CUR; rd_cur_addr_cnt<=0; route_tag_fixed<=2'd0;
                    app_addr<={5'b0,slot_base(rptr_cur)} + (rd_cur_off<<3);
                end
                else if(!evm_en && rd_dly_off<FRAME_WORDS && ddr3_read_valid
                        && !dly_hold
                        && rfifo_wcount_dly < {8'b0,burst_a}) begin
                    state_cnt<=RD_DLY; rd_dly_addr_cnt<=0; route_tag_fixed<=2'd1;
                    app_addr<={5'b0,slot_base(rptr_dly)} + (rd_dly_off<<3);
                end
                else if(evm_en && rd_load && (st_rd_off<ST_FRM)
                        && (st_rfifo_wcount<ST_RD_HI)) begin
                    state_cnt<=ST_RD; st_rd_ac<=8'd0; route_tag_fixed<=2'd2;
                    app_addr<={5'b0,st_rd_grp} + (st_rd_off<<3);
                end
                else if(evm_en && rd_load && (st_wr_off<ST_FRM)
                        && (st_wfifo_rcount>=ST_WR_N)) begin
                    state_cnt<=ST_WR; st_wr_ac<=8'd0;
                    app_addr<={5'b0,st_wr_grp} + (st_wr_off<<3);
                end
                else
                    state_cnt<=ARB;
            end
            WRITE: begin
                if(wr_addr_cnt=={16'b0,(burst_a-8'd1)} && app_rdy && app_wdf_rdy) begin
                    state_cnt<=ARB; app_addr<=app_addr+4'd8;
                end
                else if(app_rdy && app_wdf_rdy) begin
                    wr_addr_cnt<=wr_addr_cnt+1'b1; app_addr<=app_addr+4'd8;
                end
            end
            RD_CUR: begin
                if(rd_cur_addr_cnt=={16'b0,(burst_a-8'd1)} && app_rdy) begin
                    state_cnt<=ARB; app_addr<=app_addr+4'd8;
                end
                else if(app_rdy) begin
                    rd_cur_addr_cnt<=rd_cur_addr_cnt+1'b1; app_addr<=app_addr+4'd8;
                end
            end
            RD_DLY: begin
                if(rd_dly_addr_cnt=={16'b0,(burst_a-8'd1)} && app_rdy) begin
                    state_cnt<=ARB; app_addr<=app_addr+4'd8;
                end
                else if(app_rdy) begin
                    rd_dly_addr_cnt<=rd_dly_addr_cnt+1'b1; app_addr<=app_addr+4'd8;
                end
            end
            ST_RD: begin
                if(st_rd_ac==(ST_BL-8'd1) && app_rdy) begin
                    state_cnt<=ARB; app_addr<=app_addr+4'd8;
                    st_rd_off<=st_rd_off+17'd80;
                end
                else if(app_rdy) begin
                    st_rd_ac<=st_rd_ac+1'b1; app_addr<=app_addr+4'd8;
                end
            end
            ST_WR: begin
                if(st_wr_ac==(ST_BL-8'd1) && app_rdy && app_wdf_rdy) begin
                    state_cnt<=ARB; app_addr<=app_addr+4'd8;
                    st_wr_off<=st_wr_off+17'd80;
                end
                else if(app_rdy && app_wdf_rdy) begin
                    st_wr_ac<=st_wr_ac+1'b1; app_addr<=app_addr+4'd8;
                end
            end
            default: state_cnt<=IDLE;
        endcase
    end
end

endmodule
