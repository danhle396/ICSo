// =============================================================================
// Module      : traffic_top
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : The controller (Fig. 1 of the proposal), board independent:
//
//   ped_btn, emg_sensor, car_ns, car_ew, fast
//      -> sync_debounce x5 (sampled by strobe_gen) -> ped_clean / emg_sync /
//         car_ns_c / car_ew_c / fast_sync
//   clk_divider (fast_sync, restart = load) -> tick
//   traffic_fsm (tick, last, emg_sync, ped_pulse, cars) -> load, load_val, hold,
//                                                         lights, flags
//   state_timer (tick, load, load_val, hold) -> cnt, last
//   bin2bcd8 (cnt) -> time_left
//
// Parameters  : TICK_DIV / FAST_DIV / DB_DIV are the board values (50 MHz clock);
//               the testbench overrides them with small values. Durations are
//               in ticks.
// Notes       : Every net between instances is a wire (PLAN 2: the legacy
//               down-converter turns logic into reg, and a reg cannot be driven
//               by an instance output).
// =============================================================================
module traffic_top #(
  parameter int         TICK_DIV = 50_000_000, // clock cycles per tick (1 Hz)
  parameter int         FAST_DIV = 5_000_000,  // with fast = 1 (10 Hz)
  parameter int         DB_DIV   = 250_000,    // cycles between debounce samples
  parameter logic [7:0] T_G      = 8'd10,
  parameter logic [7:0] T_G_MAX  = 8'd15,
  parameter logic [7:0] T_Y      = 8'd3,
  parameter logic [7:0] T_R      = 8'd1,
  parameter logic [7:0] T_WALK   = 8'd5,
  parameter logic [7:0] T_RC     = 8'd2
) (
  input  logic       clk,                   // 50 MHz on the board
  input  logic       rst_n,                 // reset, active low
  input  logic       fast,                  // 1: ticks FAST_DIV apart
  input  logic       ped_btn,               // pedestrian button, 1 = pressed
  input  logic       emg_sensor,            // emergency vehicle sensor
  input  logic       car_ns,                // a car waits on NS
  input  logic       car_ew,                // a car waits on EW
  output wire  [2:0] light_ns,              // {R,Y,G}, one-hot
  output wire  [2:0] light_ew,              // {R,Y,G}, one-hot
  output wire        ped_lamp,              // walk lamp
  output wire  [7:0] time_left,             // ticks left in the phase, BCD
  output wire        emergency_active,      // emergency request seen
  output wire  [3:0] state_dbg,             // state number 0..8 (debug)
  output wire        ped_req_dbg,           // pedestrian request pending (debug)
  output wire        tick_dbg               // time base (debug)
);

  timeunit 1ns;
  timeprecision 100ps;

  wire       sample;                        // debounce strobe
  wire       emg_sync, ped_clean, car_ns_c, car_ew_c, fast_sync;
  wire       tick, load, hold, last;
  wire [7:0] load_val, cnt;
  logic      ped_q;                         // ped_clean one cycle ago

  // ---- Input conditioning ----------------------------------------------------
  strobe_gen #(.DIV(DB_DIV)) u_strobe (
    .clk    (clk),
    .rst_n  (rst_n),
    .strobe (sample)
  );

  sync_debounce u_db_emg  (.clk(clk), .rst_n(rst_n), .sample(sample), .din(emg_sensor), .dout(emg_sync));
  sync_debounce u_db_ped  (.clk(clk), .rst_n(rst_n), .sample(sample), .din(ped_btn),    .dout(ped_clean));
  sync_debounce u_db_cns  (.clk(clk), .rst_n(rst_n), .sample(sample), .din(car_ns),     .dout(car_ns_c));
  sync_debounce u_db_cew  (.clk(clk), .rst_n(rst_n), .sample(sample), .din(car_ew),     .dout(car_ew_c));
  sync_debounce u_db_fast (.clk(clk), .rst_n(rst_n), .sample(sample), .din(fast),       .dout(fast_sync));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ped_q <= 1'b0;
    else
      ped_q <= ped_clean;
  end

  // ---- Time base -----------------------------------------------------------------
  clk_divider #(.TICK_DIV(TICK_DIV), .FAST_DIV(FAST_DIV)) u_div (
    .clk     (clk),
    .rst_n   (rst_n),
    .fast    (fast_sync),
    .restart (load),
    .tick    (tick)
  );

  // ---- Control -------------------------------------------------------------------
  traffic_fsm #(
    .T_G(T_G), .T_G_MAX(T_G_MAX), .T_Y(T_Y), .T_R(T_R), .T_WALK(T_WALK), .T_RC(T_RC)
  ) u_fsm (
    .clk              (clk),
    .rst_n            (rst_n),
    .tick             (tick),
    .last             (last),
    .emg              (emg_sync),
    .ped_pulse        (ped_clean & ~ped_q),
    .car_ns           (car_ns_c),
    .car_ew           (car_ew_c),
    .load             (load),
    .load_val         (load_val),
    .hold             (hold),
    .light_ns         (light_ns),
    .light_ew         (light_ew),
    .ped_lamp         (ped_lamp),
    .emergency_active (emergency_active),
    .ped_req          (ped_req_dbg),
    .state_dbg        (state_dbg)
  );

  state_timer #(.RESET_VAL(T_G)) u_timer (
    .clk      (clk),
    .rst_n    (rst_n),
    .tick     (tick),
    .load     (load),
    .load_val (load_val),
    .hold     (hold),
    .cnt      (cnt),
    .last     (last)
  );

  // ---- Display -------------------------------------------------------------------
  bin2bcd8 u_bcd (
    .bin (cnt),
    .bcd (time_left)
  );

  assign tick_dbg = tick;

endmodule
