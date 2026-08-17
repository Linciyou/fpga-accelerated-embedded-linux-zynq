# Vivado batch script for HELLOFPGA XC7Z020 Embedded Linux + FFT accelerator.
#
# Usage in Vivado Tcl shell:
#   cd <repository-path>
#   source hardware/vivado/create_zynq7020_fft_linux.tcl
#
# This creates a block design with:
#   Zynq PS7 + simulated 100 MSPS AXI4-Stream source + XFFT + AXI DMA
#
# Review the PS7 MIO/DDR configuration against the schematic before building:
#   - Part: XC7Z020-2CLG484I
#   - DDR: MT41K256M16TW-107:P
#   - PS clock: 33.333 MHz
#   - SD: MIO40-MIO45, CD on MIO47
#   - QSPI: W25Q256 on MIO1-MIO6
#   - CH340E UART: PL Bank 34 L17/M17 via PS UART1 EMIO

set proj_name zynq7020_fft_linux
set proj_dir  [file normalize ./build/vivado/$proj_name]
set part_name xc7z020clg484-2
set bd_name   system
set rtl_dir   [file normalize ./hardware/rtl]
set sample_sim_rtl [file join $rtl_dir axis_sample_sim.v]
set mdio_iobuf_rtl [file join $rtl_dir mdio_iobuf.v]
set uart_xdc [file normalize ./hardware/vivado/zynq7020_emio_uart.xdc]
set rgmii_xdc [file normalize ./hardware/vivado/zynq7020_rgmii.xdc]

file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]
add_files -norecurse $sample_sim_rtl
add_files -norecurse $mdio_iobuf_rtl
add_files -fileset constrs_1 -norecurse $uart_xdc
add_files -fileset constrs_1 -norecurse $rgmii_xdc
update_compile_order -fileset sources_1

create_bd_design $bd_name

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR"} [get_bd_cells ps7]

# Schematic-derived high level PS settings. Vivado property availability can vary
# slightly by release; missing properties are skipped by set_ps7_property.
proc set_ps7_property {name value} {
    set prop_name CONFIG.$name
    if {[lsearch -exact [list_property [get_bd_cells ps7]] $prop_name] >= 0} {
        set_property -dict [list CONFIG.$name $value] [get_bd_cells ps7]
    }
}

set_ps7_property PCW_PRESET_BANK0_VOLTAGE LVCMOS\ 3.3V
set_ps7_property PCW_PRESET_BANK1_VOLTAGE LVCMOS\ 3.3V
set_ps7_property PCW_UIPARAM_DDR_PARTNO MT41K256M16\ RE-125
set_ps7_property PCW_UIPARAM_DDR_BUS_WIDTH 16\ Bit
set_ps7_property PCW_UIPARAM_DDR_FREQ_MHZ 533.333313
set_ps7_property PCW_USE_S_AXI_HP0 1
set_ps7_property PCW_USE_M_AXI_GP0 1
set_ps7_property PCW_USE_FABRIC_INTERRUPT 1
set_ps7_property PCW_IRQ_F2P_INTR 1
set_ps7_property PCW_EN_CLK0_PORT 1
set_ps7_property PCW_FPGA0_PERIPHERAL_FREQMHZ 100
set_ps7_property PCW_EN_CLK1_PORT 1
set_ps7_property PCW_FPGA1_PERIPHERAL_FREQMHZ 200
set_ps7_property PCW_QSPI_PERIPHERAL_ENABLE 1
set_ps7_property PCW_QSPI_GRP_SINGLE_SS_ENABLE 1
set_ps7_property PCW_SD0_PERIPHERAL_ENABLE 1
set_ps7_property PCW_SD0_GRP_CD_ENABLE 1
set_ps7_property PCW_UART1_PERIPHERAL_ENABLE 1
set_ps7_property PCW_EN_EMIO_UART1 1
set_ps7_property PCW_ENET0_PERIPHERAL_ENABLE 1
set_ps7_property PCW_ENET0_ENET0_IO EMIO
set_ps7_property PCW_ENET0_GRP_MDIO_ENABLE 1
set_ps7_property PCW_ENET0_GRP_MDIO_IO EMIO
set_ps7_property PCW_EN_EMIO_ENET0 1

# Apply the coupled GEM/EMIO settings together after the peripheral presets.
# Processing System 7 can otherwise recompute the I/O selection while an
# individual dependency is still disabled.
set_property -dict [list \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_EN_EMIO_ENET0 {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO} \
] [get_bd_cells ps7]

