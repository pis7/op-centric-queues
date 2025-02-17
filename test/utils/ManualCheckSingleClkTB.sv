`ifndef TEST_UTILS_MANUAL_CHECK_SINGLE_CLK_TB
`define TEST_UTILS_MANUAL_CHECK_SINGLE_CLK_TB

`include "utils/SingleClockUtils.sv"

//----------------------------------------------------------------------
// ManualCheckSingleClkTB
//----------------------------------------------------------------------
/*verilator coverage_off*/
module ManualCheckSingleClkTB #(
  parameter p_chk_nbits      = 8,
  parameter p_timeout_period = 10000
)(
  output logic clk,
  output logic reset,

  // Testbench status
  output logic done,
  output logic pass
);

// Name
string tb_name;

// Fail logic
logic failed = 0;

// Verbosity
integer verbose;

// Seed
integer seed;

// Results
string results;

// Clock utils
SingleClockUtils #(
  .p_timeout_period(p_timeout_period)
) clk_utils ( .* );

//----------------------------------------------------------------------
// Check for clock timeout
//----------------------------------------------------------------------
logic timeout_occurred;
always @(posedge timeout_occurred) begin
  $write($sformatf("\n%s%s\n", results, `CLI_RESET));
  $write($sformatf("\n%s------ %s FAILED ------%s\n", `CLI_RED, tb_name, `CLI_RESET));
  done = 1;
end

//----------------------------------------------------------------------
// test_bench_start
//----------------------------------------------------------------------
task test_bench_start(string l_name);
  tb_name = l_name;
  $display("Starting %s", tb_name);
endtask

//----------------------------------------------------------------------
// test_bench_end
//----------------------------------------------------------------------
task test_bench_end;
  if (failed) begin
    $write($sformatf("\n%s%s\n", results, `CLI_RESET));
    $write($sformatf("\n%s------ %s FAILED ------%s\n", `CLI_RED, tb_name, `CLI_RESET));
  end
  else begin
    $write($sformatf("\n%s%s\n", results, `CLI_RESET));
    $write($sformatf("\n%s------ %s PASSED ------%s\n", `CLI_GREEN, tb_name, `CLI_RESET));
    pass = 1;
  end
  done = 1;
endtask

//----------------------------------------------------------------------
// test_case_begin
//----------------------------------------------------------------------
task test_case_begin (
  string  test_name,
  integer clk_period,
  integer rst_delay,
  integer l_seed = -1
);
  results = {results, $sformatf("\n - %s @ %0dns ", test_name, $time)};
  clk_utils.set_clock (
    clk_period
  );
  clk_utils.do_reset (
    rst_delay
  );
  seed = l_seed;
endtask

//----------------------------------------------------------------------
// do_reset
//----------------------------------------------------------------------
task do_reset (
  integer rst_delay
);
  clk_utils.do_reset (
    rst_delay
  );
endtask

//----------------------------------------------------------------------
// Test case check
//----------------------------------------------------------------------
task automatic test_case_check(logic[p_chk_nbits-1:0] _ref, logic[p_chk_nbits-1:0] _dut, string msg = "");
  if (_ref !== (_ref ^ _dut ^ _ref)) begin
    case(verbose)
      0: results = {results, $sformatf("%sF(Seed=%0d)%s",`CLI_RED, seed, `CLI_RESET)};
      1: results = {results, $sformatf("\n -- %s%s FAIL @ %0dns - Expected=%x : Actual=%x | Seed=%0d%s", `CLI_RED, msg, $time, _ref, _dut, seed, `CLI_RESET)};
    endcase
    failed = 1;
  end
  else begin
    case(verbose)
      0: results = {results, $sformatf("%s.%s", `CLI_GREEN, `CLI_RESET)};
      1: results = {results, $sformatf("\n -- %s%s PASS @ %0dns - Expected=Actual=%x%s", `CLI_GREEN, msg, $time, _dut, `CLI_RESET)};
    endcase
  end
endtask

//----------------------------------------------------------------------
// Plusarg evaluation
//----------------------------------------------------------------------
string vcd_filename;
integer test_case = 0;
initial begin
  done = 0;
  pass = 0;
  if (!$value$plusargs("test-case=%d", test_case)) test_case = 0;
  if ($value$plusargs("dump-vcd=%s", vcd_filename)) begin
    $dumpfile(vcd_filename);
    $dumpvars(0, Top);
  end
  if ($test$plusargs("verbose")) verbose = 1;
  else verbose = 0;
end

endmodule
/*verilator coverage_on*/

`endif
