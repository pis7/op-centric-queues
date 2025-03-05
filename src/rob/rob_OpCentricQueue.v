//========================================================================
// rob_OpCentricQueue.v
//========================================================================
// Toplevel module connected the control unit and the datapath

`ifndef ROB_OP_CENTRIC_QUEUE_V
`define ROB_OP_CENTRIC_QUEUE_V

`include "rob/CtrlUnit.v"
`include "rob/Dpath.v"
`include "common_defs.v"

module rob_OpCentricQueue # (
  parameter p_depth     = `ROB_DEPTH,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_bitwidth  = `ROB_BITWIDTH
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  output logic                  deq_front_cpl,
  output logic [p_bitwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Insert interface
  //----------------------------------------------------------------------

  input  logic                  ins_en,
  output logic                  ins_cpl,
  input  logic [p_ptrwidth-1:0] ins_sn_in,
  input  logic [p_bitwidth-1:0] ins_data_in
);

  logic                  wr_data    [p_depth];
  logic [p_bitwidth-1:0] wr_data_in;
  logic [p_bitwidth-1:0] data_out   [p_depth];
  logic                  clr_occ    [p_depth];
  logic [p_depth-1:0]    occ;

  //----------------------------------------------------------------------
  // Control unit
  //----------------------------------------------------------------------

  rob_CtrlUnit #(
    .p_depth     (p_depth),
    .p_ptrwidth  (p_ptrwidth),
    .p_bitwidth  (p_bitwidth)
  ) ctrl_unit (
    .*
  );

  //----------------------------------------------------------------------
  // Datapath register collection
  //----------------------------------------------------------------------

  rob_Dpath #(
    .p_depth     (p_depth),
    .p_ptrwidth  (p_ptrwidth),
    .p_bitwidth  (p_bitwidth)
  ) dpath (
    .*
  );

endmodule

`endif
