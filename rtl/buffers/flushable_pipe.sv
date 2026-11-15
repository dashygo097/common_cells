`include "cc/assertions.svh"
`include "cc/registers.svh"

module flushable_pipe #(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic flush_i,

    handshake_if.sink   in,
    handshake_if.source out
);
  logic allow_in;
  logic valid_r;
  payload_t payload_r;

  always_comb begin
    allow_in = !valid_r || out.ready;
    in.ready = !flush_i && allow_in;

    out.valid = valid_r && !flush_i;
    out.payload = payload_r;
  end

  `REG_CE_CLR_ARSTN(valid_r, in.valid, in.ready, flush_i, 1'b0)
  `REG_CE_CLR(payload_r, in.payload, in.ready && in.valid, flush_i, '0)

  `ASSERT_INIT(InputPayloadWidth, $bits(in.payload) == $bits(payload_t))
  `ASSERT_INIT(OutputPayloadWidth, $bits(out.payload) == $bits(payload_t))
  `ASSERT(OutputStableUnlessFlushed, out.valid && !out.ready |=> flush_i || (out.valid && $stable
                                     (out.payload)))

endmodule
