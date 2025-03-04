//========================================================================
// CtrlUnit.v
//========================================================================
// Controller for the queue

`ifndef V3A_CTRL_UNIT_V
`define V3A_CTRL_UNIT_V

`include "v3a/SyncFifo.v"
`include "common_defs.v"

module v3a_CtrlUnit
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

  input  logic                   enq_back_en,
  output logic                   enq_back_cpl,
  output logic [p_ptrwidth-1:0]  enq_back_tag_out,
  input  logic [p_chanwidth-1:0] enq_back_data,

  //----------------------------------------------------------------------
  // Enq_front interface
  //----------------------------------------------------------------------

  input  logic                   enq_front_en,
  output logic                   enq_front_cpl,
  output logic [p_ptrwidth-1:0]  enq_front_tag_out,
  input  logic [p_chanwidth-1:0] enq_front_data,

  //----------------------------------------------------------------------
  // Deq_front interface
  //----------------------------------------------------------------------

  input  logic                   deq_front_en,
  output logic                   deq_front_cpl,
  output logic [p_chanwidth-1:0] deq_front_data,

  //----------------------------------------------------------------------
  // Deq_back interface
  //----------------------------------------------------------------------

  input  logic                   deq_back_en,
  output logic                   deq_back_cpl,
  output logic [p_chanwidth-1:0] deq_back_data,

  //----------------------------------------------------------------------
  // Update interface
  //----------------------------------------------------------------------

  input  logic                   upd_en,
  output logic                   upd_cpl,
  input  logic [p_ptrwidth-1:0]  upd_tag_in,
  input  logic [p_chanwidth-1:0] upd_data_in,

  //----------------------------------------------------------------------
  // Delete interface
  //----------------------------------------------------------------------

  input  logic                   del_en,
  output logic                   del_cpl,
  input  logic [p_ptrwidth-1:0]  del_tag_in,

  //----------------------------------------------------------------------
  // Data Interface
  //----------------------------------------------------------------------

  output logic                   wr_data    [p_depth],
  output logic [p_bitwidth-1:0]  wr_data_in,
  output logic [1:0]             shift_en   [p_depth],
  input  logic [p_bitwidth-1:0]  data_out   [p_depth],
  output logic                   set_occ    [p_depth],
  output logic                   clr_occ    [p_depth],
  input  logic [p_depth-1:0]     occ
);

  logic enq_back_will_fire, enq_front_will_fire, deq_front_will_fire, deq_back_will_fire, upd_will_fire, del_will_fire;
  logic [p_ptrwidth-1:0] back_ptr, front_ptr;
  logic                  empty, full;

  //----------------------------------------------------------------------
  // Empty and full logic
  //----------------------------------------------------------------------

  assign empty = ~|occ; // empty if all registers are unoccupied
  assign full  = &occ;  // full if all registers are occupied

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
      tag_srch_idx   <= back_ptr;
      tag_srch_found <= 1'b0;
      srch_op        <= SRCH_OP_NOP;
    end else begin
      case (tag_srch_state)
        TAG_SRCH_IDLE: begin
          tag_srch_idx <= back_ptr;
          tag_srch_found <= 1'b0;
          if (upd_will_fire || del_will_fire) begin
            if (upd_will_fire) srch_op <= SRCH_OP_UPD;
            else if (del_will_fire) srch_op <= SRCH_OP_DEL;
            tag_srch_state <= TAG_SRCH_RUN;
          end else srch_op <= SRCH_OP_NOP;
        end
        TAG_SRCH_RUN: begin
          if (data_out[int'(tag_srch_idx)][p_bitwidth-1:p_chanwidth] == (upd_will_fire ? upd_tag_in : del_tag_in)) begin
            tag_srch_found <= 1'b1;
            tag_srch_state <= TAG_SRCH_DONE;
          end else if (tag_srch_idx == front_ptr) begin
            tag_srch_found <= 1'b0;
            tag_srch_state <= TAG_SRCH_DONE;
          end else tag_srch_idx <= tag_srch_idx - p_ptrwidth'(1);
        end
        TAG_SRCH_DONE: begin
          tag_srch_state <= TAG_SRCH_IDLE;
          srch_op <= SRCH_OP_NOP;
        end
        default: begin
          tag_srch_idx <= back_ptr;
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
    input logic l_enq_back_will_fire,
    input logic l_enq_front_will_fire,
    input logic l_deq_back_will_fire,
    input logic l_deq_front_will_fire,
    input logic l_upd_will_fire,
    input logic l_del_will_fire
  );
    enq_back_will_fire   = l_enq_back_will_fire;
    enq_front_will_fire  = l_enq_front_will_fire;
    deq_back_will_fire   = l_deq_back_will_fire;
    deq_front_will_fire  = l_deq_front_will_fire;
    upd_will_fire        = l_upd_will_fire;
    del_will_fire        = l_del_will_fire;
  endtask

  always_comb begin
    if (enq_back_en && !full && tag_srch_state == TAG_SRCH_IDLE)        op_en(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    else if (enq_front_en && !full && tag_srch_state == TAG_SRCH_IDLE)  op_en(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    else if (deq_back_en && !empty && tag_srch_state == TAG_SRCH_IDLE)  op_en(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
    else if (deq_front_en && !empty && tag_srch_state == TAG_SRCH_IDLE) op_en(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
    else if (upd_en && !empty && srch_op != SRCH_OP_DEL)                op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    else if (del_en && !empty && srch_op != SRCH_OP_UPD)                op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
    else                                                                op_en(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
  end

  //----------------------------------------------------------------------
  // Tag FIFO
  //----------------------------------------------------------------------

  logic tag_q_in_put, tag_q_out_take;
  logic [p_ptrwidth-1:0] tag_q_in_data, tag_q_out_data;

  v3a_SyncFifo #(
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
  // Back and front pointers and empty sequential logic
  //----------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (rst) begin
      back_ptr <= {p_ptrwidth{1'b0}};
      front_ptr <= {p_ptrwidth{1'b0}};
    end else begin
      if (enq_back_will_fire) begin
        if (!empty) back_ptr <= back_ptr + p_ptrwidth'(1);
      end else if (deq_front_will_fire) begin
        if (!empty && front_ptr != back_ptr) front_ptr <= front_ptr + p_ptrwidth'(1);
      end else if (enq_front_will_fire) begin
        if (!empty) front_ptr <= front_ptr - p_ptrwidth'(1);
      end else if (deq_back_will_fire) begin
        if (!empty && front_ptr != back_ptr) back_ptr <= back_ptr - p_ptrwidth'(1);
      end else if (del_cpl) begin
        if (!empty && tag_srch_idx <= back_ptr) back_ptr <= back_ptr - p_ptrwidth'(1);
        else if (!empty && tag_srch_idx >= front_ptr) front_ptr <= front_ptr + p_ptrwidth'(1);
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
      if (enq_back_will_fire) begin
        op_cpl(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b1;
        tag_q_in_data <= p_ptrwidth'(0);
        enq_back_tag_out <= tag_q_out_data;
      end else if (enq_front_will_fire) begin
        op_cpl(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b1;
        tag_q_in_data <= p_ptrwidth'(0);
        enq_front_tag_out <= tag_q_out_data;
      end else if (deq_back_will_fire) begin
        op_cpl(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        tag_q_in_put  <= 1'b1;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= data_out[back_ptr][p_bitwidth-1:p_chanwidth];
        deq_back_data  <= data_out[back_ptr][p_chanwidth-1:0];
      end else if (deq_front_will_fire) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        tag_q_in_put <= 1'b1;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= data_out[front_ptr][p_bitwidth-1:p_chanwidth];
        deq_front_data <= data_out[front_ptr][p_chanwidth-1:0];
      end else if (upd_will_fire) begin
        op_cpl(1'b0, 1'b0, 1'b0, 1'b0, tag_srch_state == TAG_SRCH_DONE, 1'b0);
        tag_q_in_put  <= 1'b0;
        tag_q_out_take <= 1'b0;
        tag_q_in_data <= p_ptrwidth'(0);
      end else if (del_will_fire) begin
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
        set_occ[i]    = 1'b0;
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = p_bitwidth'(0);
    end else if (enq_back_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (!empty && (back_ptr == p_depth-1 ? i == 0 : i == back_ptr+1) || empty && i == back_ptr);
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = (!empty && (back_ptr == p_depth-1 ? i == 0 : i == back_ptr+1) || empty && i == back_ptr);
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = {tag_q_out_data, enq_back_data};
    end else if (enq_front_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (!empty && (front_ptr == 0 ? i == p_depth-1 : i == front_ptr-1) || empty && i == front_ptr);
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = (!empty && (front_ptr == 0 ? i == p_depth-1 : i == front_ptr-1) || empty && i == front_ptr);
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = {tag_q_out_data, enq_front_data};
    end else if (deq_back_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = 1'b0;
        clr_occ[i]    = (!empty && i == back_ptr);
      end
      wr_data_in = p_bitwidth'(0);
    end else if (deq_front_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = 1'b0;
        clr_occ[i]    = (!empty && i == front_ptr);
      end
      wr_data_in = p_bitwidth'(0);
    end else if (upd_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = (tag_srch_state == TAG_SRCH_DONE && tag_srch_found && i == tag_srch_idx);
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = 1'b0;
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = upd_data_in;
    end else if (del_will_fire) begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = (tag_srch_state == TAG_SRCH_DONE && tag_srch_found ? 
          (front_ptr > back_ptr ? 
            (tag_srch_idx < back_ptr ? 
              (i >= tag_srch_idx ? 
                `SHFT_REV :
                `SHFT_IDLE
              ) : 
              (tag_srch_idx > front_ptr ? 
                (i >= front_ptr && i <= tag_srch_idx ? 
                  `SHFT_FWD : 
                  `SHFT_IDLE
                ) :
                `SHFT_IDLE)
            ) : 
            (tag_srch_idx < back_ptr ? 
              (i >= tag_srch_idx ? 
                `SHFT_REV :
                `SHFT_IDLE
              ) :
              `SHFT_IDLE
            )) :
          `SHFT_IDLE);
        set_occ[i]    = 1'b0;
        clr_occ[i]    = (tag_srch_state == TAG_SRCH_DONE && tag_srch_found ? 
          (front_ptr > back_ptr ?
            (tag_srch_idx <= back_ptr ? 
              (i == back_ptr) : 
              (tag_srch_idx >= front_ptr ? 
                (i == front_ptr) : 
                1'b0)
            ) : 
            (i == back_ptr)) :
            1'b0
        );
      end
      wr_data_in = p_bitwidth'(0);
    end else begin
      for (int i = 0; i < p_depth; i++) begin
        wr_data[i]    = 1'b0;
        shift_en[i]   = `SHFT_IDLE;
        set_occ[i]    = 1'b0;
        clr_occ[i]    = 1'b0;
      end
      wr_data_in = p_bitwidth'(0);
    end
  end

endmodule

`endif
