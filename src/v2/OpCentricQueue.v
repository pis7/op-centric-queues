//========================================================================
// OpCentricQueue.v
//========================================================================
// Toplevel module connected the control unit and the datapath

`ifndef OP_CENTRIC_QUEUES_V2_TOP_V
`define OP_CENTRIC_QUEUES_V2_TOP_V

`include "v2/CtrlUnit.v"
`include "v2/RegCollection.v"

module OpCentricQueue # (
  parameter p_depth    = 32,
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Enq_back interface
  //----------------------------------------------------------------------

  input  logic                  enq_back_req,
  output logic                  enq_back_cpl,
  input  logic [p_bitwidth-1:0] enq_back_data,

  //----------------------------------------------------------------------
  // Enq_front interface
  //----------------------------------------------------------------------

  input  logic                  enq_front_req,
  output logic                  enq_front_cpl,
  input  logic [p_bitwidth-1:0] enq_front_data,        

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  input  logic                  deq_front_req,
  output logic                  deq_front_cpl,
  output logic [p_bitwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Deq_back interface
  //----------------------------------------------------------------------

  input  logic                  deq_back_req,
  output logic                  deq_back_cpl,
  output logic [p_bitwidth-1:0] deq_back_data
);

  logic                  wr_data    [p_depth];
  logic [p_bitwidth-1:0] wr_data_in;
  logic [1:0]            shift_en   [p_depth];
  logic [p_bitwidth-1:0] data_out   [p_depth];

  //----------------------------------------------------------------------
  // Control unit
  //----------------------------------------------------------------------

  v2_CtrlUnit #(
    .p_depth    (p_depth),
    .p_ptrwidth ($clog2(p_depth)),
    .p_bitwidth (p_bitwidth)
  ) ctrl_unit (
    .*
  );

  //----------------------------------------------------------------------
  // Register collection
  //----------------------------------------------------------------------

  v2_RegCollection #(
    .p_depth    (p_depth),
    .p_bitwidth (p_bitwidth)
  ) reg_collection (
    .*
  );

endmodule

`endif
