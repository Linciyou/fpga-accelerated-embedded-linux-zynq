# Recover a faulted DAP if needed, then reset into the source selected by boot straps.
connect
if {[catch {targets -set -filter {name == "APU"}}]} {
	targets 1
	rst -dap
	after 2000
	targets -set -filter {name == "APU"}
}

puts "Resetting Zynq for boot-mode-selected startup."
rst -system
after 30000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
puts "BOOT_MODE_CPU_PC: [rrd pc]"
