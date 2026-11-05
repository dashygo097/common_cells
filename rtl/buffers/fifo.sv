`include "cc/assertions.svh"

module fifo
  import cc_pkg::*;
#(
    parameter type payload_t = logic,
    parameter int unsigned DEPTH = 4
) (
    input logic clk_i,
    input logic rst_n_i,

    handshake_if.sink   in,
    handshake_if.source out,

    output logic empty_o,
    output logic full_o
);
  localparam int unsigned PtrWidth = index_width(DEPTH);
  localparam int unsigned CntWidth = index_width(DEPTH + 1);

  payload_t storage[DEPTH];

  logic [CntWidth - 1:0] counter_r;
  logic [PtrWidth - 1:0] w_ptr_r;
  logic [PtrWidth - 1:0] r_ptr_r;

  logic push;
  logic pop;

  always_comb begin
    empty_o = (counter_r == '0);
    full_o = (counter_r == CntWidth'(DEPTH));

    out.valid = !empty_o;
    out.payload = storage[r_ptr_r];

    pop = out.valid && out.ready;

    in.ready = !full_o || pop;
    push = in.valid && in.ready;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      counter_r <= '0;
      w_ptr_r   <= '0;
      r_ptr_r   <= '0;
    end else begin
      if (push) begin
        storage[w_ptr_r] <= in.payload;

        if (w_ptr_r == PtrWidth'(DEPTH - 1)) begin
          w_ptr_r <= '0;
        end else begin
          w_ptr_r <= w_ptr_r + 1'b1;
        end
      end

      if (pop) begin
        if (r_ptr_r == PtrWidth'(DEPTH - 1)) begin
          r_ptr_r <= '0;
        end else begin
          r_ptr_r <= r_ptr_r + 1'b1;
        end
      end

      case ({
        push, pop
      })
        2'b10:   counter_r <= counter_r + 1'b1;
        2'b01:   counter_r <= counter_r - 1'b1;
        default: counter_r <= counter_r;
      endcase
    end
  end

  `CC_ASSERT_INIT(DepthPositive, DEPTH > 0)
  `CC_ASSERT_INIT(InputPayloadWidth, $bits(in.payload) == $bits(payload_t))
  `CC_ASSERT_INIT(OutputPayloadWidth, $bits(out.payload) == $bits(payload_t))

  `CC_ASSERT(CountInRange, counter_r <= CntWidth'(DEPTH))
  `CC_ASSERT(WritePointerInRange, {1'b0, w_ptr_r} < (PtrWidth + 1)'(DEPTH))
  `CC_ASSERT(ReadPointerInRange, {1'b0, r_ptr_r} < (PtrWidth + 1)'(DEPTH))
  `CC_ASSERT(OutputStable, out.valid && !out.ready |=> out.valid && $stable(out.payload))

endmodule
