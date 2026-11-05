`include "cc/assertions.svh"

module flushable_pipe_stage
  import cc_pkg::*;
#(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic flush_i,

    handshake_if.sink   upstream,
    handshake_if.source downstream
);
  logic allow_in;
  logic valid_r;
  payload_t payload_r;

  always_comb begin
    allow_in = !valid_r || downstream.ready;
    upstream.ready = !flush_i && allow_in;

    downstream.valid = valid_r && !flush_i;
    downstream.payload = payload_r;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      valid_r   <= 1'b0;
      payload_r <= '0;
    end else if (flush_i) begin
      valid_r   <= 1'b0;
      payload_r <= '0;
    end else begin
      valid_r <= upstream.ready ? upstream.valid : 1'b1;

      if (upstream.ready && upstream.valid) begin
        payload_r <= upstream.payload;
      end
    end
  end

  `CC_ASSERT_INIT(InputPayloadWidth, $bits(upstream.payload) == $bits(payload_t))
  `CC_ASSERT_INIT(OutputPayloadWidth, $bits(downstream.payload) == $bits(payload_t))
  `CC_ASSERT(OutputStableUnlessFlushed,
             downstream.valid && !downstream.ready |=> flush_i || (downstream.valid && $stable
             (downstream.payload)))

endmodule
