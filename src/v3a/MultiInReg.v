//========================================================================
// MultiInReg.v
//========================================================================
// Storage element for the queue with a given ID

`ifndef V3A_MULTI_IN_REG_V
`define V3A_MULTI_IN_REG_V

`include "common_defs.v"

module v3a_MultiInReg
#(
  parameter p_ptrwidth  = 5,
  parameter p_chanwidth = 32,
  parameter p_bitwidth  = p_ptrwidth + p_chanwidth
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
  output logic [p_bitwidth-1:0] data_out,
  input  logic                  set_occ,
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
      if (set_occ)      occ <= 1'b1;
      else if (clr_occ) occ <= 1'b0;
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
