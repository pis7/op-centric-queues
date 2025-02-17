# ======================================================
# BRGTC6 Verification CMakeLists.txt
# ======================================================

# Setup ------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.10)
project(OpCentricQueues VERSION 1.0 DESCRIPTION "Op Centric Queues Source Code and Tests" LANGUAGES CXX)
set(PROJECT_AUTHORS "Parker Schless")

set(CMAKE_CXX_CREATE_SHARED_LIBRARY "<CXX_COMPILER> <CXX_FLAGS> <LINK_FLAGS> -shared <OBJECTS> -o <TARGET>")

# Add the C++ source file and create a shared library --------------------------
add_library(get_system_time_seed SHARED ${CMAKE_SOURCE_DIR}/utils/get_system_time_seed.cpp)
set_target_properties(get_system_time_seed PROPERTIES LINKER_LANGUAGE CXX)

# Add the directory containing the shared library to the linker search path ----
link_directories(${CMAKE_BINARY_DIR})

# Print the project metadata ---------------------------------------------------
message(STATUS "Project Name: ${PROJECT_NAME}")
message(STATUS "Project Author: ${PROJECT_AUTHORS}")
message(STATUS "Project Version: ${PROJECT_VERSION}")
message(STATUS "Project Description: ${PROJECT_DESCRIPTION}")
message(STATUS "!! PLEASE ENSURE VERILATOR AND/OR SYNOPSYS VCS ARE AVAILABLE ON YOUR PATH !!")

# Specify the source directory -------------------------------------------------
set(SRC_DIR ${CMAKE_SOURCE_DIR}/../src)

# Define flags for VCS and verilator -------------------------------------------
set(VCS_FLAGS_COMM
    -full64
    -sverilog
    +lint=all
    -xprop=tmerge
    -debug_access+r
    +incdir+${CMAKE_SOURCE_DIR}/+${SRC_DIR}/
    -top Top
    -override_timescale=1ns/1ps
)

set(VERILATOR_FLAGS_COMM
    -j 0
    -Wall
    -Wno-DECLFILENAME
    -Wno-UNUSEDSIGNAL
    -Wno-UNUSEDPARAM
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
    -Wno-UNOPTFLAT
    -Wno-SYNCASYNCNET
    -Wno-BLKSEQ
    -Wno-GENUNNAMED
    --autoflush
    --build
    --cc
    --exe
    --timing
    --assert
    --timescale-override 1ns/1ps
)

set(TEST_TARGETS)
set(COVERAGE_TARGETS)

# Create RTL and coverage testing target ---------------------------------------
function(add_rtl_test_target TEST_PATH)

    # Obtain file components
    get_filename_component(TEST_FOLDER ${TEST_PATH} DIRECTORY)
    get_filename_component(TEST_FILE ${TEST_PATH} NAME)
    string(REGEX REPLACE "-test" "" SRC_NAME ${TEST_FILE})

    # Create Verilator and VCS out subdirectories
    set (VERILATOR_OUT_DIR ${CMAKE_BINARY_DIR}/${TEST_FOLDER}/${TEST_FILE}/${TEST_FILE}-verilator-out)
    file(MAKE_DIRECTORY ${VERILATOR_OUT_DIR})
    set (VCS_OUT_DIR ${CMAKE_BINARY_DIR}/${TEST_FOLDER}/${TEST_FILE}/${TEST_FILE}-vcs-rtl-out)
    file(MAKE_DIRECTORY ${VCS_OUT_DIR})

    # Create VCS RTL build target
    add_custom_target(${TEST_FILE}-vcs-rtl
        COMMAND cd ${VCS_OUT_DIR} && vcs
        ${VCS_FLAGS_COMM}
        +define+TEST_PATH=${CMAKE_BINARY_DIR}/${TEST_PATH}
        ${CMAKE_SOURCE_DIR}/${TEST_PATH}.sv
        ${CMAKE_SOURCE_DIR}/utils/get_system_time_seed.cpp
        -o ${VCS_OUT_DIR}/${TEST_FILE}-vcs-rtl-exec
    )

    # Create verilator build and test targets
    add_custom_target(${TEST_FILE}-verilator
        COMMAND cd ${VERILATOR_OUT_DIR} && verilator
        ${VERILATOR_FLAGS_COMM}
        -I${SRC_DIR}
        -I${CMAKE_SOURCE_DIR}
        --coverage
        --trace
        --top-module Top ${CMAKE_SOURCE_DIR}/${TEST_PATH}.sv
        ${CMAKE_SOURCE_DIR}/utils/sim.cpp
        ${CMAKE_SOURCE_DIR}/utils/get_system_time_seed.cpp
        -o ${VERILATOR_OUT_DIR}/${TEST_FILE}-verilator-exec
    )
    add_test(
        NAME ${TEST_FILE}-verilator
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMAND ./${TEST_FOLDER}/${TEST_FILE}/${TEST_FILE}-verilator-out/${TEST_FILE}-verilator-exec
    )
    set_tests_properties(${TEST_FILE}-verilator PROPERTIES 
        PASS_REGULAR_EXPRESSION "OVERALL PASSED"
        FAIL_REGULAR_EXPRESSION "OVERALL FAILED"
        TIMEOUT 0
    )
    list(APPEND TEST_TARGETS ${TEST_FILE}-verilator)
    set(TEST_TARGETS ${TEST_TARGETS} PARENT_SCOPE)

    # Create verilator coverage target
    add_custom_target(${SRC_NAME}-coverage
        DEPENDS ${TEST_FILE}-verilator
        COMMAND ${VERILATOR_OUT_DIR}/${TEST_FILE}-verilator-exec
        COMMAND mkdir -p coverage/
        COMMAND verilator_coverage
        --annotate-all
        --annotate-min 1
        --annotate coverage/${SRC_NAME}
        logs/coverage.dat
    )
    list(APPEND COVERAGE_TARGETS ${SRC_NAME}-coverage)
    set(COVERAGE_TARGETS ${COVERAGE_TARGETS} PARENT_SCOPE)
endfunction()

enable_testing()

# Check target -----------------------------------------------------------------
add_custom_target(check
    COMMAND ${CMAKE_CTEST_COMMAND} --verbose
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Coverage target --------------------------------------------------------------
add_custom_target(coverage)

# ------------------------------------------------------------------------------
# Add tests here 
# ------------------------------------------------------------------------------

# RTL tests
add_rtl_test_target(v1/V1Main-test)

# Add dependencies -------------------------------------------------------------
add_dependencies(check ${TEST_TARGETS})
add_dependencies(coverage ${COVERAGE_TARGETS})