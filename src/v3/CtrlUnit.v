//========================================================================
// CtrlUnit.v
//========================================================================
// Controller for the queue

`ifndef V3_CTRL_UNIT_V
`define V3_CTRL_UNIT_V

`include "v3/SyncFifo.v"
`include "common_defs.v"

module v3_CtrlUnit
#(
  parameter p_depth     = 32,
  parameter p_ptrwidth  = $clog2(p_depth),
  parameter p_chanwidth = 32,
  parameter p_bitwidth  = p_ptrwidth + p_chanwidth
)(
  input logic clk,
  input logic rst,

  //----------------------------------------------------------------------
  // Enq_back interface
  //----------------------------------------------------------------------

  input  logic                   enq_back_req,
  output logic                   enq_back_cpl,
  output logic [p_ptrwidth-1:0]  enq_back_tag_out,
  input  logic [p_chanwidth-1:0] enq_back_data,

  //----------------------------------------------------------------------
  // Enq_front interface
  //----------------------------------------------------------------------

  input  logic                   enq_front_req,
  output logic                   enq_front_cpl,
  output logic [p_ptrwidth-1:0]  enq_front_tag_out,
  input  logic [p_chanwidth-1:0] enq_front_data,

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  input  logic                   deq_front_req,
  output logic                   deq_front_cpl,
  output logic [p_chanwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Deq_back interface
  //----------------------------------------------------------------------

  input  logic                   deq_back_req,
  output logic                   deq_back_cpl,
  output logic [p_chanwidth-1:0] deq_back_data,

  //----------------------------------------------------------------------
  // Update interface
  //----------------------------------------------------------------------

  input  logic                   upd_req,
  output logic                   upd_cpl,
  input  logic [p_ptrwidth-1:0]  upd_tag_in,
  input  logic [p_chanwidth-1:0] upd_data_in,

  //----------------------------------------------------------------------
  // Delete interface
  //----------------------------------------------------------------------

  input  logic                   del_req,
  output logic                   del_cpl,
  input  logic [p_ptrwidth-1:0]  del_tag_in,

  //----------------------------------------------------------------------
  // Data Interface
  //----------------------------------------------------------------------

  output logic                   wr_data    [p_depth],
  output logic [p_bitwidth-1:0]  wr_data_in,
  output logic [1:0]             shift_en   [p_depth],
  input  logic [p_bitwidth-1:0]  data_out   [p_depth]
);

  logic enq_back_en, enq_front_en, deq_front_en, deq_back_en, upd_en, del_en;
  logic [p_ptrwidth-1:0] tail;
  logic                  empty, full;
  assign                 full = (tail == p_ptrwidth'(0));


  //----------------------------------------------------------------------
  // Tag search FSM
  //----------------------------------------------------------------------

  logic [1:0]            tag_srch_state;
  logic [p_ptrwidth-1:0] tag_srch_idx;
  logic                  tag_srch_found;
  logic [2:0]            srch_op;

  localparam TAG_SRCH_IDLE = 2'b00;
  localparam TAG_SRCH_RUN  = 2'b01;
  localparam TAG_SRCH_DONE = 2'b10;

  localparam SRCH_OP_NOP = 3'b000;
  localparam SRCH_OP_UPD = 3'b001;
  localparam SRCH_OP_DEL = 3'b010;

  always_ff @(posedge clk) begin
    if (rst) begin
      tag_srch_state <= TAG_SRCH_IDLE;
      tag_srch_idx   <= tail;
      tag_srch_found <= 1'b0;
      srch_op        <= SRCH_OP_NOP;
    end else begin
      case (tag_srch_state)
        TAG_SRCH_IDLE: begin
          tag_srch_idx <= tail;
          tag_srch_found <= 1'b0;
          if (upd_en || del_en) begin
            if (upd_en) srch_op <= SRCH_OP_UPD;
            else if (del_en) srch_op <= SRCH_OP_DEL;
            tag_srch_state <= TAG_SRCH_RUN;
          end else srch_op <= SRCH_OP_NOP;
        end
        TAG_SRCH_RUN: begin
          if (data_out[int'(tag_srch_idx)][p_bitwidth-1:p_chanwidth] == (upd_en ? upd_tag_in : del_tag_in)) begin
            tag_srch_found <= 1'b1;
            tag_srch_state <= TAG_SRCH_DONE;
          end else if (tag_srch_idx == p_depth-1) begin
            tag_srch_found <= 1'b0;
            tag_srch_state <= TAG_SRCH_DONE;
          end else tag_srch_idx <= tag_srch_idx + p_ptrwidth'(1);
        end
        TAG_SRCH_DONE: begin
          tag_srch_state <= TAG_SRCH_IDLE;
          srch_op <= SRCH_OP_NOP;
        end
        default: begin
          tag_srch_idx <= tail;
          tag_srch_found <= 1'b0;
          tag_srch_state <= TAG_SRCH_IDLE;
        end
      endcase
    end
  end

  //----------------------------------------------------------------------
  // Operation arbitration logic
  //----------------------------------------------------------------------

  task op_en (
    input logic l_enq_back_en,
    input logic l_enq_front_en,
    input logic l_deq_back_en,
    input logic l_deq_front_en,
    input logic l_upd_en,
    input logic l_del_en
  );
    enq_back_en   = l_enq_back_en;
    enq_front_en  = l_enq_front_en;
    deq_back_en   = l_deq_back_en;
    deq_front_en  = l_deq_front_en;
    upd_en        = l_upd_en;
    del_en        = l_del_en;
  endtask

  always_comb begin
    if (enq_back_req && !full && tag_srch_state == TAG_SRCH_IDLE)        op_en(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    else if (enq_front_req && !full && tag_srch_state == TAG_SRCH_IDLE)  op_en(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    else if (deq_back_req && !empty && tag_srch_state == TAG_SRCH_IDLE)  op_en(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
    else if (deq_front_req && !empty && tag_srch_state == TAG_SRCH_IDLE) op_en(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
    else if (upd_req && !empty && srch_op != SRCH_OP_DEL)                op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    else if (del_req && !empty && srch_op != SRCH_OP_UPD)                op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
    else                                                                 op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
  end

  //----------------------------------------------------------------------
  // Tag FIFO
  //----------------------------------------------------------------------

  logic tag_q_in_put, tag_q_out_take;
  logic [p_ptrwidth-1:0] tag_q_in_data, tag_q_out_data;

  v3_SyncFifo #(
    .p_num_entries (p_depth),
    .p_bit_width   (p_ptrwidth)
  ) tag_fifo (
    .clk         (clk),
    .reset       (rst),
    .istream_msg (tag_q_in_data),
    .istream_val (tag_q_in_put),
    .ostream_msg (tag_q_out_data),
    .ostream_rdy (tag_q_out_take)
  );

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
      end else if (del_cpl) begin
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
    input logic l_deq_front_cpl,
    input logic l_upd_cpl,
    input logic l_del_cpl
  );
    enq_back_cpl  <= l_enq_back_cpl;
    enq_front_cpl <= l_enq_front_cpl;
    deq_back_cpl  <= l_deq_back_cpl;
    deq_front_cpl <= l_deq_front_cpl;
    upd_cpl       <= l_upd_cpl;
    del_cpl       <= l_del_cpl;
  endtask;

  always_ff @(posedge clk) begin
    if (rst) begin
      op_cpl(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
      enq_back_tag_out <= p_ptrwidth'(0);
      enq_front_tag_out <= p_ptrwidth'(0);
      deq_back_data <= p_chanwidth'(0);
      deq_front_data <= p_chanwidth'(0);
      tag_q_in_put  <= 1'b0;
      tag_q_out_take <= 1'b0;
      tag_q_in_data <= p_ptrwidth'(0);
    end else begin
      if (enq_back_en) begin
        op_cpl(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b1;
        tag_q_in_data <= p_ptrwidth'(0);
        enq_back_tag_out <= tag_q_out_data;
      end else if (enq_front_en) begin
        op_cpl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b1;
        tag_q_in_data <= p_ptrwidth'(0);
        enq_front_tag_out <= tag_q_out_data;
      end else if (deq_back_en) begin
        op_cpl(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b1;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= data_out[tail][p_bitwidth-1:p_chanwidth];
        deq_back_data  <= data_out[tail][p_chanwidth-1:0];
      end else if (deq_front_en) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        tag_q_in_put <= 1'b1;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= data_out[p_depth-1][p_bitwidth-1:p_chanwidth];
        deq_front_data <= data_out[p_depth-1][p_chanwidth-1:0];
      end else if (upd_en) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b0, tag_srch_state == TAG_SRCH_DONE, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= p_ptrwidth'(0);
      end else if (del_en) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tag_srch_state == TAG_SRCH_DONE);
        if (tag_srch_state == TAG_SRCH_DONE) tag_q_in_put <= 1'b1;
        tag_q_out_take <= 1'b0;
        if (tag_srch_state == TAG_SRCH_DONE) tag_q_in_data <= del_tag_in;
      end else begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= p_ptrwidth'(0);
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
      wr_data_in = {tag_q_out_data, enq_back_data};
    end else if (enq_front_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (i == p_depth-1);
        shift_en[i]   = (i >= tail-1 ? `SHFT_REV : `SHFT_IDLE);
      end
      wr_data_in = {tag_q_out_data, enq_front_data};
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
    end else if (upd_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (tag_srch_state == TAG_SRCH_DONE && tag_srch_found && i == tag_srch_idx);
        shift_en[i]   = `SHFT_IDLE;
      end
      wr_data_in = upd_data_in;
    end else if (del_en) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = (tag_srch_state == TAG_SRCH_DONE && tag_srch_found && i >= tail && i <= tag_srch_idx ? `SHFT_FWD : `SHFT_IDLE);
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
