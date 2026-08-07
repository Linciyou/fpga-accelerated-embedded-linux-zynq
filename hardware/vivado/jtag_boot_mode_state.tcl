# Report the latched Zynq boot mode and CPU state without resetting the board.
connect
targets -set -filter {name == "APU"}
puts "BOOT_MODE: [mrd -force -address-space AP0 0xF800025C]"
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
puts "CPU_PC: [rrd pc]"
