## =============================================================================
## pin.xdc -- Guang top-level pin + clock constraints
## Part: xc7z020clg484-2
## =============================================================================

## System clock 50 MHz
#create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

## Generated DAC clocks (sys_clk / 2 = 25 MHz via clk_fenpin)
## Note: net name may be clk_dac after synthesis; also constrain output ports.
#create_generated_clock -name da_clk_gen \
#    -source [get_ports sys_clk] \
#    -divide_by 2 \
#    [get_ports da_clk]

#create_generated_clock -name da_clk1_gen \
#    -source [get_ports sys_clk] \
#    -divide_by 2 \
#    [get_ports da_clk1]

#set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports sys_clk]
#set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]

## DAC0 data/clock (AD9708)
#set_property PACKAGE_PIN E16 [get_ports {da_data[9]}]
#set_property PACKAGE_PIN F16 [get_ports {da_data[8]}]
#set_property PACKAGE_PIN D18 [get_ports {da_data[7]}]
#set_property PACKAGE_PIN C19 [get_ports {da_data[6]}]
#set_property PACKAGE_PIN D15 [get_ports {da_data[5]}]
#set_property PACKAGE_PIN E15 [get_ports {da_data[4]}]
#set_property PACKAGE_PIN D17 [get_ports {da_data[3]}]
#set_property PACKAGE_PIN D16 [get_ports {da_data[2]}]
#set_property PACKAGE_PIN B15 [get_ports {da_data[1]}]
#set_property PACKAGE_PIN C15 [get_ports {da_data[0]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {da_data[*]}]
#set_property PACKAGE_PIN G16 [get_ports da_clk]
#set_property IOSTANDARD LVCMOS33 [get_ports da_clk]

## DAC1 data/clock (AD9708)
#set_property PACKAGE_PIN B17 [get_ports {da_data1[9]}]
#set_property PACKAGE_PIN B16 [get_ports {da_data1[8]}]
#set_property PACKAGE_PIN B22 [get_ports {da_data1[7]}]
#set_property PACKAGE_PIN B21 [get_ports {da_data1[6]}]
#set_property PACKAGE_PIN D22 [get_ports {da_data1[5]}]
#set_property PACKAGE_PIN C22 [get_ports {da_data1[4]}]
#set_property PACKAGE_PIN E20 [get_ports {da_data1[3]}]
#set_property PACKAGE_PIN E19 [get_ports {da_data1[2]}]
#set_property PACKAGE_PIN G19 [get_ports {da_data1[1]}]
#set_property PACKAGE_PIN F19 [get_ports {da_data1[0]}]
#set_property IOSTANDARD LVCMOS33 [get_ports {da_data1[*]}]
#set_property PACKAGE_PIN A16 [get_ports da_clk1]
#set_property IOSTANDARD LVCMOS33 [get_ports da_clk1]

## Triggers / reserved
## clk_fx: reserved freq-meter input (HDL unused)
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_fx_IBUF]
#set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports clk_fx]
#set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports clk_out]
#set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports clk_light]

## UART 115200
#set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN L17} [get_ports uart_tx]
#set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN M17} [get_ports uart_rx]
