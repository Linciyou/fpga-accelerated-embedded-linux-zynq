# RTL8211E RGMII interface from the board schematic, FPGA Bank 35.
create_clock -name eth_rgmii_rx_clk -period 8.000 [get_ports eth_rgmii_rxc]

set_property PACKAGE_PIN B19 [get_ports eth_rgmii_rxc]
set_property PACKAGE_PIN A22 [get_ports {eth_rgmii_rxd[0]}]
set_property PACKAGE_PIN A18 [get_ports {eth_rgmii_rxd[1]}]
set_property PACKAGE_PIN A19 [get_ports {eth_rgmii_rxd[2]}]
set_property PACKAGE_PIN B20 [get_ports {eth_rgmii_rxd[3]}]
set_property PACKAGE_PIN A21 [get_ports eth_rgmii_rx_ctl]

set_property PACKAGE_PIN D21 [get_ports eth_rgmii_txc]
set_property PACKAGE_PIN E21 [get_ports {eth_rgmii_txd[0]}]
set_property PACKAGE_PIN F21 [get_ports {eth_rgmii_txd[1]}]
set_property PACKAGE_PIN F22 [get_ports {eth_rgmii_txd[2]}]
set_property PACKAGE_PIN G20 [get_ports {eth_rgmii_txd[3]}]
set_property PACKAGE_PIN G22 [get_ports eth_rgmii_tx_ctl]

set_property PACKAGE_PIN G21 [get_ports eth_mdc]
set_property PACKAGE_PIN H22 [get_ports eth_mdio]
set_property PACKAGE_PIN H17 [get_ports eth_phy_reset_n]

set_property IOSTANDARD LVCMOS33 [get_ports {eth_rgmii_rxc eth_rgmii_rxd[*] eth_rgmii_rx_ctl}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rgmii_txc eth_rgmii_txd[*] eth_rgmii_tx_ctl}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_mdc eth_mdio eth_phy_reset_n}]

# RXD1/TXDLY is strapped high, so the RTL8211E supplies the TX clock delay.
# The GMII-to-RGMII bridge must not add a second TX clock phase shift.
set_property SLEW FAST [get_ports {eth_rgmii_txc eth_rgmii_txd[*] eth_rgmii_tx_ctl}]
