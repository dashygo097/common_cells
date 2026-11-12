module pipe #(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,

    handshake_if.sink   in,
    handshake_if.source out
);

  flushable_pipe #(
      .payload_t(payload_t)
  ) i_flushable_pipe (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .in(in),
      .out(out)
  );

endmodule
