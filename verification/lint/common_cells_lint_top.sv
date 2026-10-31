module common_cells_lint_top #(
    parameter int unsigned DATA_WIDTH,
    parameter int unsigned DEPTH
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic async_clk_i,
    input logic async_rst_n_i,
    input logic flush_i,
    input logic [2:0] valid_i,
    output logic [2:0] ready_o,
    input logic [2:0][DATA_WIDTH-1:0] data_i,
    output logic [2:0] valid_o,
    input logic [2:0] ready_i,
    output logic [2:0][DATA_WIDTH-1:0] data_o,
    output logic [1:0] empty_o,
    output logic [1:0] full_o
);
  typedef logic [DATA_WIDTH-1:0] payload_t;

  handshake_if #(.payload_t(payload_t)) upstreams[3] ();
  handshake_if #(.payload_t(payload_t)) downstreams[3] ();

  for (genvar i = 0; i < 3; i++) begin : gen_channels
    assign upstreams[i].valid = valid_i[i];
    assign upstreams[i].payload = data_i[i];
    assign ready_o[i] = upstreams[i].ready;
    assign valid_o[i] = downstreams[i].valid;
    assign data_o[i] = downstreams[i].payload;
    assign downstreams[i].ready = ready_i[i];
  end

  sync_fifo #(.payload_t(payload_t), .DEPTH(DEPTH)) u_sync_fifo (
      .clk_i(clk_i), .rst_n_i(rst_n_i),
      .in(upstreams[0]), .out(downstreams[0]),
      .empty_o(empty_o[0]), .full_o(full_o[0])
  );

  async_fifo #(.payload_t(payload_t), .DEPTH(DEPTH)) u_async_fifo (
      .wclk_i(clk_i), .wrst_n_i(rst_n_i),
      .rclk_i(async_clk_i), .rrst_n_i(async_rst_n_i),
      .in(upstreams[1]), .out(downstreams[1]),
      .empty_o(empty_o[1]), .full_o(full_o[1])
  );

  pipe_stage #(.payload_t(payload_t)) u_pipe_stage (
      .clk_i(clk_i), .rst_n_i(rst_n_i), .flush_i(flush_i),
      .upstream(upstreams[2]), .downstream(downstreams[2])
  );
endmodule
