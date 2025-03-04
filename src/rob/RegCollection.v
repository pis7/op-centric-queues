//========================================================================
// RegCollection.v
//========================================================================
// Collection of queue registers which represents the FIFO

`ifndef V3_REG_COLLECTION_V
`define V3_REG_COLLECTION_V

`include "v3/MultiInReg.v"

module v3_RegCollection
#(
  parameter p_depth     = 32,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_chanwidth = 32,
  parameter p_bitwidth  = p_ptrwidth + p_chanwidth
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Data interface
  //----------------------------------------------------------------------

  input  logic                  wr_data    [p_depth],
  input  logic [p_bitwidth-1:0] wr_data_in,
  input  logic [1:0]            shift_en   [p_depth],
  output logic [p_bitwidth-1:0] data_out   [p_depth]
);

  //----------------------------------------------------------------------
  // Register generation
  //----------------------------------------------------------------------

  logic [p_bitwidth-1:0] internal_conn [p_depth+2];
  assign internal_conn[0]         = p_bitwidth'(0); // dummy shift_fwd_data_in
  assign internal_conn[p_depth+1] = p_bitwidth'(0); // dummy shift_rev_data_in

  genvar i;
  generate
    for(i = 0; i < p_depth; i++) begin : reg_gen

      assign data_out[i] = internal_conn[i+1];

      v3_MultiInReg #(
        .p_ptrwidth  (p_ptrwidth),
        .p_chanwidth (p_chanwidth),
        .p_bitwidth  (p_bitwidth)
      ) dpath_reg (
        .clk               (clk),
        .rst               (rst),
        .wr_data           (wr_data[i]),
        .wr_data_in        (wr_data_in),
        .shift_en          (shift_en[i]),
        .shift_fwd_data_in (internal_conn[i]),
        .shift_rev_data_in (internal_conn[i+2]),
        .data_out          (internal_conn[i+1])
      );
    end
  endgenerate

endmodule

`endif
