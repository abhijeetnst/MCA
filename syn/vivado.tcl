# Vivado non-project flow for the lab PCs (Artix-7, Basys3 part).
#   vivado -mode batch -source syn/vivado.tcl -tclargs systolic_top
#   vivado -mode batch -source syn/vivado.tcl -tclargs seq_matmul
# Reports land in build/vivado_<top>_{util,timing}.rpt (run from the repo root).
set top [expr {$argc > 0 ? [lindex $argv 0] : "systolic_top"}]
file mkdir build

read_verilog [glob rtl/*.v]
synth_design -top $top -part xc7a35tcpg236-1
create_clock -name clk -period 10.0 [get_ports clk]
# no pin constraints, so no bitstream; utilization and timing are all we need
opt_design
place_design
route_design

report_utilization    -file build/vivado_${top}_util.rpt
report_timing_summary -file build/vivado_${top}_timing.rpt
report_utilization
puts "WNS (ns) at 100 MHz: [get_property SLACK [get_timing_paths -max_paths 1 -setup]]"
