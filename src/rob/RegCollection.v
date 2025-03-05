//========================================================================
// RegCollection.v
//========================================================================
// Collection of queue registers which represents the FIFO

`ifndef ROB_REG_COLLECTION_V
`define ROB_REG_COLLECTION_V

`include "rob/RobReg.v"

module rob_RegCollection
#(
  parameter p_depth     = 32,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_bitwidth  = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Data interface
  //----------------------------------------------------------------------

  input  logic                  wr_data    [p_depth],
  input  logic [p_bitwidth-1:0] wr_data_in,
  output logic [p_bitwidth-1:0] data_out   [p_depth],
  input  logic                  clr_occ    [p_depth],
  output logic [p_depth-1:0]    occ
);

  //----------------------------------------------------------------------
  // Register generation
  //----------------------------------------------------------------------

  genvar i;
  generate
    for(i = 0; i < p_depth; i++) begin : reg_gen

      rob_Reg #(
        .p_ptrwidth  (p_ptrwidth),
        .p_bitwidth  (p_bitwidth)
      ) dpath_reg (
        .clk               (clk),
        .rst               (rst),
        .wr_data           (wr_data[i]),
        .wr_data_in        (wr_data_in),
        .data_out          (data_out[i]),
        .clr_occ           (clr_occ[i]),
        .occ               (occ[i])
      );
    end
  endgenerate

endmodule

`endif
