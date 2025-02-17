//========================================================================
// OpCentricQueue.v
//========================================================================
// Toplevel module connected the control unit and the datapath

`ifndef OP_CENTRIC_QUEUES_V1_TOP_V
`define OP_CENTRIC_QUEUES_V1_TOP_V

`include "v1/CtrlUnit.v"
`include "v1/RegCollection.v"

module OpCentricQueue # (
  parameter p_depth    = 32,
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Push_back interface
  //----------------------------------------------------------------------

  input  logic                  push_back_en,
  output logic                  push_back_rdy,
  input  logic [p_bitwidth-1:0] push_back_data,

  //----------------------------------------------------------------------
  // Pop_front interface
  //----------------------------------------------------------------------

  input  logic                  pop_front_en,
  output logic                  pop_front_rdy,
  output logic [p_bitwidth-1:0] pop_front_data
);

  logic                  wr_data    [p_depth];
  logic [p_bitwidth-1:0] wr_data_in;
  logic                  shift_en   [p_depth];
  logic [p_bitwidth-1:0] data_out   [p_depth];

  //----------------------------------------------------------------------
  // Control unit
  //----------------------------------------------------------------------

  v1_CtrlUnit #(
    .p_depth    (p_depth),
    .p_ptrwidth ($clog2(p_depth)),
    .p_bitwidth (p_bitwidth)
  ) ctrl_unit (
    .*
  );

  //----------------------------------------------------------------------
  // Register collection
  //----------------------------------------------------------------------

  v1_RegCollection #(
    .p_depth    (p_depth),
    .p_bitwidth (p_bitwidth)
  ) reg_collection (
    .*
  );

endmodule

`endif
