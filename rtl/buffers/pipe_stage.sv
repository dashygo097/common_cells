module pipe_stage #(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic flush_i,

    handshake_if.sink   upstream,
    handshake_if.source downstream
);

  flushable_pipe_stage #(
      .payload_t(payload_t)
  ) i_flushable_pipe_stage (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .upstream(upstream),
      .downstream(downstream)
  );

endmodule
