# CH340E UART signals from the board schematic.
# Zynq UART1 EMIO TX feeds CH340 RX; CH340 TX feeds UART1 EMIO RX.
set_property PACKAGE_PIN L17 [get_ports ps_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports ps_uart_tx]
set_property PACKAGE_PIN M17 [get_ports ps_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports ps_uart_rx]
