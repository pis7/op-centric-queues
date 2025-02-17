//========================================================================
// MultiInReg.v
//========================================================================
// Storage element for the queue with a given ID

`ifndef V1_MULTI_IN_REG_V
`define V1_MULTI_IN_REG_V

module v1_MultiInReg
#(
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Data interface
  //----------------------------------------------------------------------

  input  logic                  wr_data,
  input  logic [p_bitwidth-1:0] wr_data_in,
  input  logic                  shift_en,
  input  logic [p_bitwidth-1:0] shift_data_in,
  output logic [p_bitwidth-1:0] data_out
);

  //----------------------------------------------------------------------
  // Data logic
  //----------------------------------------------------------------------

  always @(posedge clk) begin
    if (rst) begin
      data_out <= p_bitwidth'(0);
    end else begin
      if (wr_data) begin
        data_out <= wr_data_in;
      end else if (shift_en) begin
        data_out <= shift_data_in;
      end
    end
  end

endmodule

`endif
