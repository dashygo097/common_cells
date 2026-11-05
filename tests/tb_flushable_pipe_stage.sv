module tb_flushable_pipe_stage
  import df_verify_pkg::*;
#(
    parameter int unsigned RANDOM_CYCLES = 1000
) ();

  typedef struct packed {
    logic [31:0] data;
    logic last;
  } payload_t;

  logic clk_i;
  logic rst_n_i;
  logic flush_i;
  handshake_if #(.payload_t(payload_t)) upstream ();
  handshake_if #(.payload_t(payload_t)) downstream ();
  logic full_model;
  payload_t payload_model;
  ordered_scoreboard #(payload_t) scoreboard;

  flushable_pipe_stage #(
      .payload_t(payload_t)
  ) u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .upstream(upstream),
      .downstream(downstream)
  );

  always #5ns clk_i = ~clk_i;

  task automatic reset_dut();
    @(negedge clk_i);
    upstream.valid = 1'b0;
    upstream.payload = '0;
    downstream.ready = 1'b0;
    flush_i = 1'b0;
    rst_n_i = 1'b0;
    full_model = 1'b0;
    payload_model = '0;
    scoreboard.clear();
    #1ns;
    check(!downstream.valid, "Reset must clear downstream validity");
    wait_cycles(clk_i, 2);
    @(negedge clk_i);
    rst_n_i = 1'b1;
  endtask

  task automatic cycle(input logic valid, input payload_t payload, input logic ready,
                       input logic flush);
    logic accept;
    @(negedge clk_i);
    upstream.valid = valid;
    upstream.payload = payload;
    downstream.ready = ready;
    flush_i = flush;
    #1ns;
    value_check#(logic)::equal(upstream.ready, !flush && (!full_model || ready),
                               "Incorrect upstream ready");
    value_check#(logic)::equal(downstream.valid, full_model && !flush,
                               "Incorrect downstream valid");
    if (downstream.valid) begin
      value_check#(payload_t)::equal(downstream.payload, payload_model,
                                     "Payload ordering or stability failure");
    end
    accept = upstream.valid && upstream.ready;
    @(posedge clk_i);
    if (flush) begin
      scoreboard.clear();
      full_model = 1'b0;
    end else begin
      if (downstream.valid && downstream.ready) begin
        scoreboard.check_actual(downstream.payload);
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
    value_check#(logic)::equal(downstream.valid, full_model && !flush,
                               "Incorrect registered validity");
    if (downstream.valid) begin
      value_check#(payload_t)::equal(downstream.payload, payload_model,
                                     "Incorrect registered payload");
    end
  endtask

  initial begin
    clk_i = 1'b0;
    scoreboard = new("flushable_pipe_stage");
    rst_n_i = 1'b0;
    upstream.valid = 1'b0;
    upstream.payload = '0;
    downstream.ready = 1'b0;
    flush_i = 1'b0;
    full_model = 1'b0;
    payload_model = '0;

    // Test 1: Reset an empty stage and verify idle operation.
    reset_dut();
    cycle(1'b0, '0, 1'b1, 1'b0);

    // Test 2: Reset an occupied stage and discard the pending payload.
    cycle(1'b1, payload_t'(33'h1_12345678), 1'b0, 1'b0);
    reset_dut();
    cycle(1'b0, '0, 1'b1, 1'b0);

    // Test 3: Sustain one accepted transfer per cycle with a ready consumer.
    reset_dut();
    for (int unsigned i = 0; i < 100; i++) begin
      cycle(1'b1, payload_t'(i), 1'b1, 1'b0);
    end

    // Test 4: Hold the output stable under backpressure, then replace it on a pop.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_87654321), 1'b0, 1'b0);
    repeat (20) cycle(1'b1, payload_t'($urandom), 1'b0, 1'b0);
    cycle(1'b1, payload_t'(33'h0_12345678), 1'b1, 1'b0);

    // Test 5: Flush an occupied stage, block both handshakes, then accept new data.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_12345678), 1'b0, 1'b0);
    cycle(1'b1, payload_t'(33'h1_87654321), 1'b1, 1'b1);
    cycle(1'b0, '0, 1'b1, 1'b0);
    cycle(1'b1, payload_t'(33'h1_aabbccdd), 1'b1, 1'b0);

    // Test 6: Randomize traffic, stalls, and flushes, then drain all pending data.
    reset_dut();
    check(RANDOM_CYCLES > 0, "RANDOM_CYCLES must be positive");
    repeat (RANDOM_CYCLES) begin
      cycle(1'($urandom), payload_t'({$urandom, $urandom}), 1'($urandom), $urandom_range(0, 15
            ) == 0);
    end
    cycle(1'b0, '0, 1'b1, 1'b0);
    cycle(1'b0, '0, 1'b1, 1'b0);
    check(!downstream.valid, "Pipeline did not drain");

    // Finish
    scoreboard.check_empty();
    finish_test();
  end
endmodule
