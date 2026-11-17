// =============================================================================
// Module      : state_timer
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : 8-bit down-counter of the ticks left in the current phase.
//                 load = 1                 cnt <= load_val (new phase)
//                 tick & !hold & cnt != 0  cnt <= cnt - 1
//                 otherwise                cnt holds (hold = green extension)
//               last = (cnt == 1): the next tick is the last one of the phase.
//               After reset cnt = RESET_VAL (T_G, the reset state is NS_G).
// =============================================================================
module state_timer #(
  parameter logic [7:0] RESET_VAL = 8'd10   // duration of the reset state
) (
  input  logic       clk,                   // rising-edge clock
  input  logic       rst_n,                 // asynchronous reset, active low
  input  logic       tick,                  // time base (clk_divider)
  input  logic       load,                  // a new phase starts
  input  logic [7:0] load_val,              // its duration, in ticks
  input  logic       hold,                  // keep cnt at 1 (green extension)
  output logic [7:0] cnt,                   // ticks left
  output logic       last                   // cnt == 1
);

  timeunit 1ns;
  timeprecision 100ps;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cnt <= RESET_VAL;
    else if (load)
      cnt <= load_val;
    else if (tick && !hold && cnt != 8'd0)
      cnt <= cnt - 8'd1;
  end

  always_comb last = (cnt == 8'd1);

endmodule