# The schematic routes CH340E through PL Bank 34, not PS MIO. UART1 remains
# the Linux console device (ttyPS1), with its EMIO pins exported to L17/M17.
create_bd_port -dir O ps_uart_tx
create_bd_port -dir I ps_uart_rx
connect_bd_net [get_bd_pins ps7/UART1_TX] [get_bd_ports ps_uart_tx]
connect_bd_net [get_bd_pins ps7/UART1_RX] [get_bd_ports ps_uart_rx]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_100M
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_200M
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_gp0_interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_hp0_interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_fft
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_capture
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_phy_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_fifo_to_fft
create_bd_cell -type ip -vlnv xilinx.com:ip:xfft xfft_0
create_bd_cell -type ip -vlnv xilinx.com:ip:gmii_to_rgmii gmii_to_rgmii_0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat dma_irq_concat
create_bd_cell -type module -reference axis_sample_sim sample_sim_0
create_bd_cell -type module -reference mdio_iobuf mdio_iobuf_0
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells dma_irq_concat]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {3}] [get_bd_cells axi_gp0_interconnect]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells axi_hp0_interconnect]

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
] [get_bd_cells axi_dma_fft]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells axi_gpio_capture]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] [get_bd_cells axi_gpio_phy_reset]
set_property -dict [list \
    CONFIG.C_EXTERNAL_CLOCK {false} \
    CONFIG.C_USE_IDELAY_CTRL {true} \
    CONFIG.C_PHYADDR {8} \
    CONFIG.RGMII_TXC_SKEW {0} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
] [get_bd_cells gmii_to_rgmii_0]

set_property -dict [list \
    CONFIG.FIFO_DEPTH {1024} \
    CONFIG.TDATA_NUM_BYTES {4} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
] [get_bd_cells axis_fifo_to_fft]

# XFFT configured for AXI4-Stream, 1024 point, fixed-point, scaled output.
# If your Vivado release exposes different XFFT property names, open the IP
# customization GUI once, set the same values, then write_bd_tcl to refresh this script.
set_property -dict [list \
    CONFIG.transform_length {1024} \
    CONFIG.implementation_options {pipelined_streaming_io} \
    CONFIG.input_width {16} \
    CONFIG.phase_factor_width {16} \
    CONFIG.scaling_options {scaled} \
    CONFIG.rounding_modes {convergent_rounding} \
] [get_bd_cells xfft_0]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_100M/ext_reset_in]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins rst_ps7_200M/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_200M/ext_reset_in]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins gmii_to_rgmii_0/clkin]
connect_bd_net [get_bd_pins rst_ps7_200M/peripheral_reset] [get_bd_pins gmii_to_rgmii_0/tx_reset]
connect_bd_net [get_bd_pins rst_ps7_200M/peripheral_reset] [get_bd_pins gmii_to_rgmii_0/rx_reset]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/M01_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gp0_interconnect/M02_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_hp0_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_hp0_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_hp0_interconnect/S01_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_hp0_interconnect/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_fft/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gpio_capture/s_axi_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_gpio_phy_reset/s_axi_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_fft/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axis_fifo_to_fft/s_axis_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins xfft_0/aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins sample_sim_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_dma_fft/axi_resetn]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gpio_capture/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gpio_phy_reset/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axis_fifo_to_fft/s_axis_aresetn]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins sample_sim_0/aresetn]
connect_bd_net [get_bd_pins rst_ps7_100M/interconnect_aresetn] [get_bd_pins axi_gp0_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/interconnect_aresetn] [get_bd_pins axi_hp0_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/M01_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_gp0_interconnect/M02_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_hp0_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_hp0_interconnect/S01_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_pins axi_hp0_interconnect/M00_ARESETN]

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_gp0_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_interconnect/M00_AXI] [get_bd_intf_pins axi_dma_fft/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_interconnect/M01_AXI] [get_bd_intf_pins axi_gpio_capture/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_gp0_interconnect/M02_AXI] [get_bd_intf_pins axi_gpio_phy_reset/S_AXI]

# GEM0 remains the Zynq PS hard MAC. EMIO exposes its GMII and MDIO buses to
# the PL, where the AMD bridge converts GMII timing to the board PHY's RGMII.
connect_bd_intf_net [get_bd_intf_pins ps7/GMII_ETHERNET_0] [get_bd_intf_pins gmii_to_rgmii_0/GMII]
connect_bd_intf_net [get_bd_intf_pins ps7/MDIO_ETHERNET_0] [get_bd_intf_pins gmii_to_rgmii_0/MDIO_GEM]

create_bd_port -dir I -from 3 -to 0 eth_rgmii_rxd
create_bd_port -dir I eth_rgmii_rx_ctl
create_bd_port -dir I -type clk eth_rgmii_rxc
create_bd_port -dir O -from 3 -to 0 eth_rgmii_txd
create_bd_port -dir O eth_rgmii_tx_ctl
create_bd_port -dir O -type clk eth_rgmii_txc
create_bd_port -dir O eth_mdc
create_bd_port -dir IO eth_mdio
create_bd_port -dir O eth_phy_reset_n

