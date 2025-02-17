`ifndef TEST_UTILS_SINGLE_CLK_UTILS
`define TEST_UTILS_SINGLE_CLK_UTILS

`timescale 1ns/1ps

`include "utils/TestUtilsDefs.sv"

//----------------------------------------------------------------------
// SingleClockUtils
//----------------------------------------------------------------------
/*verilator coverage_off*/
module SingleClockUtils #(
  parameter p_timeout_period = 10000
) (
  output logic clk,
  output logic reset,
  output logic timeout_occurred
);

//----------------------------------------------------------------------
// Initialize reset
//----------------------------------------------------------------------
initial reset  = 0;

//----------------------------------------------------------------------
// Clock controller
//----------------------------------------------------------------------
integer clk_period = 10;

logic clk_rst;
initial clk_rst = 0;

logic clk_ack;
initial clk_ack = 0;

initial clk = 1'b1;

always begin
  if (!clk_rst) begin
    clk <= ~clk;
    clk_ack <= 0;
    #(clk_period/2);
  end
  else begin
    clk <= 1'b0;
    clk_ack <= 1;
    #1;
  end
end

//----------------------------------------------------------------------
// Cycle counter + timeout check
//----------------------------------------------------------------------
int cycles = 0;
initial timeout_occurred = 0;

always @(posedge clk) begin
  if (reset)
    cycles <= 0;
  else
    cycles <= cycles + 1;

  if (cycles > p_timeout_period) begin
    $write($sformatf("\n\n%sTIMEOUT @ %0dns%s", `CLI_RED, $time, `CLI_RESET));
    timeout_occurred <= 1;
  end
end

//----------------------------------------------------------------------
// Setes clock
//----------------------------------------------------------------------
task set_clock (
  integer new_clk_period
);

  // Wait for clock to not be in delay statement and reset them
  // Note: clock will wait at logic low and transition to high at the same time
  // as the reset go high, but this should mean the high reset is not captured
  // until the next cycle as long as it is delayed by at least the new clock
  // period
  clk_rst = 1;
  while(!clk_ack) #1;
  clk_period = new_clk_period;
  clk_rst = 0;
endtask

//----------------------------------------------------------------------
// do_reset
//----------------------------------------------------------------------
task do_reset (
  integer rst_delay
);
  reset = 1;
  #rst_delay;
  reset = 0;
endtask

endmodule
/*verilator coverage_on*/

`endif
