`include "cc/registers.svh"

module skid_buffer #(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,

    handshake_if.sink   in,
    handshake_if.source out
);
  logic valid_r;
  payload_t payload_r;

  handshake_if #(.payload_t(payload_t)) pipe_i ();
  handshake_if #(.payload_t(payload_t)) skid_o ();

  pipe #(
      .payload_t(payload_t)
  ) i_pipe (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .in(pipe_i),
      .out(skid_o)
  );

  always_comb begin
    pipe_i.valid = in.ready ? in.valid : valid_r;
    pipe_i.payload = in.ready ? in.payload : payload_r;

    out.valid = skid_o.valid;
    out.payload = skid_o.payload;
    skid_o.ready = out.ready;
  end

  `REG(in.ready, pipe_i.ready)
  `REG_CE_ARSTN(valid_r, in.valid, in.ready, 1'b0)
  `REG_CE(payload_r, in.payload, in.valid && in.ready)

endmodule
