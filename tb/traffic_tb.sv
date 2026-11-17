// =============================================================================
// Testbench   : traffic_tb
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Self-checking testbench of traffic_top with small parameters:
//               TICK_DIV = 4, FAST_DIV = 2, DB_DIV = 1, so one tick is 4 clock
//               cycles (2 with fast = 1) and the debouncers sample every clock.
//   Phase 1 : directed tests T1..T18 (PLAN 4.3). Each one starts from a reset
//             and checks the order of the states, the length of each phase
//             (cycles), time_left at the start of the phase and the flags.
//   Phase 2 : N_RANDOM constrained-random cycles from +seed=N: emergencies
//             (1/400 cycles, held 5..60), button presses (1/150), 1-2 cycle
//             glitches (1/50), car sensors (1/80), fast (1/4000), reset (1/5000).
//   Always  : traffic_checker (the properties of PLAN 4.2), coverage of the
//             9 states and the 24 arcs of PLAN 1.3, and two vector files for
//             model/golden.py, one line per rising edge of clk (values just
//             before the edge):
//               vectors/stim_<tag>.txt  cycle rst_n ped_btn emg_sensor car_ns car_ew fast
//               vectors/rtl_<tag>.txt   cycle state light_ns light_ew ped_lamp time_left emergency_active
// Plusargs    : +seed=N    random seed (default 1)
//               +tag=name  vector file names (default seedN)
//               +vcd       dump phase 1 to traffic_tb.vcd
// Run         : .\run_sim.ps1  (iverilog, down-converted for 0.9.7 if needed)
//               .\run_modelsim.ps1
// =============================================================================
module traffic_tb;

  timeunit 1ns;
  timeprecision 100ps;

  // ---- Parameters of the DUT and derived lengths, in clock cycles -------------
  localparam int TICK_DIV = 4;
  localparam int FAST_DIV = 2;
  localparam int DB_DIV   = 1;
  localparam int T_G = 10, T_G_MAX = 15, T_Y = 3, T_R = 1, T_WALK = 5, T_RC = 2;

  localparam int CG    = T_G * TICK_DIV;      // 40
  localparam int CGMAX = T_G_MAX * TICK_DIV;  // 60
  localparam int CY    = T_Y * TICK_DIV;      // 12
  localparam int CR    = T_R * TICK_DIV;      //  4
  localparam int CW    = T_WALK * TICK_DIV;   // 20
  localparam int CRC   = T_RC * TICK_DIV;     //  8
  localparam int DB    = 5;                   // input -> debounced output, cycles

  localparam int PERIOD    = 10;              // ns
  localparam int N_RANDOM  = 30000;           // cycles of phase 2
  localparam int MAX_PRINT = 20;              // directed errors shown

  // state numbers (state_dbg) and time_left at the start of each phase (BCD)
  localparam logic [3:0] NS_G = 4'd0, NS_Y = 4'd1, RED1 = 4'd2, EW_G = 4'd3, EW_Y = 4'd4,
                         RED2 = 4'd5, PED_WALK = 4'd6, EMERGENCY = 4'd7, RECOVER = 4'd8;
  localparam logic [7:0] TL_G = 8'h10, TL_Y = 8'h03, TL_R = 8'h01, TL_W = 8'h05, TL_RC = 8'h02;

  // ---- DUT ------------------------------------------------------------------------
  logic       clk = 1'b0;
  logic       rst_n, fast, ped_btn, emg_sensor, car_ns, car_ew;
  wire  [2:0] light_ns, light_ew;
  wire        ped_lamp, emergency_active, ped_req_dbg, tick_dbg;
  wire  [7:0] time_left;
  wire  [3:0] state_dbg;

  always #(PERIOD/2) clk = ~clk;

  traffic_top #(.TICK_DIV(TICK_DIV), .FAST_DIV(FAST_DIV), .DB_DIV(DB_DIV)) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .fast             (fast),
    .ped_btn          (ped_btn),
    .emg_sensor       (emg_sensor),
    .car_ns           (car_ns),
    .car_ew           (car_ew),
    .light_ns         (light_ns),
    .light_ew         (light_ew),
    .ped_lamp         (ped_lamp),
    .time_left        (time_left),
    .emergency_active (emergency_active),
    .state_dbg        (state_dbg),
    .ped_req_dbg      (ped_req_dbg),
    .tick_dbg         (tick_dbg)
  );

  // internal signals observed by the checker and the coverage
  wire       emg_sync, fast_sync, extend;
  wire [3:0] fsm_state, fsm_next;
  assign emg_sync  = dut.emg_sync;
  assign fast_sync = dut.fast_sync;
  assign extend    = dut.u_fsm.extend;
  assign fsm_state = dut.u_fsm.state;
  assign fsm_next  = dut.u_fsm.next_state;

  traffic_checker #(.TICK_DIV(TICK_DIV), .FAST_DIV(FAST_DIV), .T_Y(T_Y), .T_G_MAX(T_G_MAX)) chk (
    .clk              (clk),
    .rst_n            (rst_n),
    .fast_sync        (fast_sync),
    .emg_sync         (emg_sync),
    .light_ns         (light_ns),
    .light_ew         (light_ew),
    .ped_lamp         (ped_lamp),
    .emergency_active (emergency_active)
  );

  // ---- Bookkeeping ------------------------------------------------------------
  int          seed, seed0;
  logic [8*32:1] tag;
  logic [8*64:1] fname;
  int          fs, ft;                      // vector files
  int          cyc      = 0;                // rising edges so far
  int          test_id  = 0;                // shown in the waveform
  int          dchecks  = 0;                // directed checks
  int          derr     = 0;                // directed errors
  int          phase    = 1;
  int          i, k, len, bad;

  // monitors used by some directed tests (sampled at the rising edge)
  int          ped_entries = 0;
  logic        emg_seen = 1'b0, pedreq_seen = 1'b0;
  logic [3:0]  prev_state = 4'd0;

  // coverage
  int          state_hits [0:8];
  int          arc_hits   [0:23];
  int          arc;

  function automatic logic [8*9:1] sname(input logic [3:0] s);
    case (s)
      NS_G:      sname = "NS_G";
      NS_Y:      sname = "NS_Y";
      RED1:      sname = "RED1";
      EW_G:      sname = "EW_G";
      EW_Y:      sname = "EW_Y";
      RED2:      sname = "RED2";
      PED_WALK:  sname = "PED_WALK";
      EMERGENCY: sname = "EMERGENCY";
      RECOVER:   sname = "RECOVER";
      default:   sname = "?";
    endcase
  endfunction

  // Arc of PLAN 1.3 taken from s to n (e = emg_sync, x = green extension), -1 if none
  function automatic int arc_id(input logic [3:0] s, input logic [3:0] n,
                                input logic e, input logic x);
    begin
      arc_id = -1;
      case (s)
        NS_G:      arc_id = x ? 1 : (n == NS_Y) ? (e ? 0 : 2) : -1;
        NS_Y:      arc_id = (n == EMERGENCY) ? 3 : (n == RED1) ? 4 : -1;
        RED1:      arc_id = (n == EMERGENCY) ? 5 : (n == PED_WALK) ? 6 : (n == EW_G) ? 7 : -1;
        EW_G:      arc_id = x ? 9 : (n == EW_Y) ? (e ? 8 : 10) : -1;
        EW_Y:      arc_id = (n == EMERGENCY) ? 11 : (n == RED2) ? 12 : -1;
        RED2:      arc_id = (n == EMERGENCY) ? 13 : (n == PED_WALK) ? 14 : (n == NS_G) ? 15 : -1;
        PED_WALK:  arc_id = (n == EMERGENCY) ? 16 : (n == EW_G) ? 17 : (n == NS_G) ? 18 : -1;
        EMERGENCY: arc_id = (n == RECOVER) ? 19 : -1;
        RECOVER:   arc_id = (n == EMERGENCY) ? 20 : (n == PED_WALK) ? 21 :
                            (n == EW_G) ? 22 : (n == NS_G) ? 23 : -1;
        default:   arc_id = -1;
      endcase
    end
  endfunction

  // ---- Every rising edge: vectors, coverage, monitors (values before the edge) --
  always @(posedge clk) begin
    $fdisplay(fs, "%0d %b %b %b %b %b %b", cyc, rst_n, ped_btn, emg_sensor, car_ns, car_ew, fast);
    $fdisplay(ft, "%0d %0d %b %b %b %h %b", cyc, state_dbg, light_ns, light_ew, ped_lamp,
              time_left, emergency_active);
    cyc++;
    if (rst_n === 1'b1 && (fsm_next != fsm_state || extend)) begin
      arc = arc_id(fsm_state, fsm_next, emg_sync, extend);
      if (arc >= 0)
        arc_hits[arc] = arc_hits[arc] + 1;
      if (fsm_next <= 4'd8 && fsm_next != fsm_state)
        state_hits[fsm_next] = state_hits[fsm_next] + 1;
    end
    if (state_dbg == PED_WALK && prev_state != PED_WALK)
      ped_entries++;
    if (emergency_active)
      emg_seen = 1'b1;
    if (ped_req_dbg)
      pedreq_seen = 1'b1;
    prev_state = state_dbg;
  end

  // ---- Directed-test helpers (all start and end at a falling edge of clk) --------
  task automatic step(input int n);
    repeat (n) @(negedge clk);
  endtask

  task automatic begin_test(input int id, input logic [8*72:1] title);
    begin
      test_id = id;
      $display("TEST_START T%0d %0t : %0s", id, $time, title);
    end
  endtask

  task automatic check(input logic ok, input logic [8*72:1] what);
    begin
      dchecks++;
      assert (ok)
        else begin
          derr++;
          if (derr <= MAX_PRINT)
            $error("T%0d %t: %0s  (state %0s, time_left %h)", test_id, $time, what,
                   sname(state_dbg), time_left);
        end
    end
  endtask

  // Reset with the given car / fast inputs; returns at the falling edge where
  // rst_n is released (state NS_G, timer T_G).
  task automatic reset_dut(input logic cns, input logic cew, input logic f);
    begin
      @(negedge clk);
      rst_n      = 1'b0;
      ped_btn    = 1'b0;
      emg_sensor = 1'b0;
      car_ns     = cns;
      car_ew     = cew;
      fast       = f;
      step(3);
      rst_n      = 1'b1;
    end
  endtask

  // Cycles until state_dbg changes, counted from the first falling edge of a
  // phase; returns at the first falling edge of the next phase.
  task automatic phase_len(output int n);
    logic [3:0] s0;
    begin
      s0 = state_dbg;
      n  = 0;
      while (state_dbg === s0 && n < 5000) begin
        @(negedge clk);
        n++;
      end
    end
  endtask

  task automatic expect_state(input logic [3:0] s);
    begin
      dchecks++;
      assert (state_dbg === s)
        else begin
          derr++;
          if (derr <= MAX_PRINT)
            $error("T%0d %t: state %0s, expected %0s", test_id, $time, sname(state_dbg), sname(s));
        end
    end
  endtask

  // Called at the first falling edge of a phase: checks the state, time_left
  // at its start and its length.
  task automatic expect_phase(input logic [3:0] s, input int n_exp, input logic [7:0] tl_exp);
    int n;
    begin
      expect_state(s);
      dchecks++;
      assert (time_left === tl_exp)
        else begin
          derr++;
          if (derr <= MAX_PRINT)
            $error("T%0d %t: %0s starts with time_left %h, expected %h", test_id, $time,
                   sname(s), time_left, tl_exp);
        end
      phase_len(n);
      dchecks++;
      assert (n == n_exp)
        else begin
          derr++;
          if (derr <= MAX_PRINT)
            $error("T%0d %t: %0s lasted %0d cycles, expected %0d", test_id, $time,
                   sname(s), n, n_exp);
        end
    end
  endtask

  // Wait (at most max_cyc cycles) for state s
  task automatic wait_state(input logic [3:0] s, input int max_cyc);
    int n;
    begin
      n = 0;
      while (state_dbg !== s && n < max_cyc) begin
        @(negedge clk);
        n++;
      end
      dchecks++;
      assert (state_dbg === s)
        else begin
          derr++;
          if (derr <= MAX_PRINT)
            $error("T%0d %t: %0s not reached within %0d cycles (state %0s)", test_id, $time,
                   sname(s), max_cyc, sname(state_dbg));
        end
    end
  endtask

  task automatic press_ped(input int n);
    begin
      ped_btn = 1'b1;
      step(n);
      ped_btn = 1'b0;
    end
  endtask

  // ---- Stimulus -----------------------------------------------------------------
  int          rst_left, emg_left, ped_left, gl_left, gl_sel;
  logic [31:0] rnd [0:10];                  // random numbers of one cycle (unsigned)

  initial begin
    if (!$value$plusargs("seed=%d", seed0))
      seed0 = 1;
    seed = seed0;
    if (!$value$plusargs("tag=%s", tag))
      $sformat(tag, "seed%0d", seed0);
    $sformat(fname, "vectors/stim_%0s.txt", tag);
    fs = $fopen(fname);
    $sformat(fname, "vectors/rtl_%0s.txt", tag);
    ft = $fopen(fname);
    $fdisplay(fs, "# traffic_tb stimulus  TICK_DIV=%0d FAST_DIV=%0d DB_DIV=%0d T_G=%0d T_G_MAX=%0d T_Y=%0d T_R=%0d T_WALK=%0d T_RC=%0d",
              TICK_DIV, FAST_DIV, DB_DIV, T_G, T_G_MAX, T_Y, T_R, T_WALK, T_RC);
    $fdisplay(fs, "# cycle rst_n ped_btn emg_sensor car_ns car_ew fast");
    $fdisplay(ft, "# traffic_tb RTL trace, seed %0d", seed0);
    $fdisplay(ft, "# cycle state light_ns light_ew ped_lamp time_left emergency_active");
    for (i = 0; i <= 8; i++)  state_hits[i] = 0;
    for (i = 0; i <= 23; i++) arc_hits[i]   = 0;

    if ($test$plusargs("vcd")) begin
      $dumpfile("traffic_tb.vcd");
      $dumpvars(1, traffic_tb);
      $dumpvars(1, traffic_tb.dut);
      $dumpvars(1, traffic_tb.dut.u_fsm);
    end
    $timeformat(-9, 0, " ns", 8);
    $display("traffic_tb: seed %0d, tag %0s", seed0, tag);

    rst_n = 1'b0; fast = 1'b0; ped_btn = 1'b0; emg_sensor = 1'b0; car_ns = 1'b1; car_ew = 1'b1;

    // ==== Phase 1: directed tests (PLAN 4.3) ========================================
    begin_test(1, "normal cycle, cars waiting on both roads: 10-3-1-10-3-1");
    reset_dut(1'b1, 1'b1, 1'b0);
    repeat (2) begin
      expect_phase(NS_G, CG, TL_G);
      expect_phase(NS_Y, CY, TL_Y);
      expect_phase(RED1, CR, TL_R);
      expect_phase(EW_G, CG, TL_G);
      expect_phase(EW_Y, CY, TL_Y);
      expect_phase(RED2, CR, TL_R);
    end
    expect_state(NS_G);

    begin_test(2, "button pressed in NS_Y: PED_WALK after RED1, then EW_G");
    reset_dut(1'b1, 1'b1, 1'b0);
    expect_phase(NS_G, CG, TL_G);
    fork
      press_ped(6);
      expect_phase(NS_Y, CY, TL_Y);
    join
    check(ped_req_dbg === 1'b1, "request latched during NS_Y");
    expect_phase(RED1, CR, TL_R);
    check(ped_req_dbg === 1'b0 && ped_lamp === 1'b1, "PED_WALK: lamp on, request cleared");
    expect_phase(PED_WALK, CW, TL_W);
    expect_state(EW_G);

    begin_test(3, "button held, then pressed three times: one PED_WALK only");
    reset_dut(1'b1, 1'b1, 1'b0);
    ped_btn = 1'b1;                         // held through a whole cycle
    ped_entries = 0;
    wait_state(PED_WALK, CG + CY + CR + 2);
    wait_state(EW_G, CW + 2);
    wait_state(RED2, CG + CY + CR + 2);
    wait_state(NS_G, CR + 2);
    step(CG / 2);
    check(ped_entries == 1 && ped_req_dbg === 1'b0, "held button: one PED_WALK");
    ped_btn = 1'b0;
    reset_dut(1'b1, 1'b1, 1'b0);
    ped_entries = 0;
    repeat (3) begin
      press_ped(6);
      step(6);
    end
    wait_state(PED_WALK, CG + CY + CR);
    wait_state(EW_G, CW + 2);
    wait_state(NS_G, CG + CY + 2 * CR + 2);
    step(CG / 2);
    check(ped_entries == 1, "three presses: one PED_WALK");

    begin_test(4, "button pressed during PED_WALK is ignored");
    reset_dut(1'b1, 1'b1, 1'b0);
    ped_entries = 0;
    press_ped(6);
    wait_state(PED_WALK, CG + CY + CR);
    press_ped(6);
    wait_state(EW_G, CW);
    check(ped_req_dbg === 1'b0, "no request left after PED_WALK");
    expect_phase(EW_G, CG, TL_G);
    expect_phase(EW_Y, CY, TL_Y);
    expect_phase(RED2, CR, TL_R);
    expect_state(NS_G);
    check(ped_entries == 1, "one PED_WALK");

    begin_test(5, "emergency in NS_G: full yellow, EMERGENCY, RECOVER, EW_G");
    reset_dut(1'b1, 1'b1, 1'b0);
    step(10);
    emg_sensor = 1'b1;
    wait_state(NS_Y, DB + 2);
    check(emergency_active === 1'b1, "emergency_active set");
    expect_phase(NS_Y, CY, TL_Y);
    expect_state(EMERGENCY);
    check(light_ns == 3'b100 && light_ew == 3'b100 && time_left == 8'h00 && !ped_lamp,
          "EMERGENCY: all red, time_left 00");
    step(30);
    expect_state(EMERGENCY);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    check(emergency_active === 1'b0, "emergency_active cleared");
    expect_phase(RECOVER, CRC, TL_RC);
    expect_state(EW_G);                     // NS was cut: EW goes first

    begin_test(6, "emergency in NS_Y: the yellow ends normally, then EMERGENCY");
    reset_dut(1'b1, 1'b1, 1'b0);
    expect_phase(NS_G, CG, TL_G);
    fork
      begin step(2); emg_sensor = 1'b1; end
      expect_phase(NS_Y, CY, TL_Y);
    join
    expect_state(EMERGENCY);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_state(EW_G);

    begin_test(7, "emergency in PED_WALK: EMERGENCY at once, walk lamp off");
    reset_dut(1'b1, 1'b1, 1'b0);
    press_ped(6);
    wait_state(PED_WALK, CG + CY + CR);
    step(3);
    emg_sensor = 1'b1;
    wait_state(EMERGENCY, DB + 2);
    check(ped_lamp === 1'b0, "walk lamp off in EMERGENCY");
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_state(EW_G);                     // the pedestrians lost their turn
    check(ped_req_dbg === 1'b0, "no pedestrian request after RECOVER");

    begin_test(8, "emergency and button together: EMERGENCY first, PED_WALK after RECOVER");
    reset_dut(1'b1, 1'b1, 1'b0);
    step(10);
    emg_sensor = 1'b1;
    press_ped(6);
    wait_state(EMERGENCY, CY + DB + 2);
    check(ped_req_dbg === 1'b1, "request kept during EMERGENCY");
    step(20);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_phase(PED_WALK, CW, TL_W);
    expect_state(EW_G);

    begin_test(9, "second emergency during RECOVER: back to EMERGENCY");
    reset_dut(1'b1, 1'b1, 1'b0);
    step(10);
    emg_sensor = 1'b1;
    wait_state(EMERGENCY, CY + DB + 2);
    step(10);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    emg_sensor = 1'b1;                      // first falling edge of RECOVER
    phase_len(len);
    check(len < CRC, "RECOVER cut by the second emergency");
    expect_state(EMERGENCY);
    step(10);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_state(EW_G);

    begin_test(10, "reset in the middle of a phase: NS_G with T_G at once");
    reset_dut(1'b1, 1'b1, 1'b0);
    wait_state(EW_G, CG + CY + CR + 2);
    step(10);
    rst_n = 1'b0;
    #1;
    check(state_dbg === NS_G && time_left === TL_G && light_ns === 3'b001 &&
          light_ew === 3'b100 && !ped_lamp && !emergency_active, "asynchronous reset");
    step(2);
    rst_n = 1'b1;
    expect_phase(NS_G, CG, TL_G);
    expect_state(NS_Y);

    begin_test(11, "1- and 2-cycle glitches on emg / ped are filtered");
    reset_dut(1'b1, 1'b1, 1'b0);
    emg_seen = 1'b0;
    pedreq_seen = 1'b0;
    fork
      begin
        step(2);
        emg_sensor = 1'b1; step(1); emg_sensor = 1'b0; step(8);
        emg_sensor = 1'b1; step(2); emg_sensor = 1'b0; step(8);
        ped_btn    = 1'b1; step(1); ped_btn    = 1'b0; step(8);
        ped_btn    = 1'b1; step(2); ped_btn    = 1'b0;
      end
      expect_phase(NS_G, CG, TL_G);         // the green is not cut
    join
    check(!emg_seen && !pedreq_seen, "no emergency, no pedestrian request");
    expect_phase(NS_Y, CY, TL_Y);
    expect_phase(RED1, CR, TL_R);
    expect_state(EW_G);                     // no PED_WALK

    begin_test(12, "3-cycle pulses on emg / ped are accepted");
    reset_dut(1'b1, 1'b1, 1'b0);
    emg_seen = 1'b0;
    step(5);
    emg_sensor = 1'b1; step(3); emg_sensor = 1'b0;
    wait_state(NS_Y, DB + 2);               // the green is cut
    check(emergency_active === 1'b1, "emergency_active set by the 3-cycle pulse");
    fork
      begin ped_btn = 1'b1; step(3); ped_btn = 1'b0; end
      expect_phase(NS_Y, CY, TL_Y);
    join
    expect_state(RED1);                     // emergency gone before the yellow ended
    check(ped_req_dbg === 1'b1, "3-cycle press latched");
    expect_phase(RED1, CR, TL_R);
    expect_state(PED_WALK);

    begin_test(13, "no car on the other road: green extended to T_G_MAX, both roads");
    reset_dut(1'b1, 1'b0, 1'b0);
    expect_phase(NS_G, CGMAX, TL_G);
    car_ns = 1'b0;                          // now nobody waits on NS
    car_ew = 1'b1;
    expect_phase(NS_Y, CY, TL_Y);
    expect_phase(RED1, CR, TL_R);
    expect_phase(EW_G, CGMAX, TL_G);
    expect_state(EW_Y);
    car_ns = 1'b1;

    begin_test(14, "a car arrives during the extension: the green ends at the next tick");
    reset_dut(1'b1, 1'b0, 1'b0);
    fork
      begin step(CG + 5); car_ew = 1'b1; end
      phase_len(len);
    join
    $display("  T14: NS_G lasted %0d cycles (%0d without extension, %0d at most)", len, CG, CGMAX);
    check(len > CG && len < CGMAX && (len % TICK_DIV) == 0, "extension stopped on a tick");
    expect_state(NS_Y);

    begin_test(15, "fast = 1: every phase twice as short (TICK_DIV / FAST_DIV)");
    reset_dut(1'b1, 1'b1, 1'b1);
    wait_state(NS_Y, CG + 2);               // the first green sees the rate change
    expect_phase(NS_Y, T_Y * FAST_DIV, TL_Y);
    expect_phase(RED1, T_R * FAST_DIV, TL_R);
    expect_phase(EW_G, T_G * FAST_DIV, TL_G);
    expect_phase(EW_Y, T_Y * FAST_DIV, TL_Y);
    expect_phase(RED2, T_R * FAST_DIV, TL_R);
    expect_phase(NS_G, T_G * FAST_DIV, TL_G);
    expect_state(NS_Y);
    fast = 1'b0;

    begin_test(16, "emergency held for a long time: all red, no timeout");
    reset_dut(1'b1, 1'b1, 1'b0);
    step(3);
    emg_sensor = 1'b1;
    wait_state(EMERGENCY, CY + DB + 4);
    bad = 0;
    for (k = 0; k < 2000; k++) begin
      @(negedge clk);
      if (state_dbg !== EMERGENCY || time_left !== 8'h00 || light_ns !== 3'b100 || light_ew !== 3'b100)
        bad++;
    end
    check(bad == 0, "2000 cycles in EMERGENCY, all red");
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_state(EW_G);

    begin_test(17, "emergency at every offset from the tick: full yellow, full RECOVER");
    for (k = 0; k < TICK_DIV; k++) begin
      reset_dut(1'b1, 1'b1, 1'b0);
      step(8 + k);
      emg_sensor = 1'b1;
      wait_state(NS_Y, DB + 2);
      expect_phase(NS_Y, CY, TL_Y);
      expect_state(EMERGENCY);
      step(5);
      emg_sensor = 1'b0;
      wait_state(RECOVER, DB + 2);
      expect_phase(RECOVER, CRC, TL_RC);
      expect_state(EW_G);
    end

    begin_test(18, "coverage: emergency in RED1 / EW_G / RED2, pedestrian after RED2");
    reset_dut(1'b1, 1'b1, 1'b0);
    expect_phase(NS_G, CG, TL_G);
    fork                                    // emg_sync rises just after the yellow
      begin step(CY - 4); emg_sensor = 1'b1; end
      expect_phase(NS_Y, CY, TL_Y);
    join
    expect_state(RED1);
    phase_len(len);
    check(len < CR, "RED1 cut by the emergency");
    expect_state(EMERGENCY);
    step(5);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    step(5);                                // EW_G -emg-> EW_Y -> EMERGENCY
    emg_sensor = 1'b1;
    wait_state(EW_Y, DB + 2);
    expect_phase(EW_Y, CY, TL_Y);
    expect_state(EMERGENCY);
    step(5);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_phase(NS_G, CG, TL_G);           // EW was cut: NS goes first
    expect_phase(NS_Y, CY, TL_Y);
    expect_phase(RED1, CR, TL_R);
    expect_phase(EW_G, CG, TL_G);
    fork
      begin step(CY - 4); emg_sensor = 1'b1; end
      expect_phase(EW_Y, CY, TL_Y);
    join
    expect_state(RED2);
    phase_len(len);
    check(len < CR, "RED2 cut by the emergency");
    expect_state(EMERGENCY);
    step(5);
    emg_sensor = 1'b0;
    wait_state(RECOVER, DB + 2);
    expect_phase(RECOVER, CRC, TL_RC);
    expect_phase(NS_G, CG, TL_G);
    expect_phase(NS_Y, CY, TL_Y);
    expect_phase(RED1, CR, TL_R);
    fork
      press_ped(6);
      expect_phase(EW_G, CG, TL_G);
    join
    expect_phase(EW_Y, CY, TL_Y);
    expect_phase(RED2, CR, TL_R);
    expect_phase(PED_WALK, CW, TL_W);
    expect_state(NS_G);

    test_id = 0;
    $display("Phase 1: %0d directed checks, %0d errors, %0d cycles", dchecks, derr, cyc);
    if ($test$plusargs("vcd"))
      $dumpoff;

    // ==== Phase 2: constrained random ===========================================
    phase = 2;
    $display("Phase 2: %0d random cycles, seed %0d", N_RANDOM, seed0);
    rst_left = 0; emg_left = 0; ped_left = 0; gl_left = 0; gl_sel = 0;
    for (i = 0; i < N_RANDOM; i++) begin
      @(negedge clk);
      // All the random numbers of the cycle are drawn first, unconditionally:
      // SystemVerilog short-circuits && and ?:, Verilog-2001 simulators may not,
      // so a $random inside a condition would give each simulator its own sequence.
      for (k = 0; k < 11; k++)
        rnd[k] = {$random(seed)};
      // reset: 1 in 5000 cycles, held 2..4 cycles
      if (rst_left > 0) begin
        rst_left = rst_left - 1;
        if (rst_left == 0) rst_n = 1'b1;
      end
      else if (rnd[0] % 5000 == 0) begin
        rst_n = 1'b0;
        rst_left = 2 + rnd[1] % 3;
      end
      // emergency: 1 in 400 cycles, held 5..60 cycles
      if (!(gl_left > 0 && gl_sel == 0)) begin
        if (emg_left > 0) begin
          emg_left = emg_left - 1;
          if (emg_left == 0) emg_sensor = 1'b0;
        end
        else if (rnd[2] % 400 == 0) begin
          emg_sensor = 1'b1;
          emg_left = 5 + rnd[3] % 56;
        end
      end
      // pedestrian: 1 in 150 cycles, pressed 3..12 cycles
      if (!(gl_left > 0 && gl_sel == 1)) begin
        if (ped_left > 0) begin
          ped_left = ped_left - 1;
          if (ped_left == 0) ped_btn = 1'b0;
        end
        else if (rnd[4] % 150 == 0) begin
          ped_btn = 1'b1;
          ped_left = 3 + rnd[5] % 10;
        end
      end
      // car sensors: each changes 1 in 80 cycles
      if (!(gl_left > 0 && gl_sel == 2) && rnd[6] % 80 == 0) car_ns = ~car_ns;
      if (!(gl_left > 0 && gl_sel == 3) && rnd[7] % 80 == 0) car_ew = ~car_ew;
      // fast: 1 in 4000 cycles
      if (rnd[8] % 4000 == 0) fast = ~fast;
      // glitch: 1 in 50 cycles, one quiet input inverted for 1 or 2 cycles
      if (gl_left > 0) begin
        gl_left = gl_left - 1;
        if (gl_left == 0)
          case (gl_sel)
            0: emg_sensor = ~emg_sensor;
            1: ped_btn    = ~ped_btn;
            2: car_ns     = ~car_ns;
            default: car_ew = ~car_ew;
          endcase
      end
      else if (rnd[9] % 50 == 0) begin
        gl_sel = rnd[10] % 4;
        if ((gl_sel == 0 && emg_left == 0) || (gl_sel == 1 && ped_left == 0) || gl_sel >= 2) begin
          gl_left = 1 + (rnd[10] / 4) % 2;
          case (gl_sel)
            0: emg_sensor = ~emg_sensor;
            1: ped_btn    = ~ped_btn;
            2: car_ns     = ~car_ns;
            default: car_ew = ~car_ew;
          endcase
        end
      end
    end
    @(negedge clk);
    $fclose(fs);
    $fclose(ft);

    // ==== Report ===============================================================
    chk.report;
    $display("Coverage: states entered");
    k = 0;
    for (i = 0; i <= 8; i++) begin
      $display("  %0d %9s %6d", i, sname(i), state_hits[i]);
      if (state_hits[i] > 0) k++;
    end
    len = 0;
    $display("Coverage: arcs of PLAN 1.3");
    for (i = 0; i <= 23; i++) begin
      $display("  arc %2d %6d", i, arc_hits[i]);
      if (arc_hits[i] > 0) len++;
    end
    $display("COVERAGE : states %0d/9, arcs %0d/24", k, len);
    if (derr == 0 && chk.violations == 0)
      $display("TRAFFIC TB PASSED : seed %0d, %0d cycles, %0d directed checks, 0 errors, 0 checker violations",
               seed0, cyc, dchecks);
    else
      $display("TRAFFIC TB FAILED : seed %0d, %0d cycles, %0d directed checks, %0d errors, %0d checker violations",
               seed0, cyc, dchecks, derr, chk.violations);
    $finish;
  end

endmodule
