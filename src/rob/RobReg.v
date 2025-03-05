//========================================================================
// RobReg.v
//========================================================================
// Storage element for the queue with a given ID

`ifndef ROB_REG_V
`define ROB_REG_V

`include "common_defs.v"

module rob_Reg
#(
  parameter p_ptrwidth  = 5,
  parameter p_bitwidth  = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Data interface
  //----------------------------------------------------------------------

  input  logic                  wr_data,
  input  logic [p_bitwidth-1:0] wr_data_in,
  output logic [p_bitwidth-1:0] data_out,
  input  logic                  clr_occ,
  output logic                  occ

);

  //----------------------------------------------------------------------
  // Data logic
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (rst) begin
      data_out <= p_bitwidth'(0);
      occ      <= 1'b0;
    end else begin
      if (wr_data) begin
        data_out <= wr_data_in;
        occ <= 1'b1;
      end else if (clr_occ) occ <= 1'b0;
    end
  end

endmodule

`endif
