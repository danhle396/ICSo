# =============================================================================
# CE2031 Project 23 - timing constraints of de2_traffic (PLAN 5.2)
# One clock: the 50 MHz oscillator of the DE2. The switches and buttons are
# asynchronous to it and go through synchronizers (sync_debounce, reset
# synchronizer); the LEDs and 7-segment displays are read by a human. These
# paths are therefore not timed.
# No derive_clock_uncertainty: Cyclone II does not support it (Quartus 13.0:
# Warning 332153 "Family doesn't support jitter analysis").
# =============================================================================
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] LEDG[*] HEX*}]
