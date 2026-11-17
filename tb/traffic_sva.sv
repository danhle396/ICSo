// =============================================================================
// Module      : traffic_sva, traffic_sva_bind
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : The properties of PLAN 4.2 as SystemVerilog concurrent
//               assertions, bound into every traffic_top. This file is the
//               formal specification of the report. ModelSim-Altera Starter
//               Edition compiles it (run_modelsim.ps1) but does not execute
//               concurrent assertions (vsim-8311: "supported only in
//               Questasim"); the results come from traffic_checker.sv, which
//               implements the same properties procedurally.
//               iverilog does not parse SVA: run_sim.ps1 leaves this file out.
// Notes       : The three proposal properties are a_safe, a_emg and a_yel_*.
//               The length properties (a_allred, a_gmax_*, a_ylen_*) are written
//               for the normal rate and disabled while fast_sync = 1.
// =============================================================================
module traffic_sva #(
  parameter int TICK_DIV = 50_000_000,
  parameter int T_Y      = 3,
  parameter int T_G_MAX  = 15
) (
  input logic       clk,
  input logic       rst_n,
  input logic       fast_sync,
  input logic       emg_sync,
  input logic [2:0] light_ns,               // {R,Y,G}
  input logic [2:0] light_ew,
  input logic       ped_lamp,
  input logic       emergency_active
);

  localparam int YLEN = T_Y * TICK_DIV;     // cycles of a yellow
  localparam int GMAX = T_G_MAX * TICK_DIV; // longest green, cycles
  localparam int L    = YLEN + 1;           // worst emergency -> all red

  default clocking cb @(posedge clk); endclocking

  // ---- Proposal -----------------------------------------------------------------
  a_safe: assert property (disable iff (!rst_n)
    !(light_ns[0] && light_ew[0]));

  a_emg: assert property (disable iff (!rst_n)
    $rose(emg_sync) |-> ##[1:3] emergency_active);

  a_yel_ns: assert property (disable iff (!rst_n)
    $fell(light_ns[0]) |-> light_ns[1]);
  a_yel_ew: assert property (disable iff (!rst_n)
    $fell(light_ew[0]) |-> light_ew[1]);

  // ---- Added in the plan --------------------------------------------------------
  a_onehot: assert property (disable iff (!rst_n)
    $onehot(light_ns) && $onehot(light_ew));

  a_ped: assert property (disable iff (!rst_n)
    ped_lamp |-> light_ns[2] && light_ew[2]);

  a_allred: assert property (disable iff (!rst_n || fast_sync)
    emg_sync [*L+1] |-> light_ns[2] && light_ew[2] && !ped_lamp);

  a_gmax_ns: assert property (disable iff (!rst_n || fast_sync)
    $rose(light_ns[0]) |-> light_ns[0] [*1:GMAX] ##1 !light_ns[0]);
  a_gmax_ew: assert property (disable iff (!rst_n || fast_sync)
    $rose(light_ew[0]) |-> light_ew[0] [*1:GMAX] ##1 !light_ew[0]);

  a_ylen_ns: assert property (disable iff (!rst_n || fast_sync)
    $rose(light_ns[1]) |-> light_ns[1] [*YLEN] ##1 !light_ns[1]);
  a_ylen_ew: assert property (disable iff (!rst_n || fast_sync)
    $rose(light_ew[1]) |-> light_ew[1] [*YLEN] ##1 !light_ew[1]);

  // ---- Coverage of the emergency path ---------------------------------------------
  c_green_cut: cover property (disable iff (!rst_n)
    light_ns[0] ##1 emg_sync ##[1:$] light_ns[1] ##[1:$] (light_ns[2] && light_ew[2]));

endmodule

// Bind the properties into every instance of traffic_top: the parameters and
// signals are those of the traffic_top instance.
module traffic_sva_bind;
  bind traffic_top traffic_sva #(
    .TICK_DIV (TICK_DIV),
    .T_Y      (T_Y),
    .T_G_MAX  (T_G_MAX)
  ) u_sva (
    .clk              (clk),
    .rst_n            (rst_n),
    .fast_sync        (fast_sync),
    .emg_sync         (emg_sync),
    .light_ns         (light_ns),
    .light_ew         (light_ew),
    .ped_lamp         (ped_lamp),
    .emergency_active (emergency_active)
  );
endmodule
