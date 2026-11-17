// =============================================================================
// Module      : strobe_gen
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Sampling strobe of the debouncers: one cycle high every DIV
//               clock cycles (DIV = 250_000 on the board: 200 Hz, one sample
//               every 5 ms). DIV = 1 (simulation) gives a strobe that is always
//               high, so the debouncers sample on every clock.
// Notes       : strobe is a continuous assignment on purpose: with DIV = 1 it
//               is a constant, and the always @* that the legacy down-converter
//               makes of an always_comb would never run for a constant (PLAN 2).
// =============================================================================
module strobe_gen #(
  parameter int DIV = 250_000               // clock cycles between two samples
) (
  input  logic clk,                         // rising-edge clock
  input  logic rst_n,                       // asynchronous reset, active low
  output wire  strobe                       // one cycle wide, every DIV cycles
);

  timeunit 1ns;
  timeprecision 100ps;

  localparam int W = (DIV > 1) ? $clog2(DIV) : 1;

  logic [W-1:0] cnt;                        // 0 .. DIV-1

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cnt <= {W{1'b0}};
    else if (cnt == DIV - 1)
      cnt <= {W{1'b0}};
    else
      cnt <= cnt + 1'b1;
  end

  assign strobe = (DIV == 1) ? 1'b1 : (cnt == DIV - 1);

endmodule
