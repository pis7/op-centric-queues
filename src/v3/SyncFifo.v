`ifndef V3_SYNC_FIFO
`define V3_SYNC_FIFO

`include "v3/Mem1r1w.v"

//=========================================================================
// Synchronous FIFO Implementation
//=========================================================================
module v3_SyncFifo #(
    parameter p_num_entries = 8, 
    parameter p_bit_width   = 32
) (
    input   logic                   clk,
    input   logic                   reset,

    input   logic [p_bit_width-1:0] istream_msg,
    input   logic                   istream_val,

    output  logic [p_bit_width-1:0] ostream_msg,
    input   logic                   ostream_rdy
);

localparam ptr_width = $clog2(p_num_entries);

logic [ptr_width-1:0] w_ptr, r_ptr;

v3_Mem1r1w #(
    .p_num_entries(p_num_entries),
    .p_bit_width(p_bit_width)
) mem1r1w (
    .clk(clk),
    .reset(reset),
    .write_en(istream_val),
    .write_addr(w_ptr),
    .write_data(istream_msg),
    .read_en(1'b1),
    .read_addr(r_ptr),
    .read_data(ostream_msg)
);

always_ff @(posedge clk) begin
    if(reset) begin
        w_ptr <= 0;
        r_ptr <= 0;
    end else begin
        if(istream_val) begin
            w_ptr <= w_ptr + 1;
        end
        if(ostream_rdy) begin
            r_ptr <= r_ptr + 1;
        end
    end
end

endmodule

`endif /* BRGTC6_SYNC_FIFO */

