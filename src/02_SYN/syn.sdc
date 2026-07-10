# ADFP synthesis constraint file
# Revise only the cycle time while sweeping AT score.
# Start with 5 ns. If timing passes, try 4, 3, 2.5, ... ns.
set cycle 1.500

create_clock -period $cycle -name clk [get_ports clk]
set_dont_touch_network [get_clocks clk]
set_fix_hold [get_clocks clk]
set_ideal_network [get_ports clk]
set_clock_uncertainty -hold 0.005 [get_clocks clk]
set_clock_uncertainty -setup 0.03 [get_clocks clk]
set_clock_latency [expr $cycle * 0.5] [get_clocks clk]

set_input_delay  [expr $cycle * 0.5] -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr $cycle * 0.5] -clock clk [all_outputs]

set_max_delay $cycle -from [all_inputs] -to [all_outputs]
set_load 0.05 [all_outputs]
