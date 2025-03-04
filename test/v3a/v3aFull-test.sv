`timescale 1ns/1ps

`ifndef V3A_FULL_TEST
`define V3A_FULL_TEST

`include "utils/ManualCheckSingleClkTB.sv"
`include "utils/TestUtilsDefs.sv"
`include "v3a/v3a_OpCentricQueue.v"
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
    localparam integer   p_chanwidths[p_num_duts]    = '{`TOP_CHANWIDTH};
    string               saif_filename;
  `else
    localparam           p_num_duts                  = 4;
    localparam           p_active_duts               = 1;
    localparam integer   p_depths[p_num_duts]        = '{8, 16, 32, `TOP_DEPTH};
    localparam integer   p_chanwidths[p_num_duts]    = '{8, 16, 32, `TOP_CHANWIDTH};
  `endif
  
  logic tb_go  [0:p_num_duts-1];
  logic tb_done[0:p_num_duts-1];
  logic tb_pass[0:p_num_duts-1];

  // Generate test benches
  genvar i;
  generate
    for (i = 0; i < p_active_duts; i++) begin : gen_test
      V3AFullTest #(
        .p_chanwidth (p_chanwidths[i]),
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
// V3AFullTest
//----------------------------------------------------------------------
module V3AFullTest #(
  parameter p_chanwidth     = 32,
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

  logic                   enq_back_en;
  logic                   enq_back_cpl;
  logic [p_ptrwidth-1:0]  enq_back_tag_out;
  logic [p_chanwidth-1:0] enq_back_data;

  logic                   enq_front_en;
  logic                   enq_front_cpl;
  logic [p_ptrwidth-1:0]  enq_front_tag_out;
  logic [p_chanwidth-1:0] enq_front_data;

  logic                   deq_back_en;
  logic                   deq_back_cpl;
  logic [p_chanwidth-1:0] deq_back_data;

  logic                   deq_front_en;
  logic                   deq_front_cpl;
  logic [p_chanwidth-1:0] deq_front_data;

  logic                   upd_en;
  logic                   upd_cpl;
  logic [p_ptrwidth-1:0]  upd_tag_in;
  logic [p_chanwidth-1:0] upd_data_in;

  logic                   del_en;
  logic                   del_cpl;
  logic [p_ptrwidth-1:0]  del_tag_in;

  //----------------------------------------------------------------------
  // Testbench instance
  //----------------------------------------------------------------------
  ManualCheckSingleClkTB # (
    .p_chk_nbits(p_chanwidth),
    .p_timeout_period(100000)
  ) tb (
    .reset (rst),
    .*
  );

  //----------------------------------------------------------------------
  // DUT instance
  //----------------------------------------------------------------------
  v3a_OpCentricQueue #(
    .p_depth    (p_depth),
    .p_ptrwidth (p_ptrwidth),
    .p_chanwidth (p_chanwidth)
  ) dut ( .* );

  //----------------------------------------------------------------------
  // rst_reqs
  //----------------------------------------------------------------------
  task automatic rst_reqs;
    enq_back_en  = 1'b0;
    enq_front_en = 1'b0;
    deq_back_en  = 1'b0;
    deq_front_en = 1'b0;
    upd_en       = 1'b0;
    del_en       = 1'b0;
  endtask

  //----------------------------------------------------------------------
  // enq_back_task
  //----------------------------------------------------------------------
  task automatic enq_back_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_chanwidth-1:0] msgs[],
    ref logic [p_ptrwidth-1:0] tag_out[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Send message
      @(negedge clk);
      enq_back_data = msgs[i];
      enq_back_en = 1;
      while (!enq_back_cpl) #1;
      @(negedge clk);
      tag_out[i] = enq_back_tag_out;
      enq_back_en = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // enq_back_single_task
  //----------------------------------------------------------------------
  task automatic enq_back_single_task (
    integer msg_delay = -1,
    logic [p_chanwidth-1:0]    msg,
    ref logic [p_ptrwidth-1:0] tag,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);

    // Send message
    @(negedge clk);
    enq_back_data = msg;
    enq_back_en = 1;
    while (!enq_back_cpl) #1;
    @(negedge clk);
    tag = enq_back_tag_out;
    enq_back_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // enq_front_single_task
  //----------------------------------------------------------------------
  task automatic enq_front_single_task (
    integer msg_delay = -1,
    logic [p_chanwidth-1:0]    msg,
    ref logic [p_ptrwidth-1:0] tag,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);

    // Send message
    @(negedge clk);
    enq_front_data = msg;
    enq_front_en = 1;
    while (!enq_front_cpl) #1;
    @(negedge clk);
    tag = enq_front_tag_out;
    enq_front_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // enq_front_task
  //----------------------------------------------------------------------
  task automatic enq_front_task (
    integer num_msgs,
    integer msg_delay = -1,
    logic [p_chanwidth-1:0] msgs[],
    ref logic [p_ptrwidth-1:0] tag_out[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Send message
      @(negedge clk);
      enq_front_data = msgs[i];
      enq_front_en = 1;
      while (!enq_front_cpl) #1;
      @(negedge clk);
      tag_out[i] = enq_front_tag_out;
      enq_front_en = 0;

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
    logic [p_chanwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Check result once DUT has produced it and set ready high
      @(negedge clk);
      deq_front_en = 1;
      if (!deq_front_cpl) @(posedge deq_front_cpl);
      @(negedge clk);
      tb.test_case_check(p_chanwidth'(msgs[i]), p_chanwidth'(deq_front_data));
      
      // Deassert sink_rdy so DUT knows the sink has taken the value
      deq_front_en = 0;

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
    logic [p_chanwidth-1:0] msgs[],
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    for (int i = 0; i < num_msgs; i++) begin

      // Check result once DUT has produced it and set ready high
      @(negedge clk);
      deq_back_en = 1;
      if (!deq_back_cpl) @(posedge deq_back_cpl);
      @(negedge clk);
      tb.test_case_check(p_chanwidth'(msgs[i]), p_chanwidth'(deq_back_data));
      
      // Deassert sink_rdy so DUT knows the sink has taken the value
      deq_back_en = 0;

      // Wait for some random amount of time before next action
      #msg_delay;
    end
  endtask

  //----------------------------------------------------------------------
  // deq_back_single_task
  //----------------------------------------------------------------------
  task automatic deq_back_single_task (
    integer msg_delay = -1,
    ref logic [p_chanwidth-1:0] msg,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    // Check result once DUT has produced it and set ready high
    @(negedge clk);
    deq_back_en = 1;
    if (!deq_back_cpl) @(posedge deq_back_cpl);
    @(negedge clk);
    msg = deq_back_data;
    
    // Deassert sink_rdy so DUT knows the sink has taken the value
    deq_back_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // deq_front_single_task
  //----------------------------------------------------------------------
  task automatic deq_front_single_task (
    integer msg_delay = -1,
    ref logic [p_chanwidth-1:0] msg,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    // Check result once DUT has produced it and set ready high
    @(negedge clk);
    deq_front_en = 1;
    if (!deq_front_cpl) @(posedge deq_front_cpl);
    @(negedge clk);
    msg = deq_front_data;
    
    // Deassert sink_rdy so DUT knows the sink has taken the value
    deq_front_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // update_task
  //----------------------------------------------------------------------
  task automatic update_task (
    integer msg_delay = -1,
    logic [p_chanwidth-1:0] msg,
    logic [p_ptrwidth-1:0]  tag,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    // Update tagged item with msg
    @(negedge clk);
    upd_data_in = msg;
    upd_tag_in = tag;
    upd_en = 1;
    while (!upd_cpl) #1;
    @(negedge clk);
    upd_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
  endtask

  //----------------------------------------------------------------------
  // delete_task
  //----------------------------------------------------------------------
  task automatic delete_task (
    integer msg_delay = -1,
    logic [p_ptrwidth-1:0] tag,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);

    if(msg_delay == -1) msg_delay = $urandom() % (p_max_msg_delay + 1);
    
    // Delete tagged item
    @(negedge clk);
    del_tag_in = tag;
    del_en = 1;
    while (!del_cpl) #1;
    @(negedge clk);
    del_en = 0;

    // Wait for some random amount of time before next action
    #msg_delay;
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];
    src_msgs = new[p_depth];
    tag_out  = new[p_depth];

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
    for (int i = 0; i < p_depth; i++)
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);

    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_back_tag_out"
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1));
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1));
    if (num_msgs  == -1) num_msgs  = 1 + ($urandom() % p_max_msgs);

    src_msgs = new[num_msgs];
    tag_out  = new[num_msgs];

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    rst_reqs();

    // Initialize messages to send and receive
    for (int i = 0; i < num_msgs; i++)
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);

    fork
      enq_back_task (
        num_msgs,
        -1,
        src_msgs,
        tag_out,
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_chanwidth-1:0] rev_src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    enq_front_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_front_tag_out"
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];
    src_msgs     = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end
 
    enq_front_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_front_tag_out"
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_chanwidth-1:0] rev_src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_back_tag_out"
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
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_ptrwidth-1:0] tag_out[];

    if (clk_pd    == -1) clk_pd    = p_min_clk_pd + ($urandom() % (p_max_clk_pd - p_min_clk_pd + 1));
    if (rst_delay == -1) rst_delay = clk_pd + ($urandom() % (p_max_rst_delay - clk_pd + 1));
    if (num_msgs  == -1) num_msgs  = 1 + ($urandom() % p_max_msgs);

    src_msgs = new[num_msgs];
    tag_out  = new[num_msgs];

    @(posedge clk);
    tb.test_case_begin (
      name,
      clk_pd,
      rst_delay,
      seed
    );

    rst_reqs();

    // Initialize messages to send and receive
    for (int i = 0; i < num_msgs; i++)
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);

    fork
      enq_front_task (
        num_msgs,
        -1,
        src_msgs,
        tag_out,
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
  // enqback_all_update_test
  //----------------------------------------------------------------------
  task automatic enqback_all_update_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_chanwidth-1:0] rev_src_msgs[];
    logic [p_ptrwidth-1:0]  tag_out[];
    logic [p_chanwidth-1:0] updated_msg;
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    // Enqueue messages
    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_back_tag_out"
      );

    // Update message at head of queue
    update_task (
      -1,
      {p_chanwidth{1'b1}},
      tag_out[0],
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      upd_cpl,
      "upd_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      upd_cpl,
      "upd_cpl"
    );

    // Dequeue message at head of queue
    deq_front_single_task (
      -1,
      updated_msg,
      seed
    );

    // Check updated message
    tb.test_case_check (
      {p_chanwidth{1'b1}},
      updated_msg,
      "updated_msg"
    );

    // Update message one ahead of tail of queue
    update_task (
      -1,
      {p_chanwidth{1'b1}},
      tag_out[p_depth-2],
      seed
    );

    // Dequeue message at tail of queue
    deq_back_single_task (
      -1,
      updated_msg,
      seed
    );

    // Dequeue message at tail of queue - this is the one we want
    deq_back_single_task (
      -1,
      updated_msg,
      seed
    );

    // Check updated message
    tb.test_case_check (
      {p_chanwidth{1'b1}},
      updated_msg,
      "updated_msg"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqback_all_delete_test
  //----------------------------------------------------------------------
  task automatic enqback_all_delete_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_chanwidth-1:0] rev_src_msgs[];
    logic [p_ptrwidth-1:0]  tag_out[];
    logic [p_chanwidth-1:0] updated_msg;
    logic [p_ptrwidth-1:0]  tag_ret;
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    // Enqueue messages
    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_back_tag_out"
      );

    // Update message at head of queue
    delete_task (
      -1,
      tag_out[0],
      seed
    );
    @(negedge clk);
    tb.test_case_check (
      1'b0,
      del_cpl,
      "del_cpl"
    );
    #($urandom() % (p_max_msg_delay + 1));
    tb.test_case_check (
      1'b0,
      del_cpl,
      "del_cpl"
    );

    // Dequeue message at head of queue
    deq_front_single_task (
      -1,
      updated_msg,
      seed
    );

    // Check dequeued message is the one after the deleted one
    tb.test_case_check (
      src_msgs[1],
      updated_msg,
      "updated_msg"
    );

    // Update message one ahead of tail of queue
    delete_task (
      -1,
      tag_out[p_depth-2],
      seed
    );

    // Dequeue message at tail of queue
    deq_back_single_task (
      -1,
      updated_msg,
      seed
    );

    // Dequeue message at tail of queue - this is the one we want
    deq_back_single_task (
      -1,
      updated_msg,
      seed
    );

    // Check updated message
    tb.test_case_check (
      src_msgs[p_depth-3],
      updated_msg,
      "updated_msg"
    );

    // Check enqueueing messages at the tail of the queue have the correct tags
    // This can only be done knowing the tag allocation scheme
    enq_back_single_task (
      -1,
      {p_chanwidth{1'b1}},
      tag_ret,
      seed
    );
    tb.test_case_check(
      tag_out[0],
      tag_ret,
      "tag_ret"
    );

    enq_back_single_task (
      -1,
      {p_chanwidth{1'b1}},
      tag_ret,
      seed
    );
    tb.test_case_check(
      tag_out[1],
      tag_ret,
      "tag_ret"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // enqback_simult_update_delete_test
  //----------------------------------------------------------------------
  task automatic enqback_simult_update_delete_test (
    string  name,
    integer clk_pd    = -1,
    integer rst_delay = -1,
    integer seed      = 32'(get_system_time_seed() + $time)
  );
    integer dummy_rand = $urandom(seed);
    integer ctr        = 0;
    logic [p_chanwidth-1:0] src_msgs[];
    logic [p_chanwidth-1:0] rev_src_msgs[];
    logic [p_ptrwidth-1:0]  tag_out[];
    logic [p_chanwidth-1:0] updated_msg;
    src_msgs     = new[p_depth];
    rev_src_msgs = new[p_depth];
    tag_out      = new[p_depth];

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
      src_msgs[i] = $urandom() % ((1 << p_chanwidth)-1);
    end

    for (int i = 0; i < p_depth; i++)
      rev_src_msgs[i] = src_msgs[p_depth - i - 1];
 
    // Enqueue messages
    enq_back_task (
      p_depth,
      -1,
      src_msgs,
      tag_out,
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
    for (int i = 0; i < p_depth; i++)
      tb.test_case_check (
        i,
        tag_out[i],
        "enq_back_tag_out"
      );

    fork
      update_task (
        0,
        {p_chanwidth{1'b1}},
        tag_out[0],
        seed
      );
      delete_task (
        0,
        tag_out[0],
        seed
      );
    join

    // Dequeue message at head of queue
    deq_front_single_task (
      -1,
      updated_msg,
      seed
    );

    // Check dequeued message is the one after the deleted one
    tb.test_case_check (
      src_msgs[1],
      updated_msg,
      "updated_msg"
    );

    #(`TB_CASE_DRAIN_TIME);
  endtask

  //----------------------------------------------------------------------
  // main
  //----------------------------------------------------------------------
  task automatic run;
    string suffix = $sformatf("_bw_%0d_dp_%0d", p_chanwidth, p_depth);
    tb.test_bench_start($sformatf("V3AFullTest%s", suffix));

    if (tb.test_case == 1  || tb.test_case == 0) enqback_all_deqfront_all_test($sformatf("enqback_all_deqfront_all_test%s", suffix));
    if (tb.test_case == 2  || tb.test_case == 0) enqback_deqfront_interleaved_test($sformatf("enqback_deqfront_interleaved_test%s", suffix));
    if (tb.test_case == 3  || tb.test_case == 0) enqfront_all_deqfront_all_test($sformatf("enqfront_all_deqfront_all_test%s", suffix));
    if (tb.test_case == 4  || tb.test_case == 0) enqfront_all_deqback_all_test($sformatf("enqfront_all_deqback_all_test%s", suffix));
    if (tb.test_case == 5  || tb.test_case == 0) enqback_all_deqback_all_test($sformatf("enqback_all_deqback_all_test%s", suffix));
    if (tb.test_case == 6  || tb.test_case == 0) enqfront_deqback_interleaved_test($sformatf("enqfront_deqback_interleaved_test%s", suffix));
    if (tb.test_case == 7  || tb.test_case == 0) enqback_all_update_test($sformatf("enqback_all_update_test%s", suffix));
    if (tb.test_case == 8  || tb.test_case == 0) enqback_all_delete_test($sformatf("enqback_all_delete_test%s", suffix), .clk_pd(10), .rst_delay(15));
    if (tb.test_case == 9  || tb.test_case == 0) enqback_simult_update_delete_test($sformatf("enqback_simult_update_delete_test%s", suffix), .clk_pd(10), .rst_delay(15));

    tb.test_bench_end();
  endtask

  always @(posedge go) begin
    run();
  end

endmodule
/*verilator coverage_on*/

`endif
