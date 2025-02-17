//========================================================================
// CtrlUnit.v
//========================================================================
// Controller for the queue

`ifndef V1_CTRL_UNIT_V
`define V1_CTRL_UNIT_V

module v1_CtrlUnit
#(
  parameter p_depth    = 32,
  parameter p_ptrwidth = $clog2(p_depth),
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Push_back interface
  //----------------------------------------------------------------------

  input  logic                  push_back_en,
  output logic                  push_back_rdy,
  input  logic [p_bitwidth-1:0] push_back_data,

  //----------------------------------------------------------------------
  // Pop_front interface
  //----------------------------------------------------------------------

  input  logic                  pop_front_en,
  output logic                  pop_front_rdy,
  output logic [p_bitwidth-1:0] pop_front_data,

  //----------------------------------------------------------------------
  // Data Interface
  //----------------------------------------------------------------------

  output logic                  wr_data    [p_depth],
  output logic [p_bitwidth-1:0] wr_data_in,
  output logic                  shift_en   [p_depth],
  input  logic [p_bitwidth-1:0] data_out   [p_depth]
);

  logic [p_ptrwidth-1:0] tail;
  logic                  empty;

  //----------------------------------------------------------------------
  // Tail pointer and empty sequential logic
  //----------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      tail <= p_ptrwidth'(p_depth-1);
      empty <= 1'b1;
    end else begin
      if (push_back_en && push_back_rdy) begin
        if (!empty) tail <= tail - p_ptrwidth'(1);
        else empty <= 1'b0;
      end else if (pop_front_en && pop_front_rdy) begin
        if (tail != p_depth-1) tail <= tail + p_ptrwidth'(1);
        else empty <= 1'b1;
      end
    end
  end

  //----------------------------------------------------------------------
  // Data out sequential logic
  //----------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      pop_front_data <= p_bitwidth'(0);
    end else begin
      if (pop_front_en && pop_front_rdy) begin
        pop_front_data <= data_out[p_depth-1];
      end
    end
  end

  //----------------------------------------------------------------------
  // Data signal combinational logic
  //----------------------------------------------------------------------

  assign push_back_rdy = tail != p_ptrwidth'(0);
  assign pop_front_rdy = !empty;

  always_comb begin
    if (push_back_en && push_back_rdy) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (i == tail-(!empty) ? 1'b1 : 1'b0);
        shift_en[i]   = 1'b0;
      end
      wr_data_in = push_back_data;
    end else if (pop_front_en && pop_front_rdy) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = (i >= tail);
      end
      wr_data_in = 1'b0;
    end else begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = 1'b0;
      end
      wr_data_in = 1'b0;
    end
  end

endmodule

`endif
