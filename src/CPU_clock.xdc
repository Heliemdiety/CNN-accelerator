# 1. The Clock Constraint (89.8 MHz)
create_clock -period 11.130 -name sys_clk -waveform {0.000 5.565} [get_ports clk]
