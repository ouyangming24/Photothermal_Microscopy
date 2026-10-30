# =============================================================================
# design_pin.xdc -- design_2_wrapper (BD) top-level pin + clock constraints
# Part: xc7z020clg484-2
# Migrated from pin.xdc: port names match HDL Wrapper (*_0 suffix)
# =============================================================================

# -----------------------------------------------------------------------------
# Clock notes (Zynq BD)
# - External sys_clk / sys_rst_n / clk_fx are usually NOT on the BD wrapper top
#   when clock/reset come from PS (FCLK / FCLK_RESET). Do not keep old
#   get_ports sys_clk constraints unless those ports still exist on the wrapper.
# - If DAC clocks are still sys_clk/2 at the pins, keep generated clocks below;
#   adjust -source to your real clock (e.g. [get_clocks clk_fpga_0]) if needed.
# -----------------------------------------------------------------------------

# clk_dac = FCLK_CLK0 / 2 from fabric register u_clk_fenpin/clk_out_reg.
# Without this, DDS / sin_amp_offset / DAC output regs are reported as
# no_clock and are NOT timing-analyzed at all.
create_generated_clock -name clk_dac \
    -source [get_pins -hier -filter {NAME =~ *u_clk_fenpin/clk_out_reg/C}] \
    -divide_by 2 \
    [get_pins -hier -filter {NAME =~ *u_clk_fenpin/clk_out_reg/Q}]

# Port-level DAC clocks (only needed if adding set_output_delay for AD9708):
# create_generated_clock -name da_clk_gen \
#     -source [get_clocks clk_fpga_0] \
#     -divide_by 2 \
#     [get_ports da_clk_0]
#
# create_generated_clock -name da_clk1_gen \
#     -source [get_clocks clk_fpga_0] \
#     -divide_by 2 \
#     [get_ports da_clk1_0]

# =============================================================================
# DAC0 data/clock (AD9708)  -- was da_data / da_clk
# =============================================================================
set_property PACKAGE_PIN E16 [get_ports {da_data_0[9]}]
set_property PACKAGE_PIN F16 [get_ports {da_data_0[8]}]
set_property PACKAGE_PIN D18 [get_ports {da_data_0[7]}]
set_property PACKAGE_PIN C19 [get_ports {da_data_0[6]}]
set_property PACKAGE_PIN D15 [get_ports {da_data_0[5]}]
set_property PACKAGE_PIN E15 [get_ports {da_data_0[4]}]
set_property PACKAGE_PIN D17 [get_ports {da_data_0[3]}]
set_property PACKAGE_PIN D16 [get_ports {da_data_0[2]}]
set_property PACKAGE_PIN B15 [get_ports {da_data_0[1]}]
set_property PACKAGE_PIN C15 [get_ports {da_data_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {da_data_0[*]}]

set_property PACKAGE_PIN G16 [get_ports da_clk_0]
set_property IOSTANDARD LVCMOS33 [get_ports da_clk_0]

# =============================================================================
# DAC1 data/clock (AD9708)  -- was da_data1 / da_clk1
# =============================================================================
set_property PACKAGE_PIN B17 [get_ports {da_data1_0[9]}]
set_property PACKAGE_PIN B16 [get_ports {da_data1_0[8]}]
set_property PACKAGE_PIN B22 [get_ports {da_data1_0[7]}]
set_property PACKAGE_PIN B21 [get_ports {da_data1_0[6]}]
set_property PACKAGE_PIN D22 [get_ports {da_data1_0[5]}]
set_property PACKAGE_PIN C22 [get_ports {da_data1_0[4]}]
set_property PACKAGE_PIN E20 [get_ports {da_data1_0[3]}]
set_property PACKAGE_PIN E19 [get_ports {da_data1_0[2]}]
set_property PACKAGE_PIN G19 [get_ports {da_data1_0[1]}]
set_property PACKAGE_PIN F19 [get_ports {da_data1_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {da_data1_0[*]}]

set_property PACKAGE_PIN A16 [get_ports da_clk1_0]
set_property IOSTANDARD LVCMOS33 [get_ports da_clk1_0]

# =============================================================================
# Triggers / misc  -- was clk_out / clk_light
# =============================================================================
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports clk_out_0]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports clk_light_0]

# =============================================================================
# UART 115200  -- was uart_tx / uart_rx
# =============================================================================
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN L17} [get_ports uart_tx_0]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN M17} [get_ports uart_rx_0]

# =============================================================================
# Old ports kept for reference (enable ONLY if still present on wrapper)
# =============================================================================
# set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports sys_clk]
# set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
# set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_fx_IBUF]
# set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports clk_fx]
# create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
