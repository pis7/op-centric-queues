//========================================================================
// OpCentricQueue.v
//========================================================================
// Toplevel module connected the control unit and the datapath

`ifndef V3A_OP_CENTRIC_QUEUE_V
`define V3A_OP_CENTRIC_QUEUE_V

`include "v3a/CtrlUnit.v"
`include "v3a/RegCollection.v"
`include "common_defs.v"

module v3a_OpCentricQueue # (
  parameter p_depth     = `TOP_DEPTH,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_chanwidth = `TOP_CHANWIDTH,
  parameter p_bitwidth  = p_chanwidth + p_ptrwidth
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Enq_back interface
  //----------------------------------------------------------------------

  input  logic                   enq_back_en,
  output logic                   enq_back_cpl,
  output logic [p_ptrwidth-1:0]  enq_back_tag_out,
  input  logic [p_chanwidth-1:0] enq_back_data,

  //----------------------------------------------------------------------
  // Enq_front interface
  //----------------------------------------------------------------------

  input  logic                   enq_front_en,
  output logic                   enq_front_cpl,
  output logic [p_ptrwidth-1:0]  enq_front_tag_out,
  input  logic [p_chanwidth-1:0] enq_front_data,        

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  input  logic                   deq_front_en,
  output logic                   deq_front_cpl,
  output logic [p_chanwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Deq_back interface
  //----------------------------------------------------------------------

  input  logic                   deq_back_en,
  output logic                   deq_back_cpl,
  output logic [p_chanwidth-1:0] deq_back_data,

  //----------------------------------------------------------------------
  // Update interface
  //----------------------------------------------------------------------

  input  logic                   upd_en,
  output logic                   upd_cpl,
  input  logic [p_ptrwidth-1:0]  upd_tag_in,
  input  logic [p_chanwidth-1:0] upd_data_in,

  //----------------------------------------------------------------------
  // Delete interface
  //----------------------------------------------------------------------

  input  logic                   del_en,
  output logic                   del_cpl,
  input  logic [p_ptrwidth-1:0]  del_tag_in
);

  logic                  wr_data    [p_depth];
  logic [p_bitwidth-1:0] wr_data_in;
  logic [1:0]            shift_en   [p_depth];
  logic [p_bitwidth-1:0] data_out   [p_depth];
  logic                  set_occ    [p_depth];
  logic                  clr_occ    [p_depth];
  logic [p_depth-1:0]    occ;

  //----------------------------------------------------------------------
  // Control unit
  //----------------------------------------------------------------------

  v3a_CtrlUnit #(
    .p_depth     (p_depth),
    .p_ptrwidth  (p_ptrwidth),
    .p_chanwidth (p_chanwidth),
    .p_bitwidth  (p_bitwidth)
  ) ctrl_unit (
    .*
  );

  //----------------------------------------------------------------------
  // Register collection
  //----------------------------------------------------------------------

  v3a_RegCollection #(
    .p_depth     (p_depth),
    .p_ptrwidth  (p_ptrwidth),
    .p_chanwidth (p_chanwidth),
    .p_bitwidth  (p_bitwidth)
  ) reg_collection (
    .*
  );

endmodule

`endif
