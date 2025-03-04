//========================================================================
// CtrlUnit.v
//========================================================================
// Controller for the queue

`ifndef V2_CTRL_UNIT_V
`define V2_CTRL_UNIT_V

`include "common_defs.v"

module v2_CtrlUnit
#(
  parameter p_depth    = 32,
  parameter p_ptrwidth = $clog2(p_depth),
  parameter p_bitwidth = 32
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Enq_back interface
  //----------------------------------------------------------------------

  input  logic                  enq_back_req,
  output logic                  enq_back_cpl,
  input  logic [p_bitwidth-1:0] enq_back_data,

  //----------------------------------------------------------------------
  // Enq_front interface
  //----------------------------------------------------------------------

  input  logic                  enq_front_req,
  output logic                  enq_front_cpl,
  input  logic [p_bitwidth-1:0] enq_front_data,        

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  input  logic                  deq_front_req,
  output logic                  deq_front_cpl,
  output logic [p_bitwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Deq_back interface
  //----------------------------------------------------------------------

  input  logic                  deq_back_req,
  output logic                  deq_back_cpl,
  output logic [p_bitwidth-1:0] deq_back_data,

  //----------------------------------------------------------------------
  // Data Interface
  //----------------------------------------------------------------------

  output logic                  wr_data    [p_depth],
  output logic [p_bitwidth-1:0] wr_data_in,
  output logic [1:0]            shift_en   [p_depth],
  input  logic [p_bitwidth-1:0] data_out   [p_depth]
);

  logic [p_ptrwidth-1:0] tail;
  logic                  empty;
  logic                  full;
  assign                 full = (tail == p_ptrwidth'(0));

  //----------------------------------------------------------------------
  // Operation arbitration logic
  //----------------------------------------------------------------------

  logic enq_back_en, enq_front_en, deq_front_en, deq_back_en;

  task automatic op_en (
    input logic l_enq_back_en,
    input logic l_enq_front_en,
    input logic l_deq_back_en,
    input logic l_deq_front_en
  );
    enq_back_en   = l_enq_back_en;
    enq_front_en  = l_enq_front_en;
    deq_back_en   = l_deq_back_en;
    deq_front_en  = l_deq_front_en;
  endtask

  always_comb begin
    if (enq_back_req && !full)        op_en(1'b1, 1'b0, 1'b0, 1'b0);
    else if (enq_front_req && !full)  op_en(1'b0, 1'b1, 1'b0, 1'b0);
    else if (deq_back_req && !empty)  op_en(1'b0, 1'b0, 1'b1, 1'b0);
    else if (deq_front_req && !empty) op_en(1'b0, 1'b0, 1'b0, 1'b1);
    else                              op_en(1'b0, 1'b0, 1'b0, 1'b0);
  end

  //----------------------------------------------------------------------
  // Tail pointer and empty sequential logic
  //----------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      tail <= p_ptrwidth'(p_depth-1);
      empty <= 1'b1;
    end else begin
      if (enq_back_en) begin
        if (!empty) tail <= tail - p_ptrwidth'(1);
        else empty <= 1'b0;
      end else if (deq_front_en) begin
        if (tail != p_depth-1) tail <= tail + p_ptrwidth'(1);
        else empty <= 1'b1;
      end else if (enq_front_en) begin
        if (!empty) tail <= tail - p_ptrwidth'(1);
        else empty <= 1'b0;
      end else if (deq_back_en) begin
        if (tail != p_depth-1) tail <= tail + p_ptrwidth'(1);
        else empty <= 1'b1;
      end
    end
  end

  //----------------------------------------------------------------------
  // Data out and completion sequential logic
  //----------------------------------------------------------------------

  task op_cpl (
    input logic l_enq_back_cpl,
    input logic l_enq_front_cpl,
    input logic l_deq_back_cpl,
    input logic l_deq_front_cpl
  );
    enq_back_cpl  <= l_enq_back_cpl;
    enq_front_cpl <= l_enq_front_cpl;
    deq_back_cpl  <= l_deq_back_cpl;
    deq_front_cpl <= l_deq_front_cpl;
  endtask;

  always_ff @(posedge clk) begin
    if (rst) begin
      op_cpl(1'b0, 1'b0, 1'b0, 1'b0);
      deq_front_data <= p_bitwidth'(0);
    end else begin
      if (enq_back_en) begin
        op_cpl(1'b1, 1'b0, 1'b0, 1'b0);
      end else if (enq_front_en) begin
        op_cpl(1'b0, 1'b1, 1'b0, 1'b0);
      end else if (deq_back_en) begin
        op_cpl(1'b0, 1'b0, 1'b1, 1'b0);
        deq_back_data  <= data_out[tail];
      end else if (deq_front_en) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b1);
        deq_front_data <= data_out[p_depth-1];
      end else begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b0);
      end
    end
  end

  //----------------------------------------------------------------------
  // Data signal combinational logic
  //----------------------------------------------------------------------

  always_comb begin
    if (rst) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = `SHFT_IDLE;
      end
      wr_data_in = p_bitwidth'(0);
    end else if (enq_back_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (i == tail-(!empty));
        shift_en[i]   = `SHFT_IDLE;
      end
      wr_data_in = enq_back_data;
    end else if (enq_front_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (i == p_depth-1);
        shift_en[i]   = (i >= tail-1 ? `SHFT_REV : `SHFT_IDLE);
      end
      wr_data_in = enq_front_data;
    end else if (deq_back_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = 1'b0;
      end
      wr_data_in = p_bitwidth'(0);
    end else if (deq_front_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = (i >= tail ? `SHFT_FWD : `SHFT_IDLE);
      end
      wr_data_in = p_bitwidth'(0);
    end else begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = `SHFT_IDLE;
      end
      wr_data_in = p_bitwidth'(0);
    end
  end

endmodule

`endif
