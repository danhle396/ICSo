// =============================================================================
// Module      : de2_top
// Project     : CE2031 Digital IC Design - Project 23: Traffic Light Controller
//               FSM with Emergency Override, FPGA implementation
// Target      : Altera DE2, Cyclone II EP2C35F672C6, Quartus II 13.0 SP1
// Function    : Board wrapper of traffic_top (the single Quartus project
//               de2_traffic). Same RTL as the simulation, board parameters:
//               TICK_DIV = 50_000_000 (1 Hz), FAST_DIV = 5_000_000 (10 Hz),
//               DB_DIV = 250_000 (debounce sample every 5 ms).
// Pin mapping : CLOCK_50    -> clk                 (PLAN 6.1)
//               KEY[0]      -> rst_n  (reset synchronizer: asynchronous assert,
//                                      synchronous release)
//               KEY[1]      -> ped_btn = ~KEY[1]   (pressed = 1)
//               SW[0]       -> emg_sensor
//               SW[1]/SW[2] -> car_ns / car_ew
//               SW[17]      -> fast (x10 demo speed)
//               LEDR[0] / LEDG[1] / LEDG[0]   <- NS  R / Y / G
//               LEDR[2] / LEDG[3] / LEDG[2]   <- EW  R / Y / G
//               LEDR[17]    <- ped_lamp
//               LEDR[16]    <- pedestrian request pending
//               LEDR[15]    <- emergency_active
//               LEDG[8]     <- heartbeat: toggles on every tick (a 20 ns tick
//                              pulse would not be visible)
//               HEX1:HEX0   <- time_left (BCD)
//               HEX3 / HEX2 <- NS / EW light as a letter r, y, G (the DE2 has
//                              no yellow LED)
//               HEX4        <- state number 0..8 (PLAN 1.3)
//               HEX7:HEX5   off
//   The DE2 pushbuttons are active-low and debounced by a Schmitt trigger; the
//   toggle switches bounce, hence the debouncers inside traffic_top.
// =============================================================================
module de2_top (
  input  logic        CLOCK_50,
  input  logic [17:0] SW,
  input  logic [3:0]  KEY,
  output logic [17:0] LEDR,
  output logic [8:0]  LEDG,
  output logic [6:0]  HEX0,
  output logic [6:0]  HEX1,
  output logic [6:0]  HEX2,
  output logic [6:0]  HEX3,
  output logic [6:0]  HEX4,
  output logic [6:0]  HEX5,
  output logic [6:0]  HEX6,
  output logic [6:0]  HEX7
);

  logic       rst_meta, rst_n;              // reset synchronizer
  logic       hb;                           // heartbeat
  wire  [2:0] light_ns, light_ew;
  wire  [7:0] time_left;
  wire  [3:0] state_dbg;
  wire        ped_lamp, emergency_active, ped_req_dbg, tick_dbg;

  // ---- Reset: asynchronous assert, synchronous release -------------------------
  always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0])
      {rst_n, rst_meta} <= 2'b00;
    else
      {rst_n, rst_meta} <= {rst_meta, 1'b1};
  end

  // ---- The controller ------------------------------------------------------------
  traffic_top #(
    .TICK_DIV (50_000_000),
    .FAST_DIV (5_000_000),
    .DB_DIV   (250_000)
  ) u_top (
    .clk              (CLOCK_50),
    .rst_n            (rst_n),
    .fast             (SW[17]),
    .ped_btn          (~KEY[1]),
    .emg_sensor       (SW[0]),
    .car_ns           (SW[1]),
    .car_ew           (SW[2]),
    .light_ns         (light_ns),
    .light_ew         (light_ew),
    .ped_lamp         (ped_lamp),
    .time_left        (time_left),
    .emergency_active (emergency_active),
    .state_dbg        (state_dbg),
    .ped_req_dbg      (ped_req_dbg),
    .tick_dbg         (tick_dbg)
  );

  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n)
      hb <= 1'b0;
    else if (tick_dbg)
      hb <= ~hb;
  end

  // ---- Seven-segment displays: active low, segment order {g,f,e,d,c,b,a} ---------
  function automatic logic [6:0] hex7seg(input logic [3:0] n);
    case (n)
      4'h0: hex7seg = 7'b1000000;
      4'h1: hex7seg = 7'b1111001;
      4'h2: hex7seg = 7'b0100100;
      4'h3: hex7seg = 7'b0110000;
      4'h4: hex7seg = 7'b0011001;
      4'h5: hex7seg = 7'b0010010;
      4'h6: hex7seg = 7'b0000010;
      4'h7: hex7seg = 7'b1111000;
      4'h8: hex7seg = 7'b0000000;
      4'h9: hex7seg = 7'b0010000;
      default: hex7seg = 7'b0111111;        // '-'
    endcase
  endfunction

  function automatic logic [6:0] lamp7seg(input logic [2:0] l);
    case (l)
      3'b100:  lamp7seg = 7'b0101111;       // r
      3'b010:  lamp7seg = 7'b0010001;       // y
      3'b001:  lamp7seg = 7'b1000010;       // G
      default: lamp7seg = 7'b0111111;       // '-' (never: the lights are one-hot)
    endcase
  endfunction

  // ---- LEDs and displays ---------------------------------------------------------
  always_comb begin
    LEDR     = 18'd0;
    LEDG     = 9'd0;
    LEDR[0]  = light_ns[2];                 // NS red
    LEDG[1]  = light_ns[1];                 // NS yellow
    LEDG[0]  = light_ns[0];                 // NS green
    LEDR[2]  = light_ew[2];                 // EW red
    LEDG[3]  = light_ew[1];                 // EW yellow
    LEDG[2]  = light_ew[0];                 // EW green
    LEDR[17] = ped_lamp;
    LEDR[16] = ped_req_dbg;
    LEDR[15] = emergency_active;
    LEDG[8]  = hb;
    HEX0 = hex7seg(time_left[3:0]);
    HEX1 = hex7seg(time_left[7:4]);
    HEX2 = lamp7seg(light_ew);
    HEX3 = lamp7seg(light_ns);
    HEX4 = hex7seg(state_dbg);
    HEX5 = 7'h7F;
    HEX6 = 7'h7F;
    HEX7 = 7'h7F;
  end

endmodule
