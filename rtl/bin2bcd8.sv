// =============================================================================
// Module      : bin2bcd8
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Binary to two BCD digits, 0..99 -> {tens, ones}, purely
//               combinational, by double dabble (shift left, add 3 to every
//               digit that is 5 or more before the shift).
// Notes       : Chosen over a loop of "subtract 10" comparisons (159 LE in the
//               feasibility prototype against 24 LE) and over a lookup table
//               (no M4K block is used). Inputs above 99 are out of range.
// =============================================================================
module bin2bcd8 (
  input  logic [7:0] bin,                   // 0 .. 99
  output logic [7:0] bcd                    // {tens, ones}
);

  timeunit 1ns;
  timeprecision 100ps;

  logic [15:0] s;                           // {tens, ones, bin}
  int          i;

  always_comb begin
    s = {8'd0, bin};
    for (i = 0; i < 8; i++) begin
      if (s[11:8] >= 4'd5)  s[11:8]  = s[11:8]  + 4'd3;
      if (s[15:12] >= 4'd5) s[15:12] = s[15:12] + 4'd3;
      s = s << 1;
    end
    bcd = s[15:8];
  end

endmodule
