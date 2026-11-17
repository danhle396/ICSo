// =============================================================================
// Module      : clk_divider
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Time base of the controller: a one-cycle tick every DIV clock
//               cycles (1 Hz on the board, 10 Hz with fast = 1).
//                 DIV = fast ? FAST_DIV : TICK_DIV
//               The count is cleared (clr) when
//                 restart = 1     a new phase starts (the timer loads), so the
//                                 first tick of every phase comes exactly DIV
//                                 cycles after the phase starts, even when the
//                                 phase was entered between two ticks
//                                 (emergency): PLAN 1.3 rule 4
//                 fast changes    the new rate starts from a clean count
// Notes       : tick comes straight from a flip-flop. It is decoded one cycle
//               early (cnt == DIV-2) and registered, which gives exactly the
//               waveform of the combinational decode (cnt == DIV-1) but keeps
//               the 26-bit comparison out of the FSM path. Needs DIV >= 2.
// =============================================================================
module clk_divider #(
  parameter int TICK_DIV = 50_000_000,      // clock cycles per tick, fast = 0
  parameter int FAST_DIV = 5_000_000        // clock cycles per tick, fast = 1
) (
  input  logic clk,                         // rising-edge clock
  input  logic rst_n,                       // asynchronous reset, active low
  input  logic fast,                        // synchronized rate select
  input  logic restart,                     // clear the count (phase start)
  output logic tick                         // one cycle wide, every DIV cycles
);

  timeunit 1ns;
  timeprecision 100ps;

  localparam int W = $clog2(TICK_DIV);

  logic [W-1:0] cnt;                        // 0 .. DIV-1
  logic         fast_q;                     // fast one cycle ago
  logic         clr, at_pre, at_last;

  always_comb begin
    clr     = restart || (fast != fast_q);
    at_pre  = fast ? (cnt == FAST_DIV - 2) : (cnt == TICK_DIV - 2);
    at_last = fast ? (cnt == FAST_DIV - 1) : (cnt == TICK_DIV - 1);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt    <= {W{1'b0}};
      fast_q <= 1'b0;
      tick   <= 1'b0;
    end
    else begin
      fast_q <= fast;
      tick   <= !clr && at_pre;
      if (clr || at_last)
        cnt <= {W{1'b0}};
      else
        cnt <= cnt + 1'b1;
    end
  end

endmodule
