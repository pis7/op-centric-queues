# ======================================================
# Op-Centric Queues Synthesis TCL Script
# ======================================================

# Toplevel defs/initialization -------------------------------------------------
set input_verilog $env(INPUT_VERILOG)
set top_module    $env(TOP_MODULE)
set std_view_dir  $env(STD_VIEW_DIR)
set_app_var target_library [list ${std_view_dir}/stdcells-tc.db]
set_app_var link_library   [list * ${std_view_dir}/stdcells-tc.db]
set hdlin_ff_always_sync_set_reset      true
set compile_seqmap_honor_sync_set_reset true
set_svf -off

# Values -----------------------------------------------------------------------
set core_clk_period         10
set core_clk_port           clk
set core_clk_name           ideal_clk
set core_clk_delay_factor   0.05
set max_fanout              20
set max_transition_factor   0.25

# Read design ------------------------------------------------------------------
analyze -format sverilog ${input_verilog}

# Elaborate design -------------------------------------------------------------
elaborate ${top_module}

# Create core clock amd set input/output delays --------------------------------
create_clock -period ${core_clk_period} -name ${core_clk_name} [get_ports ${core_clk_port}]
set_input_delay  -clock ${core_clk_name} [expr ${core_clk_delay_factor}*${core_clk_period}] [all_inputs]
set_output_delay -clock ${core_clk_name} [expr ${core_clk_delay_factor}*${core_clk_period}] [all_outputs]

# Global max fanout and max signal transitions ---------------------------------
set_max_fanout     $max_fanout $top_module
set_max_transition [expr $max_transition_factor*$core_clk_period] $top_module

# Check ------------------------------------------------------------------------
check_design

# Compile ----------------------------------------------------------------------
compile_ultra -no_autoungroup -gate_clock

# Write outputs and reports ----------------------------------------------------
write -format verilog -hierarchy -output outputs/${top_module}_synthesis.v
write -format ddc     -hierarchy -output outputs/${top_module}_synthesis.ddc
write_sdf                                outputs/${top_module}_synthesis.sdf
write_sdc                       -nosplit outputs/${top_module}_synthesis.sdc
file mkdir outputs/reports
report_resources -nosplit -hierarchy > outputs/reports/resources.rpt
report_qor                           > outputs/reports/qor.rpt
report_timing -max_paths 999         > outputs/reports/timing.rpt
report_timing -slack_lesser_than 0   > outputs/reports/negative_slack_paths.rpt
report_area -nosplit -hierarchy      > outputs/reports/area.rpt
report_power -nosplit -hierarchy     > outputs/reports/power.rpt

exit