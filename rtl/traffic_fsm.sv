// =============================================================================
// Module      : traffic_fsm
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override
// Description : Moore state machine of the controller, 9 states (PLAN 1.3):
//
//   state      NS EW walk  next (priority emg > done&ext > done&ped > done)
//   NS_G (0)   G  R  0     emg -> NS_Y, done&ext_ok -> NS_G (+1 tick), done -> NS_Y
//   NS_Y (1)   Y  R  0     done -> emg ? EMERGENCY : RED1
//   RED1 (2)   R  R  0     emg -> EMERGENCY, done -> ped ? PED_WALK : EW_G
//   EW_G (3)   R  G  0     same as NS_G with car_ns
//   EW_Y (4)   R  Y  0     done -> emg ? EMERGENCY : RED2
//   RED2 (5)   R  R  0     emg -> EMERGENCY, done -> ped ? PED_WALK : NS_G
//   PED_WALK(6)R  R  1     emg -> EMERGENCY, done -> next_ew ? EW_G : NS_G
//   EMERGENCY(7)R R  0     !emg -> RECOVER (no timeout)
//   RECOVER (8)R  R  0     emg -> EMERGENCY, done -> ped ? PED_WALK
//                                                     : next_ew ? EW_G : NS_G
//
//   done   = tick & (cnt == 1): last tick of the phase
//   ext_ok = no car on the other road, no pedestrian request and fewer than
//            T_G_MAX - T_G extensions so far
//   An emergency during a green goes through the full yellow first (rule 1).
//   next_ew = 1 when NS_Y is entered, 0 when EW_Y is entered: after RECOVER or
//   PED_WALK the road that was just stopped gives way (rule 2).
//   ped_req is set by a press outside PED_WALK and cleared when PED_WALK is
//   entered; clearing wins over setting in the same cycle (rule 3).
//   load = (next_state != state): the timer loads the duration of next_state
//   and clk_divider restarts (rule 4).
//
// Notes       : The state codes are localparams (no enum, for iverilog 0.9.7);
//               Quartus still recognizes the state machine and re-encodes it.
//               The lights are registered from next_state, so they change on
//               the same edge as the state register and never glitch (rule 6).
//               state_dbg is a decode of the state, never the register itself.
// =============================================================================
module traffic_fsm #(
  parameter logic [7:0] T_G     = 8'd10,    // green, ticks
  parameter logic [7:0] T_G_MAX = 8'd15,    // longest green with extensions
  parameter logic [7:0] T_Y     = 8'd3,     // yellow
  parameter logic [7:0] T_R     = 8'd1,     // all red between the two greens
  parameter logic [7:0] T_WALK  = 8'd5,     // pedestrian walk
  parameter logic [7:0] T_RC    = 8'd2      // all red after an emergency
) (
  input  logic       clk,                   // rising-edge clock
  input  logic       rst_n,                 // asynchronous reset, active low
  input  logic       tick,                  // time base
  input  logic       last,                  // timer cnt == 1
  input  logic       emg,                   // emergency (synchronized, debounced)
  input  logic       ped_pulse,             // pedestrian button, rising edge
  input  logic       car_ns,                // a car waits on NS (debounced)
  input  logic       car_ew,                // a car waits on EW (debounced)
  output logic       load,                  // a new phase starts
  output logic [7:0] load_val,              // its duration, in ticks
  output logic       hold,                  // green extension: timer keeps 1
  output logic [2:0] light_ns,              // {R,Y,G}
  output logic [2:0] light_ew,              // {R,Y,G}
  output logic       ped_lamp,              // pedestrian walk lamp
  output logic       emergency_active,      // emergency request seen
  output logic       ped_req,               // pedestrian request pending
  output logic [3:0] state_dbg              // state number 0..8
);

  timeunit 1ns;
  timeprecision 100ps;

  localparam logic [3:0] NS_G      = 4'd0;
  localparam logic [3:0] NS_Y      = 4'd1;
  localparam logic [3:0] RED1      = 4'd2;
  localparam logic [3:0] EW_G      = 4'd3;
  localparam logic [3:0] EW_Y      = 4'd4;
  localparam logic [3:0] RED2      = 4'd5;
  localparam logic [3:0] PED_WALK  = 4'd6;
  localparam logic [3:0] EMERGENCY = 4'd7;
  localparam logic [3:0] RECOVER   = 4'd8;

  localparam logic [2:0] L_R = 3'b100;      // {R,Y,G}
  localparam logic [2:0] L_Y = 3'b010;
  localparam logic [2:0] L_G = 3'b001;

  localparam logic [7:0] EXT_MAX = T_G_MAX - T_G;  // extensions per green

  logic [3:0] state, next_state;
  logic       next_ew;                      // 1: EW gets the next green
  logic [2:0] ext_cnt;                      // extensions of the current green
  logic       done, ext_room, extend;

  // ---- Next state --------------------------------------------------------------
  always_comb begin
    next_state = state;                     // default: stay
    extend     = 1'b0;
    done       = tick && last;
    ext_room   = !ped_req && (ext_cnt < EXT_MAX);
    unique case (state)
      NS_G:
        if (emg)                              next_state = NS_Y;
        else if (done && !car_ew && ext_room) extend     = 1'b1;
        else if (done)                        next_state = NS_Y;
      NS_Y:
        if (done)      next_state = emg ? EMERGENCY : RED1;
      RED1:
        if (emg)       next_state = EMERGENCY;
        else if (done) next_state = ped_req ? PED_WALK : EW_G;
      EW_G:
        if (emg)                              next_state = EW_Y;
        else if (done && !car_ns && ext_room) extend     = 1'b1;
        else if (done)                        next_state = EW_Y;
      EW_Y:
        if (done)      next_state = emg ? EMERGENCY : RED2;
      RED2:
        if (emg)       next_state = EMERGENCY;
        else if (done) next_state = ped_req ? PED_WALK : NS_G;
      PED_WALK:
        if (emg)       next_state = EMERGENCY;
        else if (done) next_state = next_ew ? EW_G : NS_G;
      EMERGENCY:
        if (!emg)      next_state = RECOVER;
      RECOVER:
        if (emg)       next_state = EMERGENCY;
        else if (done) next_state = ped_req ? PED_WALK
                                  : next_ew ? EW_G : NS_G;
      default:         next_state = NS_G;
    endcase
  end

  // ---- Timer control: duration of the state being entered ------------------
  always_comb begin
    load = (next_state != state);
    hold = extend;
    unique case (next_state)
      NS_G, EW_G: load_val = T_G;
      NS_Y, EW_Y: load_val = T_Y;
      RED1, RED2: load_val = T_R;
      PED_WALK:   load_val = T_WALK;
      RECOVER:    load_val = T_RC;
      default:    load_val = 8'd0;          // EMERGENCY: held until released
    endcase
  end

  // ---- Registers ---------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state            <= NS_G;
      next_ew          <= 1'b0;
      ext_cnt          <= 3'd0;
      ped_req          <= 1'b0;
      emergency_active <= 1'b0;
      light_ns         <= L_G;
      light_ew         <= L_R;
      ped_lamp         <= 1'b0;
    end
    else begin
      state            <= next_state;
      emergency_active <= emg;

      if (load && next_state == NS_Y)
        next_ew <= 1'b1;
      else if (load && next_state == EW_Y)
        next_ew <= 1'b0;

      if (load && (next_state == NS_G || next_state == EW_G))
        ext_cnt <= 3'd0;
      else if (extend)
        ext_cnt <= ext_cnt + 3'd1;

      if (load && next_state == PED_WALK)
        ped_req <= 1'b0;                    // served (clear wins over set)
      else if (ped_pulse && state != PED_WALK)
        ped_req <= 1'b1;                    // latched until served

      light_ns <= L_R;                      // lights of next_state
      light_ew <= L_R;
      ped_lamp <= 1'b0;
      unique case (next_state)
        NS_G:     light_ns <= L_G;
        NS_Y:     light_ns <= L_Y;
        EW_G:     light_ew <= L_G;
        EW_Y:     light_ew <= L_Y;
        PED_WALK: ped_lamp <= 1'b1;
        default:  ;                         // all red
      endcase
    end
  end

  // ---- Debug number of the state -------------------------------------------
  always_comb begin
    unique case (state)
      NS_G:      state_dbg = 4'd0;
      NS_Y:      state_dbg = 4'd1;
      RED1:      state_dbg = 4'd2;
      EW_G:      state_dbg = 4'd3;
      EW_Y:      state_dbg = 4'd4;
      RED2:      state_dbg = 4'd5;
      PED_WALK:  state_dbg = 4'd6;
      EMERGENCY: state_dbg = 4'd7;
      RECOVER:   state_dbg = 4'd8;
      default:   state_dbg = 4'hF;
    endcase
  end

endmodule
