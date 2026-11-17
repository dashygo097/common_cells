module tb_flushable_pipe #(
    parameter int unsigned RANDOM_CYCLES = 1000
) ();

  typedef struct packed {
    logic [31:0] data;
    logic last;
  } payload_t;

  logic clk_i;
  logic rst_n_i;
  logic flush_i;
  handshake_if #(.payload_t(payload_t)) in ();
  handshake_if #(.payload_t(payload_t)) out ();
  logic full_model;
  payload_t payload_model;
  df_verify_pkg::ordered_scoreboard #(payload_t) scoreboard;

  flushable_pipe #(
      .payload_t(payload_t)
  ) u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .in(in),
      .out(out)
  );

  always #5ns clk_i = ~clk_i;

  task automatic reset_dut();
    @(negedge clk_i);
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    flush_i = 1'b0;
    rst_n_i = 1'b0;
    full_model = 1'b0;
    payload_model = '0;
    scoreboard.clear();
    #1ns;
    df_verify_pkg::check(!out.valid, "Reset must clear out validity");
    df_verify_pkg::wait_cycles(clk_i, 2);
    @(negedge clk_i);
    rst_n_i = 1'b1;
  endtask

  task automatic cycle(input logic valid, input payload_t payload, input logic ready,
                       input logic flush);
    logic accept;
    @(negedge clk_i);
    in.valid = valid;
    in.payload = payload;
    out.ready = ready;
    flush_i = flush;
    #1ns;
    df_verify_pkg::value_check#(logic)::equal(in.ready, !flush && (!full_model || ready),
                                              "Incorrect in ready");
    df_verify_pkg::value_check#(logic)::equal(out.valid, full_model && !flush,
                                              "Incorrect out valid");
    if (out.valid) begin
      df_verify_pkg::value_check#(payload_t)::equal(out.payload, payload_model,
                                                    "Payload ordering or stability failure");
    end
    accept = in.valid && in.ready;
    @(posedge clk_i);
    if (flush) begin
      scoreboard.clear();
      full_model = 1'b0;
    end else begin
      if (out.valid && out.ready) begin
        scoreboard.check_actual(out.payload);
      end
      if (accept) begin
        scoreboard.push_expected(payload);
      end
      if (!full_model || ready) begin
        full_model = valid;
      end
    end
    if (accept) begin
      payload_model = payload;
    end
    #1ns;
    df_verify_pkg::value_check#(logic)::equal(out.valid, full_model && !flush,
                                              "Incorrect registered validity");
    if (out.valid) begin
      df_verify_pkg::value_check#(payload_t)::equal(out.payload, payload_model,
                                                    "Incorrect registered payload");
    end
  endtask

  task automatic test_reset_empty();
    // Reset an empty stage and verify idle operation.
    reset_dut();
    cycle(1'b0, '0, 1'b1, 1'b0);
  endtask

  task automatic test_reset_occupied();
    // Reset an occupied stage and discard the pending payload.
    cycle(1'b1, payload_t'(33'h1_12345678), 1'b0, 1'b0);
    reset_dut();
    cycle(1'b0, '0, 1'b1, 1'b0);
  endtask

  task automatic test_throughput();
    // Sustain one accepted transfer per cycle with a ready consumer.
    reset_dut();
    for (int unsigned i = 0; i < 100; i++) begin
      cycle(1'b1, payload_t'(i), 1'b1, 1'b0);
    end
  endtask

  task automatic test_backpressure();
    // Hold the output stable under backpressure, then replace it on a pop.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_87654321), 1'b0, 1'b0);
    repeat (20) cycle(1'b1, payload_t'($urandom), 1'b0, 1'b0);
    cycle(1'b1, payload_t'(33'h0_12345678), 1'b1, 1'b0);
  endtask

  task automatic test_flush();
    // Flush an occupied stage, block both handshakes, then accept new data.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_12345678), 1'b0, 1'b0);
    cycle(1'b1, payload_t'(33'h1_87654321), 1'b1, 1'b1);
    cycle(1'b0, '0, 1'b1, 1'b0);
    cycle(1'b1, payload_t'(33'h1_aabbccdd), 1'b1, 1'b0);
  endtask

  task automatic test_random_traffic();
    // Randomize traffic, stalls, and flushes, then drain all pending data.
    reset_dut();
    df_verify_pkg::check(RANDOM_CYCLES > 0, "RANDOM_CYCLES must be positive");
    repeat (RANDOM_CYCLES) begin
      cycle(1'($urandom), payload_t'({$urandom, $urandom}), 1'($urandom), $urandom_range(0, 15
            ) == 0);
    end
    cycle(1'b0, '0, 1'b1, 1'b0);
    cycle(1'b0, '0, 1'b1, 1'b0);
    df_verify_pkg::check(!out.valid, "Pipeline did not drain");
  endtask

  task automatic check_results();
    scoreboard.check_empty();
  endtask

  initial begin
    clk_i = 1'b0;
    scoreboard = new("flushable_pipe");
    rst_n_i = 1'b0;
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    flush_i = 1'b0;
    full_model = 1'b0;
    payload_model = '0;

    test_reset_empty();
    test_reset_occupied();
    test_throughput();
    test_backpressure();
    test_flush();
    test_random_traffic();
    check_results();
    df_verify_pkg::finish_test();
  end
endmodule
