# ======================================================
# BRGTC6 ASIC FLow CMakeLists.txt
# ======================================================

# Setup ------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.10)
project(BRGTC6 VERSION 1.0 DESCRIPTION "Op-Centric Queues ASIC Flow" LANGUAGES NONE)
set(PROJECT_AUTHORS "Parker Schless")

# Print the project metadata ---------------------------------------------------
message(STATUS "Project Name: ${PROJECT_NAME}")
message(STATUS "Project Author: ${PROJECT_AUTHORS}")
message(STATUS "Project Version: ${PROJECT_VERSION}")
message(STATUS "Project Description: ${PROJECT_DESCRIPTION}")
message(STATUS "!! PLEASE ENSURE VERILATOR, SYNOPSYS DC, PYTHON, CADENCE INNOVUS, AND MENTOR CALIBRE(DRV) ARE AVAILABLE ON YOUR PATH !!")
message(STATUS "!! PLEASE ENSURE YOU HAVE ACCESS TO THE PDK STANDARD VIEW DIRECTORY !!")
message(STATUS "!! PLEASE ENSURE THE test/build/ DIRECTORY HAS BEEN MADE AND cmake .. HAS BEEN RUN IN IT")

# Global variables -------------------------------------------------------------
set(SRC_DIR "${CMAKE_SOURCE_DIR}/../src")
set(SOURCE_STD_VIEW_DIR "/work/global/secure/en-ec-brg-vip-tsmc-65nm-cln65gp-nda/tsmc65gp-adk-pkg/std-view")

