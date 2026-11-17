// =============================================================================
// Module      : sync_debounce
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Two-flip-flop synchronizer followed by a 3-sample debouncer
//               for one asynchronous, possibly bouncing input (switch, button).
//                 s1, s2           synchronizer (metastability filter)
//                 on each sample   sh <= {sh[1:0], s2}
//                                  dout <= 1 if the three samples {sh[1:0], s2}
//                                  are all 1, 0 if they are all 0, else holds
//               A pulse is passed only if it lasts three samples: with one
//               sample every 5 ms (board) a glitch shorter than 10 ms never gets
//               through; with a sample every clock (simulation) glitches of 1
//               and 2 cycles are filtered and 3 cycles pass.
// =============================================================================
module sync_debounce (
  input  logic clk,                         // rising-edge clock
  input  logic rst_n,                       // asynchronous reset, active low
  input  logic sample,                      // sampling strobe (strobe_gen)
  input  logic din,                         // asynchronous input
  output logic dout                         // synchronized, debounced output
);

  timeunit 1ns;
  timeprecision 100ps;

  logic       s1, s2;                       // synchronizer
  logic [2:0] sh;                           // last three samples

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1   <= 1'b0;
      s2   <= 1'b0;
      sh   <= 3'b000;
      dout <= 1'b0;
    end
    else begin
      s1 <= din;
      s2 <= s1;
      if (sample) begin
        sh <= {sh[1:0], s2};
        if ({sh[1:0], s2} == 3'b111)
          dout <= 1'b1;
        else if ({sh[1:0], s2} == 3'b000)
          dout <= 1'b0;
      end
    end
  end

endmodule
