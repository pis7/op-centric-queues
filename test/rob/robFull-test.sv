`timescale 1ns/1ps

`ifndef ROB_FULL_TEST
`define ROB_FULL_TEST

`include "utils/ManualCheckSingleClkTB.sv"
`include "utils/TestUtilsDefs.sv"
`include "rob/rob_OpCentricQueue.v"
`include "common_defs.v"

`ifndef TIME_SEED
`define TIME_SEED
import "DPI-C" function int get_system_time_seed();
`endif

//----------------------------------------------------------------------
// Top
//----------------------------------------------------------------------
/*verilator coverage_off*/
module Top();

  `ifdef FFGL_BA
    localparam           p_num_duts                 = 1;
    localparam           p_active_duts              = 1;
    localparam integer   p_depths[p_num_duts]       = '{`ROB_DEPTH};
    localparam integer   p_bitwidths[p_num_duts]    = '{`ROB_BITWIDTH};
    string               saif_filename;
  `else
    localparam           p_num_duts                 = 4;
    localparam           p_active_duts              = 4;
    localparam integer   p_depths[p_num_duts]       = '{8, 16, 32, `ROB_DEPTH};
    localparam integer   p_bitwidths[p_num_duts]    = '{8, 16, 32, `ROB_BITWIDTH};
  `endif
  
  logic tb_go  [0:p_num_duts-1];
  logic tb_done[0:p_num_duts-1];
  logic tb_pass[0:p_num_duts-1];

  // Generate test benches
  genvar i;
  generate
    for (i = 0; i < p_active_duts; i++) begin : gen_test
      RobFullTest #(
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
    `ifdef FFGL_BA
      if (!$value$plusargs("dump-saif=%s", saif_filename)) saif_filename = "";
      if (saif_filename != "") begin
        $set_toggle_region(Top.gen_test[0].test.dut);
        $toggle_start();
      end
    `endif
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
  `ifdef FFGL_BA
    if (saif_filename != "") begin
      $toggle_stop();
      $toggle_report(saif_filename, 1e-9, Top.gen_test[0].test.dut);
    end
  `endif
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
// RobFullTest
//----------------------------------------------------------------------
module RobFullTest #(
  parameter p_bitwidth      = 32,
  parameter p_depth         = 32,
  parameter p_ptrwidth      = $clog2(p_depth),
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

  logic                  deq_front_cpl;
  logic [p_bitwidth-1:0] deq_front_data;

  logic                  ins_en;
  logic                  ins_cpl;
  logic [p_ptrwidth-1:0] ins_sn_in;
  logic [p_bitwidth-1:0] ins_data_in;

  //----------------------------------------------------------------------
  // Testbench instance
  //----------------------------------------------------------------------
  ManualCheckSingleClkTB # (
    .p_chk_nbits(p_bitwidth),
    .p_timeout_period(100000)
  ) tb (
    .reset (rst),
    .*
  );

  //----------------------------------------------------------------------
  // DUT instance
  //----------------------------------------------------------------------
  rob_OpCentricQueue #(
    .p_depth    (p_depth),
    .p_ptrwidth (p_ptrwidth),
    .p_bitwidth (p_bitwidth)
  ) dut ( .* );

  //----------------------------------------------------------------------
  // rst_reqs
  //----------------------------------------------------------------------
  task automatic rst_reqs;
    ins_en       = 1'b0;
  endtask

  //----------------------------------------------------------------------
  // insert_task
  //----------------------------------------------------------------------
  task automatic insert_task (
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] msg,
    logic [p_ptrwidth-1:0] sn,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    // Update tagged item with msg
    @(negedge clk);
    ins_data_in = msg;
    ins_sn_in = sn;
    ins_en = 1;
    while (!ins_cpl) #1;
    @(negedge clk);
    ins_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // insert_all_test
  //----------------------------------------------------------------------
  task automatic insert_all_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];
    logic [p_ptrwidth-1:0] sns[];
    src_msgs = new[p_depth];
    sns  = new[p_depth];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1)) ;
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1)) ;

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    rst_reqs();

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++) begin
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);
      sns[i] = p_depth - 1 - i;
    end

    // Insert all messages except for one at dequeue pointer
    for (int i = 0; i < p_depth-1; i++)
      insert_task (
        -1,
        src_msgs[i],
        sns[i],
        seed
      );

    // Dequeue message at dequeue pointer and check for passthrough
    fork
      begin
        insert_task (
          -1,
          src_msgs[p_depth-1],
          sns[p_depth-1],
          seed
        );
      end
      begin
        @(negedge clk);
        #1;
        tb.test_case_check(src_msgs[p_depth-1], deq_front_data, "deq_front_data");
        tb.test_case_check(1'b1, deq_front_cpl, "deq_front_cpl");
      end
    join_any

    // Check remaining dequeued messages are correct (no backpressure)
    for (int i = p_depth-2; i >= 0; i--) begin
      @(negedge clk);
      tb.test_case_check(src_msgs[i], deq_front_data, "deq_front_data");
      tb.test_case_check(1'b1, deq_front_cpl, "deq_front_cpl");
    end

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // main
  //----------------------------------------------------------------------
  task automatic run;
    string suffix = $sformatf("_bw_%0d_dp_%0d", p_bitwidth, p_depth);
    tb.test_bench_start($sformatf("RobFullTest%s", suffix));

    if (tb.test_case == 1  || tb.test_case == 0) insert_all_test($sformatf("insert_all_test%s", suffix));

    tb.test_bench_end();
  endtask

  always @(posedge go) begin
    run();
  end

endmodule
/*verilator coverage_on*/

`endif
