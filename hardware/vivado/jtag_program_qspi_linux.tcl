# Boot a temporary Linux initramfs over JTAG and let its SPI-NOR driver program QSPI.
set root_dir [file normalize [file join [file dirname [info script]] .. ..]]
set ps7_init_file [file join $root_dir build jtag_hw ps7_init.tcl]
set bit_file [file join $root_dir build vivado zynq7020_fft_linux zynq7020_fft_linux.runs impl_1 system_wrapper.bit]
set images_dir [file join $root_dir build linux_images]
set kernel_file [file join $images_dir zImage]
set initrd_file [file join $images_dir rootfs.cpio.gz]
set dtb_file [file join $images_dir zynq7020-fft-qspi-program.dtb]

foreach file [list $ps7_init_file $bit_file $kernel_file $initrd_file $dtb_file] {
	if {![file exists $file]} {
		error "Required file not found: $file"
	}
}

connect
targets -set -filter {name == "APU"}
rst -system
after 1000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
source $ps7_init_file
ps7_init
ps7_post_config
fpga $bit_file

dow -data $kernel_file 0x02000000
dow -data $initrd_file 0x06000000
dow -data $dtb_file 0x07000000
rst -processor
after 100
rwr r0 0x00000000
rwr r1 0x0000010A
rwr r2 0x07000000
con -addr 0x02000000
after 90000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
set status [lindex [mrd -value -force -address-space PA 0x1efff000 1] 0]
puts [format "QSPI_PROGRAM_STATUS: 0x%08X" $status]
if {$status != 0x51535031} {
	error [format "QSPI programming did not pass (status 0x%08X)" $status]
}
