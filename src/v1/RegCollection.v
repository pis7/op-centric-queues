//========================================================================
// RegCollection.v
//========================================================================
// Collection of queue registers which represents the FIFO

`ifndef V1_REG_COLLECTION_V
`define V1_REG_COLLECTION_V

`include "v1/MultiInReg.v"

module v1_RegCollection
#(
  parameter p_depth    = 32,
  parameter p_idwidth  = $clog2(p_depth),
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Data interface
  //----------------------------------------------------------------------

  input  logic                  wr_data    [p_depth],
  input  logic [p_bitwidth-1:0] wr_data_in,
  input  logic                  shift_en   [p_depth],
  output logic [p_bitwidth-1:0] data_out   [p_depth]
);

  //----------------------------------------------------------------------
  // Register generation
  //----------------------------------------------------------------------

  logic [p_bitwidth-1:0] shift_data_in [p_depth+1];
  assign shift_data_in[0] = p_bitwidth'(0);

  genvar i;
  generate
    for(i = 0; i < p_depth; i++) begin : reg_gen

      assign data_out[i] = shift_data_in[i+1];

      v1_MultiInReg #(
        .p_bitwidth (p_bitwidth)
      ) dpath_reg (
        .clk           (clk),
        .rst           (rst),
        .wr_data       (wr_data[i]),
        .wr_data_in    (wr_data_in),
        .shift_en      (shift_en[i]),
        .shift_data_in (shift_data_in[i]),
        .data_out      (shift_data_in[i+1])
      );
    end
  endgenerate

endmodule

`endif
