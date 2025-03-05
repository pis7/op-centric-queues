//========================================================================
// CtrlUnit.v
//========================================================================
// Controller for the queue

`ifndef ROB_CTRL_UNIT_V
`define ROB_CTRL_UNIT_V

`include "common_defs.v"

module rob_CtrlUnit
#(
  parameter p_depth     = 32,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_bitwidth  = 32
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
  input  logic [p_bitwidth-1:0] ins_data_in,

  //----------------------------------------------------------------------
  // Data Interface
  //----------------------------------------------------------------------

  output logic                   wr_data    [p_depth],
  output logic [p_bitwidth-1:0]  wr_data_in,
  input  logic [p_bitwidth-1:0]  data_out   [p_depth],
  output logic                   clr_occ    [p_depth],
  input  logic [p_depth-1:0]     occ
);

  logic [p_ptrwidth-1:0] deq_ptr;
  logic ins_and_deq;
  assign ins_and_deq = deq_ptr == ins_sn_in && ins_en;

  //----------------------------------------------------------------------
  // Dequeue pointer update sequential logic
  //----------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      deq_ptr <= {p_ptrwidth{1'b0}};
    end else if (occ[deq_ptr] || ins_and_deq) deq_ptr <= deq_ptr + p_ptrwidth'(1);
  end

  //----------------------------------------------------------------------
  // Data out combinational logic
  //----------------------------------------------------------------------

  always_comb begin
    if (rst) begin
      deq_front_data = p_bitwidth'(0);
    end else begin
      if (occ[deq_ptr])     deq_front_data = data_out[deq_ptr];
      else if (ins_and_deq) deq_front_data = ins_data_in;
      else                  deq_front_data = p_bitwidth'(0);
    end
  end

  //----------------------------------------------------------------------
  // Operation completion combinational logic
  //----------------------------------------------------------------------

  always_comb begin
    if (rst) begin
      ins_cpl = 1'b0;
      deq_front_cpl = 1'b0;
    end else begin
      ins_cpl = ins_en;
      deq_front_cpl = (occ[deq_ptr] || ins_and_deq);
    end
  end

  //----------------------------------------------------------------------
  // Register control combinational logic
  //----------------------------------------------------------------------

  always_comb begin
    if (rst) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = p_bitwidth'(0);
    end else begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (i == ins_sn_in && i != deq_ptr && ins_en);
        clr_occ[i]    = (i == deq_ptr);
      end
      wr_data_in = ins_data_in;
    end
  end

endmodule

`endif
