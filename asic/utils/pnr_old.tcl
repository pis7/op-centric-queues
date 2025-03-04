# ======================================================
# Op-Centric Queues PNR TCL Script
# ======================================================

# Toplevel defs/initialization -------------------------------------------------
set std_view_dir   $env(STD_VIEW_DIR)
set init_verilog   $env(INPUT_VERILOG)
set init_top_cell  $env(TOP_MODULE)
set init_mmmc_file $env(TIMING_FILE)
set init_lef_file  [list ${std_view_dir}/apr_tech.tlef        \
                         ${std_view_dir}/stdcells.lef]
set init_pwr_net          {VDD}
set init_gnd_net          {VSS}
set filler_list           {FILL4 FILL2 FILL1}
set hold_fixing_cell_list {BUFFD1 BUFFD2 BUFFD4 BUFFD8 BUFFD16 BUFFD24}
set lvs_exclude_list      {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G \
                            FILL32 FILL16 FILL4 FILL1 FILL2 FILL8}
set gds_merge_file_list   "${std_view_dir}/stdcells-svt.gds"
set hold_slack  0.05
set setup_slack 0.05
setMessageLimit 50

# Initialize design ------------------------------------------------------------
set init_design_uniquify 1
init_design
setAnalysisMode         -analysisType onChipVariation -cppr both
set_power_analysis_mode -analysis_view analysis_typical
setDesignMode           -process 65 -powerEffort high

# Floorplan --------------------------------------------------------------------
floorPlan -su 1.0 0.70 4.0 4.0 4.0 4.0

# Connect nets -----------------------------------------------------------------
globalNetConnect VDD -type tiehi -pin VDD -inst * -verbose
globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type tielo -pin VSS -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose

# Power ring and stripes -------------------------------------------------------
addRing   -type core_rings -nets {VDD VSS} -width 0.5 -spacing 0.6 \
  -layer {top 6 bottom 6 left 5 right 5}
addStripe -nets {VSS VDD} -layer 5 -direction vertical -width 0.4 -spacing 0.5 \
  -set_to_set_distance 5 -start 0.5
addStripe -nets {VSS VDD} -layer 4 -direction horizontal -width 0.4 -spacing 0.5 \
  -set_to_set_distance 5 -start 0.5
sroute    -allowLayerChange 1 -nets {VDD VSS} -padPinPortConnect {allPort allGeom}

# Place design cells -----------------------------------------------------------
file mkdir outputs/reports/preplace
report_ports
timeDesign  -preplace -prefix preplace_setup -outDir outputs/reports/preplace
timeDesign  -preplace -prefix preplace_hold  -outDir outputs/reports/preplace -hold
checkDesign -all -noHtml                     -outfile outputs/reports/preplace/checkDesign.rpt
check_timing
report_message -errors

file mkdir outputs/reports/place
place_opt_design -out_dir outputs/reports/place -prefix place
addTieHiLo -cell {TIEH  TIEL}
setNanoRouteMode -drouteUseMultiCutViaEffort low
setNanoRouteMode -routeAntennaCellName ANTENNA
setNanoRouteMode -routeInsertAntennaDiode true
setNanoRouteMode -routeWithEco true
setNanoRouteMode -routeWithTimingDriven true
setNanoRouteMode -routeWithSiDriven true

# CTS --------------------------------------------------------------------------
file mkdir outputs/reports/preCTS
timeDesign -preCTS -prefix preCTS_setup -outDir outputs/reports/preCTS
timeDesign -preCTS -prefix preCTS_hold  -outDir outputs/reports/preCTS -hold

file mkdir outputs/reports/CTS
clock_opt_design -outDir outputs/reports/CTS -prefix CTS

file mkdir outputs/reports/postCTS
setOptMode -fixFanoutLoad true -addInstancePrefix PostCTS_hold -addNetPrefix PostCTS_hold 
setOptMode -holdFixingCells ${hold_fixing_cell_list}
setOptMode -holdTargetSlack ${hold_slack} -setupTargetSlack ${setup_slack}
optDesign  -postCTS -prefix postCTS_opt_hold -outDir outputs/reports/postCTS -hold

# Route design -----------------------------------------------------------------
routeDesign

file mkdir outputs/reports/postRoute
optDesign  -postRoute -prefix postRoute_opt          -outDir outputs/reports/postRoute -hold
setOptMode -verbose true
setOptMode -usefulSkewPostRoute true
optDesign  -postRoute -drv -prefix postRoute_opt_drv -outDir outputs/reports/postRoute 

# Insert core filler cells -----------------------------------------------------
setFillerMode -corePrefix FILL -core ${filler_list}
addFiller

# Add custom text labels -------------------------------------------------------
add_gui_text -label VSS    -pt {398 197.5} -layer CUSTOM_BRG_LVS_M6 -height 5
add_gui_text -label VDD    -pt {403 198.5} -layer CUSTOM_BRG_LVS_M6 -height 5

# Signoff timing and power reports ---------------------------------------------
file mkdir outputs/reports/signoff
timeDesign -prefix signoff_setup -signoff -reportOnly -outDir outputs/reports/signoff
timeDesign -prefix signoff_hold  -signoff -reportOnly -outDir outputs/reports/signoff -hold

# Verify design ----------------------------------------------------------------
verifyConnectivity
verify_drc
verifyProcessAntenna

# Generate GDS -----------------------------------------------------------------
streamOut outputs/${init_top_cell}_pnr.gds -units 1000 \
  -merge   ${gds_merge_file_list} \
  -mapFile ${std_view_dir}/gds_out.map

# Save netlists ----------------------------------------------------------------
saveNetlist -excludeLeafCell -phys \
            -excludeCellInst ${lvs_exclude_list} \
            outputs/${init_top_cell}_pnr_lvs.v
saveNetlist -excludeLeafCell outputs/${init_top_cell}_pnr_vcs.v

# Perform RC extraction --------------------------------------------------------
extractRC
rcOut -rc_corner rc_typical -spef outputs/${init_top_cell}_pnr.spef

# Write SDF --------------------------------------------------------------------
write_sdf outputs/${init_top_cell}_pnr.sdf \
  -interconn all \
  -edges library \
  -recrem split \
  -remashold \
  -celltiming all \
  -recompute_delay_calc

# Save design checkpoint and exit ----------------------------------------------
saveDesign ${init_top_cell}_pnr_chkpt

# Final reports ----------------------------------------------------------------
file mkdir outputs/reports/final_reports
summaryReport -noHtml        -outfile outputs/reports/final_reports/summary.html
report_timing -late  -max_paths 999 > outputs/reports/final_reports/setup.rpt
report_timing -late  -max_slack 0   > outputs/reports/final_reports/setup_negs.rpt
report_timing -early -max_paths 999 > outputs/reports/final_reports/hold.rpt
report_timing -early -max_slack 0   > outputs/reports/final_reports/hold_negs.rpt
report_area   -verbose              > outputs/reports/final_reports/area.rpt
report_power  -hierarchy all        > outputs/reports/final_reports/power.rpt

exit

