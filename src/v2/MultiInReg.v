//========================================================================
// MultiInReg.v
//========================================================================
// Storage element for the queue with a given ID

`ifndef V2_MULTI_IN_REG_V
`define V2_MULTI_IN_REG_V

`include "common_defs.v"

module v2_MultiInReg
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
  input  logic [1:0]            shift_en,
  input  logic [p_bitwidth-1:0] shift_fwd_data_in,
  input  logic [p_bitwidth-1:0] shift_rev_data_in,
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
      end else begin
        case (shift_en)
          `SHFT_IDLE: data_out <= data_out;
          `SHFT_FWD:  data_out <= shift_fwd_data_in;
          `SHFT_REV:  data_out <= shift_rev_data_in;
          default:    data_out <= data_out;
        endcase
      end
    end
  end

endmodule

`endif
