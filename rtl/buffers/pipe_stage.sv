module pipe_stage #(
    parameter type payload_t = logic
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic flush_i,

    handshake_if.sink   upstream,
    handshake_if.source downstream
);

  flushable_pipe_stage#(
      .payload_t(payload_t)
  ) (
      .clk_i(clk_i), .rst_n_i(rst_n_i)
  );

endmodule