connect_bd_net [get_bd_ports eth_rgmii_rxd] [get_bd_pins gmii_to_rgmii_0/rgmii_rxd]
connect_bd_net [get_bd_ports eth_rgmii_rx_ctl] [get_bd_pins gmii_to_rgmii_0/rgmii_rx_ctl]
connect_bd_net [get_bd_ports eth_rgmii_rxc] [get_bd_pins gmii_to_rgmii_0/rgmii_rxc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_txd] [get_bd_ports eth_rgmii_txd]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_tx_ctl] [get_bd_ports eth_rgmii_tx_ctl]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/rgmii_txc] [get_bd_ports eth_rgmii_txc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_mdc] [get_bd_ports eth_mdc]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_o] [get_bd_pins mdio_iobuf_0/mdio_o]
connect_bd_net [get_bd_pins gmii_to_rgmii_0/mdio_phy_t] [get_bd_pins mdio_iobuf_0/mdio_t]
connect_bd_net [get_bd_pins mdio_iobuf_0/mdio_i] [get_bd_pins gmii_to_rgmii_0/mdio_phy_i]
connect_bd_net [get_bd_pins mdio_iobuf_0/mdio_io] [get_bd_ports eth_mdio]
connect_bd_net [get_bd_pins axi_gpio_phy_reset/gpio_io_o] [get_bd_ports eth_phy_reset_n]

connect_bd_intf_net [get_bd_intf_pins axi_dma_fft/M_AXI_S2MM] [get_bd_intf_pins axi_hp0_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_hp0_interconnect/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

connect_bd_intf_net [get_bd_intf_pins sample_sim_0/M_AXIS] [get_bd_intf_pins axis_fifo_to_fft/S_AXIS]
connect_bd_net [get_bd_pins axi_gpio_capture/gpio_io_o] [get_bd_pins sample_sim_0/capture_start]
connect_bd_intf_net [get_bd_intf_pins axis_fifo_to_fft/M_AXIS] [get_bd_intf_pins xfft_0/S_AXIS_DATA]
connect_bd_intf_net [get_bd_intf_pins xfft_0/M_AXIS_DATA] [get_bd_intf_pins axi_dma_fft/S_AXIS_S2MM]

connect_bd_net [get_bd_pins axi_dma_fft/s2mm_introut] [get_bd_pins dma_irq_concat/In0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant dma_irq_unused
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] [get_bd_cells dma_irq_unused]
connect_bd_net [get_bd_pins dma_irq_unused/dout] [get_bd_pins dma_irq_concat/In1]
connect_bd_net [get_bd_pins dma_irq_concat/dout] [get_bd_pins ps7/IRQ_F2P]

# The XFFT config channel drives forward FFT with a conservative scaling schedule.
# For first bring-up, tie config valid high and config data to zero. You can replace
# this with AXI GPIO later if runtime FFT/IFFT switching is needed.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xfft_cfg_valid
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xfft_cfg_data
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells xfft_cfg_valid]
set_property -dict [list CONFIG.CONST_WIDTH {16} CONFIG.CONST_VAL {0}] [get_bd_cells xfft_cfg_data]
connect_bd_net [get_bd_pins xfft_cfg_valid/dout] [get_bd_pins xfft_0/s_axis_config_tvalid]
connect_bd_net [get_bd_pins xfft_cfg_data/dout] [get_bd_pins xfft_0/s_axis_config_tdata]

assign_bd_address
set_property range 64K [get_bd_addr_segs {ps7/Data/SEG_axi_dma_fft_Reg}]
set_property offset 0x40400000 [get_bd_addr_segs {ps7/Data/SEG_axi_dma_fft_Reg}]
set_property range 64K [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_capture_Reg}]
set_property offset 0x41200000 [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_capture_Reg}]
set_property range 64K [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_phy_reset_Reg}]
set_property offset 0x41210000 [get_bd_addr_segs {ps7/Data/SEG_axi_gpio_phy_reset_Reg}]

validate_bd_design
save_bd_design

# Vivado 2025.2 can terminate an OOC gmii_to_rgmii worker after successful
# synthesis while writing its utilization report. Synthesize this small block
# design at top level so implementation remains reproducible on this host.
set_property synth_checkpoint_mode None [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd]

make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v
update_compile_order -fileset sources_1

launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
open_run impl_1
write_hw_platform -fixed -include_bit -force $proj_dir/${proj_name}.xsa

puts "Created $proj_name in $proj_dir"
puts "Generated bitstream and XSA: $proj_dir/${proj_name}.xsa"
