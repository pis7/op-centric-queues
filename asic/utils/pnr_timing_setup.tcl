# ======================================================
# Op-Centric Queues PnR Timing/MMMC Setup TCL Script
# ======================================================

# Toplevel defs/initialization -------------------------------------------------
set std_view_dir $env(STD_VIEW_DIR)
set input_sdc    $env(INPUT_SDC)

# Create rc corners ------------------------------------------------------------
create_rc_corner -name rc_best \
   -cap_table $std_view_dir/rcbest.captable \
   -T 25

create_rc_corner -name rc_worst \
   -cap_table $std_view_dir/rcworst.captable \
   -T 25

create_rc_corner -name rc_typical \
   -cap_table $std_view_dir/typical.captable \
   -T 25

# Create library sets ----------------------------------------------------------
create_library_set -name lib_best \
   -timing [list  $std_view_dir/stdcells-bc.lib]

create_library_set -name lib_worst \
   -timing [list $std_view_dir/stdcells-wc.lib]

create_library_set -name lib_typical \
   -timing [list $std_view_dir/stdcells-tc.lib]

# Create operating conditions --------------------------------------------------
create_delay_corner -name best \
   -library_set lib_best \
   -opcond_library tcbn65gplusbc \
   -opcond BCCOM \
   -rc_corner rc_best

create_delay_corner -name worst \
   -library_set lib_worst \
   -opcond_library tcbn65gpluswc \
   -opcond WCCOM \
   -rc_corner rc_worst

create_delay_corner -name delay_typical \
   -early_library_set lib_typical \
   -late_library_set lib_typical \
   -rc_corner rc_typical

# Create constraint mode from sdc ----------------------------------------------
create_constraint_mode -name constraints_default \
   -sdc_files [list $input_sdc]

# Create analysis views --------------------------------------------------------
create_analysis_view -name analysis_setup \
   -constraint_mode constraints_default \
   -delay_corner worst

create_analysis_view -name analysis_hold \
   -constraint_mode constraints_default \
   -delay_corner best

create_analysis_view -name analysis_typical \
   -constraint_mode constraints_default \
   -delay_corner delay_typical

# Set analysis mode ------------------------------------------------------------
set_analysis_view \
   -setup [list analysis_typical] \
   -hold [list analysis_typical]