# Define a function to add a flow version --------------------------------------
function (add_flow_version VERSION)

  set(TOP_MODULE "${VERSION}_OpCentricQueue")
  set(SOURCE_VERILOG "${SRC_DIR}/${VERSION}/${TOP_MODULE}.v")

  # Stage 0: Copy ADK standard view files and initialize -----------------------
  set(STD_VIEW_DIR "${CMAKE_BINARY_DIR}/${VERSION}/std_view")
  file(MAKE_DIRECTORY ${STD_VIEW_DIR})
  add_custom_target(${VERSION}_initialize
    COMMENT "STAGE 0: COPY AND INITIALIZE ADK STANDARD VIEW ----------"
    WORKING_DIRECTORY ${STD_VIEW_DIR}

    # Copy ADK standard view files and utility files
    COMMAND cp -rL ${SOURCE_STD_VIEW_DIR}/* .

    # Modify lef files
    COMMAND sed -i "10103i DELETEME        USE POWER \;" iocells.lef # For PVDD2DGZ_G VDDPST pin
    COMMAND sed -i 's@DELETEME@@g' iocells.lef

    # Modify GDS map file
    COMMAND sed -i "48i CUSTOM_BRG_LVS_M6  CUSTOM 136 0" gds_out.map
    COMMAND sed -i "49i CUSTOM_BRG_LVS_M5  CUSTOM 135 0" gds_out.map
    COMMAND sed -i "50i CUSTOM_BRG_LVS_M3  CUSTOM 133 0" gds_out.map
  )

  # Test 1: Run RTL simulation with Synopsys VCS -------------------------------
  set(RTL_TEST_DIR "${CMAKE_BINARY_DIR}/${VERSION}/t1_vcs_rtl")
  file(MAKE_DIRECTORY ${RTL_TEST_DIR})
  add_custom_target(${VERSION}_vcs_rtl
    COMMENT "TEST 1: RTL TEST ----------------------------------"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/../test/build
    COMMAND make ${VERSION}Full-test-vcs-rtl &> /dev/null
    COMMAND ./${VERSION}/${VERSION}Full-test/${VERSION}Full-test-vcs-rtl-out/${VERSION}Full-test-vcs-rtl-exec +verbose &> 
      ${RTL_TEST_DIR}/${VERSION}_rtl_test.log
  )

  # Stage 1: Pickle source verilog with Verilator ------------------------------
  set(PICKLE_DIR "${CMAKE_BINARY_DIR}/${VERSION}/s1_pickle")
  file(MAKE_DIRECTORY ${PICKLE_DIR}/inputs)
  file(MAKE_DIRECTORY ${PICKLE_DIR}/outputs)
  add_custom_target(${VERSION}_pickle
    COMMENT "STAGE 1: PICKLE ----------------------------------"
    WORKING_DIRECTORY ${PICKLE_DIR}
    COMMAND cp ${SOURCE_VERILOG} inputs/${TOP_MODULE}_source.sv

    # Run verilator
    COMMAND verilator -E -I${SRC_DIR} inputs/${TOP_MODULE}_source.sv > outputs/${TOP_MODULE}_pickle.v
  )

  # Stage 2: Synthesis with Synopsys Design Compiler ---------------------------
  set(SYNTHESIS_DIR "${CMAKE_BINARY_DIR}/${VERSION}/s2_synthesis")
  file(MAKE_DIRECTORY ${SYNTHESIS_DIR}/inputs)
  file(MAKE_DIRECTORY ${SYNTHESIS_DIR}/outputs)
  add_custom_target(${VERSION}_synthesis
    COMMENT "STAGE 2: SYNTHESIS ----------------------------------"
    WORKING_DIRECTORY ${SYNTHESIS_DIR}
    COMMAND cp ${PICKLE_DIR}/outputs/${TOP_MODULE}_pickle.v inputs/${TOP_MODULE}_pickle.v

    # Run Synopsys DC
    COMMAND ${CMAKE_COMMAND} -E env
      INPUT_VERILOG=inputs/${TOP_MODULE}_pickle.v
      TOP_MODULE=${TOP_MODULE}
      STD_VIEW_DIR=${STD_VIEW_DIR}
      dc_shell -f ${CMAKE_SOURCE_DIR}/utils/synthesis.tcl > outputs/synthesis.log
  )

  # Test 2: Run FFGL simulation with Synopsys VCS ------------------------------
  set(FFGL_TEST_DIR "${CMAKE_BINARY_DIR}/${VERSION}/t2_vcs_ffgl")
  file(MAKE_DIRECTORY ${FFGL_TEST_DIR})
  add_custom_target(${VERSION}_vcs_ffgl
    COMMENT "TEST 2: FFGL TEST ----------------------------------"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/../test/build
    COMMAND make ${VERSION}Full-test-vcs-ffgl &> /dev/null
    COMMAND ./${VERSION}/${VERSION}Full-test/${VERSION}Full-test-vcs-ffgl-out/${VERSION}Full-test-vcs-ffgl-exec +verbose &> 
      ${FFGL_TEST_DIR}/${VERSION}_ffgl_test.log
  )

  # Stage 3: Place and Route with Cadence Innovus ------------------------------
  set(PNR_DIR "${CMAKE_BINARY_DIR}/${VERSION}/s3_pnr")
  file(MAKE_DIRECTORY ${PNR_DIR}/inputs)
  file(MAKE_DIRECTORY ${PNR_DIR}/outputs)
  add_custom_target(${VERSION}_pnr
    COMMENT "STAGE 3: PLACE AND ROUTE ----------------------------------"
    WORKING_DIRECTORY ${PNR_DIR}
    COMMAND cp ${SYNTHESIS_DIR}/outputs/${TOP_MODULE}_synthesis.sdc inputs/${TOP_MODULE}_synthesis.sdc
    COMMAND cp ${SYNTHESIS_DIR}/outputs/${TOP_MODULE}_synthesis.v inputs/${TOP_MODULE}_synthesis.v

    # Run Cadence Innovus
    COMMAND ${CMAKE_COMMAND} -E env
      INPUT_VERILOG=inputs/${TOP_MODULE}_synthesis.v
      TOP_MODULE=${TOP_MODULE}
      STD_VIEW_DIR=${STD_VIEW_DIR}
      TIMING_FILE=${CMAKE_SOURCE_DIR}/utils/pnr_timing_setup.tcl
      INPUT_SDC=inputs/${TOP_MODULE}_synthesis.sdc
      innovus -64 -no_gui -batch -files ${CMAKE_SOURCE_DIR}/utils/pnr.tcl > outputs/pnr.log
  )

  # Test 2: Run BA simulation with Synopsys VCS --------------------------------
  set(BA_TEST_DIR "${CMAKE_BINARY_DIR}/${VERSION}/t3_vcs_ba")
  file(MAKE_DIRECTORY ${BA_TEST_DIR})
  add_custom_target(${VERSION}_vcs_ba
    COMMENT "TEST 3: BA TEST ----------------------------------"
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/../test/build/
    COMMAND make ${VERSION}Full-test-vcs-ba &> /dev/null
    COMMAND ./${VERSION}/${VERSION}Full-test/${VERSION}Full-test-vcs-ba-out/${VERSION}Full-test-vcs-ba-exec +verbose +dump-saif=${BA_TEST_DIR}/${VERSION}_ba_test.saif &>
      ${BA_TEST_DIR}/${VERSION}_ba_test.log
  )
  
  # Stage 4: Power analysis with Synopsys Primetime ----------------------------
  set(POWER_DIR "${CMAKE_BINARY_DIR}/${VERSION}/s4_power")
  file(MAKE_DIRECTORY ${POWER_DIR}/inputs)
  file(MAKE_DIRECTORY ${POWER_DIR}/outputs)
  add_custom_target(${VERSION}_power
    COMMENT "STAGE 4: POWER ANALYSIS ----------------------------------"
    WORKING_DIRECTORY ${POWER_DIR}
    COMMAND cp ${PNR_DIR}/outputs/${TOP_MODULE}_pnr_full.v inputs/${TOP_MODULE}_pnr_full.v
    COMMAND cp ${PNR_DIR}/outputs/${TOP_MODULE}_pnr.spef inputs/${TOP_MODULE}_pnr.spef
    COMMAND cp ${BA_TEST_DIR}/${VERSION}_ba_test.saif inputs/${VERSION}_ba_test.saif

    # Run Synopsys Primetime
    COMMAND ${CMAKE_COMMAND} -E env
      INPUT_VERILOG=inputs/${TOP_MODULE}_pnr_full.v
      INPUT_SAIF=inputs/${VERSION}_ba_test.saif
      TOP_MODULE=${TOP_MODULE}
      STD_VIEW_DIR=${STD_VIEW_DIR}
      INPUT_SPEF=inputs/${TOP_MODULE}_pnr.spef
      pt_shell -f ${CMAKE_SOURCE_DIR}/utils/power_analysis.tcl > outputs/power.log
  )


  # Cleaning targets -----------------------------------------------------------
  add_custom_target(${VERSION}_clean_all
    COMMENT "CLEANING ALL GENERATED FILES ----------------------------------"
    COMMAND rm -rf ${STD_VIEW_DIR}/* 
      ${RTL_TEST_DIR}/*
      ${PICKLE_DIR}/*
      ${SYNTHESIS_DIR}/*
      ${FFGL_TEST_DIR}/*
      ${PNR_DIR}/*
      ${BA_TEST_DIR}/*
      ${POWER_DIR}/*
      *.gds
      *.lyp
    COMMAND mkdir -p ${PICKLE_DIR}/inputs
      ${PICKLE_DIR}/outputs
      ${SYNTHESIS_DIR}/inputs
      ${SYNTHESIS_DIR}/outputs
      ${PNR_DIR}/inputs
      ${PNR_DIR}/outputs
      ${POWER_DIR}/inputs
      ${POWER_DIR}/outputs
  )

  add_custom_target(${VERSION}_clean_vcs_rtl
    COMMENT "CLEANING RTL TEST ----------------------------------"
    COMMAND rm -rf ${RTL_TEST_DIR}/*
  )
  
  add_custom_target(${VERSION}_clean_pickle
    COMMENT "CLEANING PICKLE ----------------------------------"
    COMMAND rm -rf ${PICKLE_DIR}/*
    COMMAND mkdir -p ${PICKLE_DIR}/inputs
      ${PICKLE_DIR}/outputs
  )
  
  add_custom_target(${VERSION}_clean_synthesis
    COMMENT "CLEANING SYNTHESIS ----------------------------------"
    COMMAND rm -rf ${SYNTHESIS_DIR}/*
    COMMAND mkdir -p ${SYNTHESIS_DIR}/inputs
      ${SYNTHESIS_DIR}/outputs
  )

  add_custom_target(${VERSION}_clean_vcs_ffgl
    COMMENT "CLEANING FFGL TEST ----------------------------------"
    COMMAND rm -rf ${FFGL_TEST_DIR}/*
  )
  
  add_custom_target(${VERSION}_clean_pnr
    COMMENT "CLEANING PLACE AND ROUTE ----------------------------------"
    COMMAND rm -rf ${PNR_DIR}/*
    COMMAND mkdir -p ${PNR_DIR}/inputs
      ${PNR_DIR}/outputs
  )

  add_custom_target(${VERSION}_clean_vcs_ba
    COMMENT "CLEANING BA TEST ----------------------------------"
    COMMAND rm -rf ${BA_TEST_DIR}/*
  )

  add_custom_target(${VERSION}_clean_power
    COMMENT "CLEANING POWER ANALYSIS ----------------------------------"
    COMMAND rm -rf ${POWER_DIR}/*
    COMMAND mkdir -p ${POWER_DIR}/inputs
      ${POWER_DIR}/outputs
  )

  # Run all stages of the flow -------------------------------------------------
  add_custom_target(${VERSION}_run_flow
    COMMAND make ${VERSION}_clean_all &&
      make ${VERSION}_initialize &&
      make ${VERSION}_vcs_rtl &&
      make ${VERSION}_pickle &&
      make ${VERSION}_synthesis &&
      make ${VERSION}_vcs_ffgl &&
      make ${VERSION}_pnr &&
      make ${VERSION}_vcs_ba &&
      make ${VERSION}_power
  )

endfunction()

# Add flow versions ------------------------------------------------------------
add_flow_version("v1")
add_flow_version("v2")
add_flow_version("v3")