`timescale 1ns/1ps

`ifndef V2_FULL_TEST
`define V2_FULL_TEST

`include "utils/ManualCheckSingleClkTB.sv"
`include "utils/TestUtilsDefs.sv"
`include "v2/v2_OpCentricQueue.v"
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
    localparam           p_num_duts                  = 1;
    localparam           p_active_duts               = 1;
    localparam integer   p_depths[p_num_duts]        = '{`TOP_DEPTH};
    localparam integer   p_bitwidths[p_num_duts]     = '{`TOP_CHANWIDTH};
    string               saif_filename;
  `else
    localparam           p_num_duts                  = 4;
    localparam           p_active_duts               = 4;
    localparam integer   p_depths[p_num_duts]        = '{8, 16, 32, `TOP_DEPTH};
    localparam integer   p_bitwidths[p_num_duts]     = '{8, 16, 32, `TOP_CHANWIDTH};
  `endif
  
  logic tb_go  [0:p_num_duts-1];
  logic tb_done[0:p_num_duts-1];
  logic tb_pass[0:p_num_duts-1];

  // Generate test benches
  genvar i;
  generate
    for (i = 0; i < p_active_duts; i++) begin : gen_test
      V2FullTest #(
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
// V2FullTest
//----------------------------------------------------------------------
module V2FullTest #(
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

  logic                  enq_back_req;
  logic                  enq_back_cpl;
  logic [p_bitwidth-1:0] enq_back_data;

  logic                  enq_front_req;
  logic                  enq_front_cpl;
  logic [p_bitwidth-1:0] enq_front_data;

  logic                  deq_back_req;
  logic                  deq_back_cpl;
  logic [p_bitwidth-1:0] deq_back_data;

  logic                  deq_front_req;
  logic                  deq_front_cpl;
  logic [p_bitwidth-1:0] deq_front_data;

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
  v2_OpCentricQueue #(
    .p_depth    (p_depth),
    .p_bitwidth (p_bitwidth)
  ) dut ( .* );

  //----------------------------------------------------------------------
  // enq_back_task
  //----------------------------------------------------------------------
  task automatic enq_back_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Send message
      @(negedge clk);
      enq_back_data = msgs[i];
      enq_back_req = 1;
      while (!enq_back_cpl) #1;
      @(negedge clk);
      enq_back_req = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // enq_front_task
  //----------------------------------------------------------------------
  task automatic enq_front_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Send message
      @(negedge clk);
      enq_front_data = msgs[i];
      enq_front_req = 1;
      while (!enq_front_cpl) #1;
      @(negedge clk);
      enq_front_req = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // deq_front_task
  //----------------------------------------------------------------------
  task automatic deq_front_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Check result once DUT has produced it and set ready high
      @(negedge clk);
      deq_front_req = 1;
      if (!deq_front_cpl) @(posedge deq_front_cpl);
      @(negedge clk);
      tb.test_case_check(p_bitwidth'(msgs[i]), p_bitwidth'(deq_front_data));
      
      // Deassert sink_rdy so DUT knows the sink has taken the value
      deq_front_req = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // deq_back_task
  //----------------------------------------------------------------------
  task automatic deq_back_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_bitwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Check result once DUT has produced it and set ready high
      @(negedge clk);
      deq_back_req = 1;
      if (!deq_back_cpl) @(posedge deq_back_cpl);
      @(negedge clk);
      tb.test_case_check(p_bitwidth'(msgs[i]), p_bitwidth'(deq_back_data));
      
      // Deassert sink_rdy so DUT knows the sink has taken the value
      deq_back_req = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // enqback_all_deqfront_all_test
  //----------------------------------------------------------------------
  task automatic enqback_all_deqfront_all_test (
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

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++)
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);

    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_back_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_back_cpl"
    );

    deq_front_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      deq_front_cpl,
      "deq_front_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      deq_front_cpl,
      "deq_front_cpl"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqback_deqfront_interleaved_test
  //----------------------------------------------------------------------
  task automatic enqback_deqfront_interleaved_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer num_msgs  = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1));
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1));
    if (num_msgs  == -1) num_msgs  = 1 + ($urandom() % p_max_msgs);

    src_msgs = new[num_msgs];

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < num_msgs; i++)
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);

    fork
      enq_back_task (
        num_msgs,
        -1,
        src_msgs,
        seed
      );
      deq_front_task (
        num_msgs,
        -1,
        src_msgs,
        seed
      );
    join

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqfront_all_deqfront_all_test
  //----------------------------------------------------------------------
  task automatic enqfront_all_deqfront_all_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];
    logic [p_bitwidth-1:0] rev_src_msgs[];
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1)) ;
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1)) ;

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++) begin
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    enq_front_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_back_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_back_cpl"
    );

    deq_front_task (
      p_depth,
      -1,
      rev_src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      deq_front_cpl,
      "deq_front_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      deq_front_cpl,
      "deq_front_cpl"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqfront_all_deqback_all_test
  //----------------------------------------------------------------------
  task automatic enqfront_all_deqback_all_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];
    src_msgs     = new[p_depth];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1)) ;
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1)) ;

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++) begin
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);
    end
 
    enq_front_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_front_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      enq_front_cpl,
      "enq_front_cpl"
    );

    deq_back_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      deq_back_cpl,
      "deq_back_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      deq_back_cpl,
      "deq_back_cpl"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqback_all_deqback_all_test
  //----------------------------------------------------------------------
  task automatic enqback_all_deqback_all_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];
    logic [p_bitwidth-1:0] rev_src_msgs[];
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1)) ;
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1)) ;

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < p_depth; i++) begin
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      enq_back_cpl,
      "enq_back_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      enq_back_cpl,
      "enq_back_cpl"
    );

    deq_back_task (
      p_depth,
      -1,
      rev_src_msgs,
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      deq_back_cpl,
      "deq_back_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      deq_back_cpl,
      "deq_back_cpl"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask


  //----------------------------------------------------------------------
  // enqfront_deqback_interleaved_test
  //----------------------------------------------------------------------
  task automatic enqfront_deqback_interleaved_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer num_msgs  = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_bitwidth-1:0] src_msgs[];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1));
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1));
    if (num_msgs  == -1) num_msgs  = 1 + ($urandom() % p_max_msgs);

    src_msgs = new[num_msgs];

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    enq_back_req  = 1'b0;
    enq_front_req = 1'b0;
    deq_back_req   = 1'b0;
    deq_front_req  = 1'b0;

    // Initialize messages to send and receive
    for (int i = 0; i < num_msgs; i++)
      src_msgs[i] = $urandom() % ((1 << p_bitwidth)-1);

    fork
      enq_front_task (
        num_msgs,
        -1,
        src_msgs,
        seed
      );
      deq_back_task (
        num_msgs,
        -1,
        src_msgs,
        seed
      );
    join

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // main
  //----------------------------------------------------------------------
  task automatic run;
    string suffix = $sformatf("_bw_%0d_dp_%0d", p_bitwidth, p_depth);
    tb.test_bench_start($sformatf("V2FullTest%s", suffix));

    if (tb.test_case == 1  || tb.test_case == 0) enqback_all_deqfront_all_test($sformatf("enqback_all_deqfront_all_test%s", suffix));
    if (tb.test_case == 2  || tb.test_case == 0) enqback_deqfront_interleaved_test($sformatf("enqback_deqfront_interleaved_test%s", suffix));
    if (tb.test_case == 3  || tb.test_case == 0) enqfront_all_deqfront_all_test($sformatf("enqfront_all_deqfront_all_test%s", suffix));
    if (tb.test_case == 4  || tb.test_case == 0) enqfront_all_deqback_all_test($sformatf("enqfront_all_deqback_all_test%s", suffix));
    if (tb.test_case == 5  || tb.test_case == 0) enqback_all_deqback_all_test($sformatf("enqback_all_deqback_all_test%s", suffix));
    if (tb.test_case == 6  || tb.test_case == 0) enqfront_deqback_interleaved_test($sformatf("enqfront_deqback_interleaved_test%s", suffix));

    tb.test_bench_end();
  endtask

  always @(posedge go) begin
    run();
  end

endmodule
/*verilator coverage_on*/

`endif
