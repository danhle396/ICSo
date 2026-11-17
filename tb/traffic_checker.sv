// =============================================================================
// Module      : traffic_checker
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Procedural checker of the properties of PLAN 4.2: the same
//               meaning as the SVA of traffic_sva.sv, written with cycle counters
//               and immediate assertions so that it runs on iverilog 0.9.7 (after
//               down-conversion) and on ModelSim-Altera Starter Edition, which
//               does not execute concurrent assertions (vsim-8311).
//
//   a_safe    never green on both roads                         (proposal)
//   a_emg     rise of emg_sync -> emergency_active in 1..3 cycles (proposal)
//   a_yel     a green always ends in yellow, both roads         (proposal)
//   a_onehot  exactly one lamp per road
//   a_ped     walk lamp only while both roads are red
//   a_allred  emg_sync held more than L = T_Y*DIV + 1 cycles -> all red
//   a_gmax    a green lasts at most T_G_MAX*DIV cycles
//   a_ylen    a yellow lasts exactly T_Y*DIV cycles (unless a reset cuts it)
//
//   Everything is sampled at the rising edge of clk (values before the edge)
//   and disabled while rst_n = 0, which also clears the history. DIV follows
//   fast_sync; the length checks are skipped while fast_sync changed less
//   than a phase ago (the tick period is not constant then).
//   For each property the checker counts how often it was triggered (the
//   antecedent was true) as well as the violations, so a PASS is not vacuous.
// =============================================================================
module traffic_checker #(
  parameter int TICK_DIV  = 4,
  parameter int FAST_DIV  = 2,
  parameter int T_Y       = 3,
  parameter int T_G_MAX   = 15,
  parameter int MAX_PRINT = 10              // messages shown before muting
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       fast_sync,             // traffic_top.fast_sync
  input  logic       emg_sync,              // traffic_top.emg_sync
  input  logic [2:0] light_ns,              // {R,Y,G}
  input  logic [2:0] light_ew,
  input  logic       ped_lamp,
  input  logic       emergency_active
);

  timeunit 1ns;
  timeprecision 100ps;

  // violations and triggers of each property
  int v_safe = 0, v_emg = 0, v_yel = 0, v_onehot = 0, v_ped = 0, v_allred = 0, v_gmax = 0, v_ylen = 0;
  int h_safe = 0, h_emg = 0, h_yel = 0, h_onehot = 0, h_ped = 0, h_allred = 0, h_gmax = 0, h_ylen = 0;
  int violations = 0;                       // sum of v_*

  logic g_ns_q = 1'b0, g_ew_q = 1'b0;       // greens one sample ago
  logic emg_q  = 1'b0, fast_q = 1'b0;
  int   emg_wait = 0;                       // a_emg: samples since the rise, 0 = idle
  int   emg_run  = 0;                       // a_allred: samples with emg_sync = 1
  int   glen_ns = 0, glen_ew = 0;           // a_gmax: samples of the current green
  int   ylen_ns = 0, ylen_ew = 0;           // a_ylen: samples of the current yellow
  int   quiet   = 0;                        // samples since fast_sync last changed
  int   div;

  function automatic logic onehot3(input logic [2:0] l);
    onehot3 = (l == 3'b001) || (l == 3'b010) || (l == 3'b100);
  endfunction

  task automatic fail(input logic [8*10:1] name, input logic [8*48:1] what);
    begin
      violations++;
      if (violations <= MAX_PRINT)
        $error("%t  %0s violated: %0s  (NS=%b EW=%b walk=%b emg_sync=%b emergency_active=%b)",
               $time, name, what, light_ns, light_ew, ped_lamp, emg_sync, emergency_active);
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      emg_wait = 0;
      emg_run  = 0;
      glen_ns  = 0;
      glen_ew  = 0;
      ylen_ns  = 0;
      ylen_ew  = 0;
      quiet    = 0;
    end
    else begin
      div   = fast_sync ? FAST_DIV : TICK_DIV;
      quiet = (fast_sync != fast_q) ? 0 : quiet + 1;

      // a_safe
      h_safe++;
      assert (!(light_ns[0] && light_ew[0]))
        else begin v_safe++; fail("a_safe", "green on both roads"); end

      // a_onehot
      h_onehot++;
      assert (onehot3(light_ns) && onehot3(light_ew))
        else begin v_onehot++; fail("a_onehot", "not exactly one lamp per road"); end

      // a_ped
      if (ped_lamp) begin
        h_ped++;
        assert (light_ns == 3'b100 && light_ew == 3'b100)
          else begin v_ped++; fail("a_ped", "walk lamp while a road is not red"); end
      end

      // a_emg: $rose(emg_sync) |-> ##[1:3] emergency_active
      if (emg_wait > 0) begin
        if (emergency_active)
          emg_wait = 0;
        else if (emg_wait == 3) begin
          v_emg++;
          fail("a_emg", "no emergency_active 1..3 cycles after the rise");
          emg_wait = 0;
        end
        else
          emg_wait++;
      end
      if (emg_sync && !emg_q) begin
        h_emg++;
        emg_wait = 1;
      end

      // a_yel: $fell(green) |-> yellow
      if (g_ns_q && !light_ns[0]) begin
        h_yel++;
        assert (light_ns == 3'b010)
          else begin v_yel++; fail("a_yel", "NS green ended without yellow"); end
      end
      if (g_ew_q && !light_ew[0]) begin
        h_yel++;
        assert (light_ew == 3'b010)
          else begin v_yel++; fail("a_yel", "EW green ended without yellow"); end
      end

      // a_allred: emg_sync [*L+1] |-> all red, L = T_Y*DIV + 1
      emg_run = emg_sync ? emg_run + 1 : 0;
      if (emg_run > T_Y * div + 1 && quiet > emg_run + 2) begin
        if (emg_run == T_Y * div + 2)
          h_allred++;
        assert (light_ns == 3'b100 && light_ew == 3'b100 && !ped_lamp)
          else begin v_allred++; fail("a_allred", "emergency held but not all red"); end
      end

      // a_gmax: green at most T_G_MAX*DIV samples
      glen_ns = light_ns[0] ? glen_ns + 1 : 0;
      glen_ew = light_ew[0] ? glen_ew + 1 : 0;
      if (g_ns_q && !light_ns[0]) h_gmax++;
      if (g_ew_q && !light_ew[0]) h_gmax++;
      if (glen_ns == T_G_MAX * div + 1 && quiet > glen_ns + 2) begin
        v_gmax++; fail("a_gmax", "NS green longer than T_G_MAX");
      end
      if (glen_ew == T_G_MAX * div + 1 && quiet > glen_ew + 2) begin
        v_gmax++; fail("a_gmax", "EW green longer than T_G_MAX");
      end

      // a_ylen: yellow exactly T_Y*DIV samples
      if (light_ns == 3'b010)
        ylen_ns++;
      else if (ylen_ns > 0) begin
        if (quiet > ylen_ns + 2) begin
          h_ylen++;
          assert (ylen_ns == T_Y * div)
            else begin v_ylen++; fail("a_ylen", "NS yellow not T_Y*DIV cycles long"); end
        end
        ylen_ns = 0;
      end
      if (light_ew == 3'b010)
        ylen_ew++;
      else if (ylen_ew > 0) begin
        if (quiet > ylen_ew + 2) begin
          h_ylen++;
          assert (ylen_ew == T_Y * div)
            else begin v_ylen++; fail("a_ylen", "EW yellow not T_Y*DIV cycles long"); end
        end
        ylen_ew = 0;
      end
    end
    g_ns_q = light_ns[0];
    g_ew_q = light_ew[0];
    emg_q  = emg_sync;
    fast_q = fast_sync;
  end

  // Summary table, called by the testbench at the end of the run
  task automatic report;
    begin
      $display("Checker (PLAN 4.2)   triggered  violations");
      $display("  a_safe    %12d %11d", h_safe,   v_safe);
      $display("  a_emg     %12d %11d", h_emg,    v_emg);
      $display("  a_yel     %12d %11d", h_yel,    v_yel);
      $display("  a_onehot  %12d %11d", h_onehot, v_onehot);
      $display("  a_ped     %12d %11d", h_ped,    v_ped);
      $display("  a_allred  %12d %11d", h_allred, v_allred);
      $display("  a_gmax    %12d %11d", h_gmax,   v_gmax);
      $display("  a_ylen    %12d %11d", h_ylen,   v_ylen);
      $display("CHECKER VIOLATIONS : %0d", violations);
    end
  endtask

endmodule
