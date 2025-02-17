`timescale 1ns/1ps

`ifndef V1_FULL_TEST
`define V1_FULL_TEST

`include "utils/ManualCheckSingleClkTB.sv"
`include "utils/TestUtilsDefs.sv"
`include "v1/OpCentricQueue.v"

`ifndef TIME_SEED
`define TIME_SEED
import "DPI-C" function int get_system_time_seed();
`endif

//----------------------------------------------------------------------
// Top
//----------------------------------------------------------------------
/*verilator coverage_off*/
module Top();

  localparam            p_num_duts                  = 3;
  localparam            p_active_duts               = 3;
  localparam integer    p_bitwidths[p_num_duts]     = '{8, 16, 32};
  localparam integer    p_depths[p_num_duts]        = '{8, 16, 32};
  
  logic tb_go  [0:p_num_duts-1];
  logic tb_done[0:p_num_duts-1];
  logic tb_pass[0:p_num_duts-1];

  // Generate test benches
  genvar i;
  generate
    for (i = 0; i < p_active_duts; i++) begin : gen_test
      V1FullTest #(
        .p_bitwidth (p_bitwidths[i]),
        .p_depth    (p_depths[i])
      ) test (
        .go   (tb_go[i]),
        .done (tb_done[i]),
        .pass (tb_pass[i])
      );
    end
  endgenerate

  // Start test benches
  always begin
    #1; // wait for initial values to propagate
    for (int idx = 0; idx < p_active_duts; idx++) begin
      if (tb_done[idx] == 0) tb_go[idx] <= 1;
    end
  end

  // Wait for all test benches to finish and check results
  initial begin
    bit all_done = 0, all_pass = 0;
    #1; // wait for initial values to propagate
    while(!all_done) begin
      all_done = 1;
      for (int idx = 0; idx < p_active_duts; idx++) begin
        if (tb_done[idx] == 0) all_done = 0;
      end
      #1;
    end
    all_pass = 1;
    for (int idx = 0; idx < p_active_duts; idx++) begin
      if (tb_pass[idx] == 0) all_pass = 0;
    end
    if (all_pass) begin
      $write($sformatf("\n\n%s----------------------------%s\n", `CLI_GREEN, `CLI_RESET));
      $write($sformatf("%s------ OVERALL PASSED ------%s\n", `CLI_GREEN, `CLI_RESET));
      $write($sformatf("%s----------------------------%s\n\n", `CLI_GREEN, `CLI_RESET));
      $finish(0);
    end
    else begin
      $write($sformatf("\n\n%s----------------------------%s\n", `CLI_RED, `CLI_RESET));
      $write($sformatf("%s------ OVERALL FAILED ------%s\n", `CLI_RED, `CLI_RESET));
      $write($sformatf("%s----------------------------%s\n\n", `CLI_RED, `CLI_RESET));
      $finish(1);
    end
  end
endmodule

//----------------------------------------------------------------------
// V1FullTest
//----------------------------------------------------------------------
module V1FullTest #(
  parameter p_bitwidth      = 32,
  parameter p_depth         = 32,
  parameter p_min_clk_pd    = 2,
  parameter p_max_clk_pd    = 50,
  parameter p_max_rst_delay = 100,
  parameter p_max_msg_delay = 100,
  parameter p_max_msgs      = 1000
)(
  input  logic go,
  output logic done,
  output logic pass
);

  logic clk, rst;

  logic                  push_back_en;
  logic                  push_back_rdy;
  logic [p_bitwidth-1:0] push_back_data;

  logic                  pop_front_en;
  logic                  pop_front_rdy;
  logic [p_bitwidth-1:0] pop_front_data;

  //----------------------------------------------------------------------
  // Testbench instance
  //----------------------------------------------------------------------
  ManualCheckSingleClkTB # (
    .p_chk_nbits(p_bitwidth),
    .p_timeout_period(1000000)
  ) tb (
    .reset (rst),
    .*
  );

  //----------------------------------------------------------------------
  // DUT instance
  //----------------------------------------------------------------------
  OpCentricQueue #(
    .p_depth    (p_depth),
    .p_bitwidth (p_bitwidth)
  ) dut ( .* );

  //----------------------------------------------------------------------
  // push_back_task
  //----------------------------------------------------------------------
  task automatic push_back_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] src_msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Wait for DUT to be able to accept input
      while (!push_back_rdy) #1;

      // Send message
      @(negedge clk);
      push_back_data = src_msgs[i];
      push_back_en = 1;
      @(negedge clk);
      push_back_en = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // pop_front_task
  //----------------------------------------------------------------------
  task automatic pop_front_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] src_msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Check result once DUT has produced it and set ready high
      if (!pop_front_rdy) @(posedge pop_front_rdy);
      @(negedge clk);
      pop_front_en = 1;
      @(posedge clk);
      @(negedge clk);
      tb.test_case_check(p_bitwidth'(src_msgs[i]), p_bitwidth'(pop_front_data));
      
      // Deassert sink_rdy so DUT knows the sink has taken the value
      pop_front_en = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // push_all_pop_all_test
  //----------------------------------------------------------------------
  task automatic push_all_pop_all_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];
    src_msgs = new[p_depth];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1)) ;
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1)) ;

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    push_back_en = 1'b0;
    pop_front_en = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++)
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);

    push_back_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      push_back_rdy,
      "push_back_rdy"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      push_back_rdy,
      "push_back_rdy"
    );

    pop_front_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      pop_front_rdy,
      "pop_front_rdy"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      pop_front_rdy,
      "pop_front_rdy"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // main
  //----------------------------------------------------------------------
  task automatic run;
    string suffix = $sformatf("_bw_%0d_dp_%0d", p_bitwidth, p_depth);
    tb.test_bench_start($sformatf("V1FullTest%s", suffix));

    if (tb.test_case == 1  || tb.test_case == 0) push_all_pop_all_test($sformatf("push_all_pop_all_test%s", suffix));
    
    tb.test_bench_end();
  endtask

  always @(posedge go) begin
    run();
  end

endmodule
/*verilator coverage_on*/

`endif
