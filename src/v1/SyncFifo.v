//========================================================================
// SyncFifo.v
//========================================================================
// Generic synchronous FIFO using a pointer-based approach

`ifndef SYNC_FIFO_V
`define SYNC_FIFO_V

module V1_SyncFifo
#(
  parameter p_depth    = 32,
  parameter p_bitwidth = 32
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  rd_en,
  input  logic                  wr_en,
  input  logic [p_bitwidth-1:0] wr_data,
  output logic [p_bitwidth-1:0] rd_data,
  output logic                  empty,
  output logic                  full
);

  //----------------------------------------------------------------------
  // Pointers and array declarations
  //----------------------------------------------------------------------
  logic [$clog2(p_depth)-1:0] rptr, wptr;
  logic [p_bitwidth-1:0] arr [p_depth-1:0];

  //----------------------------------------------------------------------
  // Write pointer logic
  //----------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) wptr <= 0;
    else begin
      if (wr_en & !full) wptr <= wptr + 1;
      if (rd_en) rptr <= rptr + 1;
    end
end

endmodule

`endif
