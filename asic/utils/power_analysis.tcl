# ======================================================
# Op-Centric Queues Power Analysis TCL Script
# ======================================================

# Toplevel defs/initialization -------------------------------------------------
set std_view_dir  $env(STD_VIEW_DIR)
set_app_var target_library [list ${std_view_dir}/stdcells-tc.db]
set_app_var link_library   [list * ${std_view_dir}/stdcells-tc.db]
set_app_var power_enable_analysis true

# Values -----------------------------------------------------------------------
set core_clk_period         10
set core_clk_port           clk
set core_clk_name           ideal_clk

# Design initialization --------------------------------------------------------
read_verilog   $env(INPUT_VERILOG)
current_design $env(TOP_MODULE)
link_design

# Create clock -----------------------------------------------------------------
create_clock -period ${core_clk_period} -name ${core_clk_name} [get_ports ${core_clk_port}]

# Read SAIF and SPEF data ------------------------------------------------------
read_saif $env(INPUT_SAIF)
read_parasitics -format spef $env(INPUT_SPEF)

# Perform power analysis -------------------------------------------------------
update_power

# Generate reports -------------------------------------------------------------
file mkdir outputs/reports
report_power -nosplit            > outputs/reports/power_no_hier.rpt
report_power -nosplit -hierarchy > outputs/reports/power_hier.rpt

exit
