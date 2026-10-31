`timescale 1ns/1ps
//==============================================================================
// key_tick_debounce.v
//   Push-button debounce, active-low button. Outputs one clock-cycle tick on a
//   confirmed press. Distinct module name to avoid clashing with key_debounce.
//==============================================================================

//==============================================================================
// File        : key_tick_debounce.v
// Module      : key_tick_debounce
// Description :
//   Push-button debouncer. A stable level must hold for the debounce interval, after which it
//   emits a single clock-cycle tick for one confirmed press.
//==============================================================================
module key_tick_debounce #(parameter integer CLK_HZ = 74250000) (
    input       clk,
    input       rst_n,
    input       key_in,
    output reg  key_tick
);
localparam integer DBNC = CLK_HZ/50;          // 20 ms
reg [2:0]  sync;
reg [20:0] cnt;
reg        key_l;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sync <= 3'b111; cnt <= 21'd0; key_l <= 1'b1; key_tick <= 1'b0;
    end else begin
        sync     <= {sync[1:0], key_in};
        key_tick <= 1'b0;
        if(sync[2] != key_l) begin
            cnt   <= DBNC[20:0];
            key_l <= sync[2];
        end else if(cnt != 21'd0) begin
            cnt <= cnt - 21'd1;
            if(cnt == 21'd1 && sync[2] == key_l && key_l == 1'b0)
                key_tick <= 1'b1;             // confirmed press
        end
    end
end
endmodule
