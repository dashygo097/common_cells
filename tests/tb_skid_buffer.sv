module tb_skid_buffer #(
    parameter int unsigned RANDOM_CYCLES = 1000
) ();

  typedef struct packed {
    logic [31:0] data;
    logic last;
  } payload_t;

  logic clk_i;
  logic rst_n_i;
  handshake_if #(.payload_t(payload_t)) in ();
  handshake_if #(.payload_t(payload_t)) out ();
  logic stalled;
  payload_t stalled_payload;
  logic pushed_last;
  logic popped_last;
  df_verify_pkg::ordered_scoreboard #(payload_t) scoreboard;

  skid_buffer #(
      .payload_t(payload_t)
  ) u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .in(in),
      .out(out)
  );

  always #5ns clk_i = ~clk_i;

  task automatic reset_dut();
    @(negedge clk_i);
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    rst_n_i = 1'b0;
    stalled = 1'b0;
    stalled_payload = '0;
    pushed_last = 1'b0;
    popped_last = 1'b0;
    scoreboard.clear();
    #1ns;
    df_verify_pkg::check(!out.valid, "Reset must clear out validity");
    df_verify_pkg::wait_cycles(clk_i, 2);
    @(negedge clk_i);
    rst_n_i = 1'b1;
  endtask

  task automatic cycle(input logic valid, input payload_t payload, input logic ready);
    logic ready_before;
    @(negedge clk_i);
    ready_before = in.ready;
    in.valid = valid;
    in.payload = payload;
    out.ready = ready;
    #1ns;
    df_verify_pkg::value_check#(logic)::known(in.ready, "Unknown input ready after reset");
    df_verify_pkg::value_check#(logic)::equal(in.ready, ready_before,
                                              "Input ready changed without a clock edge");
    df_verify_pkg::value_check#(logic)::equal(
        out.valid, scoreboard.pending_count() != 0,
        "Output validity disagrees with pending transactions");
    if (stalled) begin
      df_verify_pkg::check(out.valid, "Stalled output lost validity");
      df_verify_pkg::value_check#(payload_t)::equal(out.payload, stalled_payload,
                                                    "Stalled output payload changed");
    end
    if (out.valid) begin
      df_verify_pkg::value_check#(payload_t)::known(out.payload, "Unknown valid output payload");
    end
    pushed_last = in.valid && in.ready;
    popped_last = out.valid && out.ready;
    stalled = out.valid && !out.ready;
    stalled_payload = out.payload;
    @(posedge clk_i);
    if (popped_last) begin
      scoreboard.check_actual(out.payload);
    end
    if (pushed_last) begin
      scoreboard.push_expected(payload);
    end
    df_verify_pkg::check(scoreboard.pending_count() <= 2,
                         "Skid buffer exceeded its two-entry capacity");
    #1ns;
    df_verify_pkg::value_check#(logic)::equal(out.valid, scoreboard.pending_count() != 0,
                                              "Incorrect registered output validity");
    if (stalled) begin
      df_verify_pkg::value_check#(payload_t)::equal(out.payload, stalled_payload,
                                                    "Clock edge changed stalled output payload");
    end
  endtask

  task automatic drain_dut();
    repeat (3) cycle(1'b0, '0, 1'b1);
    scoreboard.check_empty();
    df_verify_pkg::check(!out.valid, "Skid buffer did not drain");
  endtask

  task automatic test_reset_empty();
    // Reset an empty stage and verify idle operation.
    reset_dut();
    cycle(1'b0, '0, 1'b1);
  endtask

  task automatic test_reset_occupied();
    // Reset an occupied stage and discard the pending payload.
    cycle(1'b1, payload_t'(33'h1_12345678), 1'b0);
    reset_dut();
    cycle(1'b0, '0, 1'b1);
  endtask

  task automatic test_throughput();
    longint unsigned comparisons_before;
    // Sustain one accepted transfer per cycle with a ready consumer.
    reset_dut();
    comparisons_before = scoreboard.comparison_count();
    for (int unsigned i = 0; i < 100; i++) begin
      cycle(1'b1, payload_t'(i), 1'b1);
      df_verify_pkg::check(pushed_last, "Ready consumer failed to sustain input throughput");
      if (i > 0) df_verify_pkg::check(popped_last, "Bubble in continuous output traffic");
    end
    drain_dut();
    df_verify_pkg::check(scoreboard.comparison_count() - comparisons_before == 100,
                         "Throughput test did not deliver all 100 inputs");
  endtask

  task automatic test_backpressure_replay();
    // Fill both slots, stall, then replay the extra item before new input.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_11111111), 1'b0);
    df_verify_pkg::check(pushed_last, "Empty skid buffer did not accept the first item");
    cycle(1'b1, payload_t'(33'h0_22222222), 1'b0);
    df_verify_pkg::check(pushed_last, "Skid slot did not absorb the second item");
    df_verify_pkg::check(scoreboard.pending_count() == 2, "Both slots should be occupied");
    repeat (20) begin
      cycle(1'b1, payload_t'(33'h1_33333333), 1'b0);
      df_verify_pkg::check(!pushed_last, "Full skid buffer accepted another item");
    end
    cycle(1'b1, payload_t'(33'h1_33333333), 1'b1);
    df_verify_pkg::check(!pushed_last && popped_last,
                         "Backpressure recovery must respect registered ready");
    cycle(1'b1, payload_t'(33'h1_33333333), 1'b1);
    df_verify_pkg::check(pushed_last && popped_last,
                         "Failed simultaneous receive and replay output");
    drain_dut();
  endtask

  task automatic test_reset_full();
    // Reset a full skid buffer and discard both pending items.
    reset_dut();
    cycle(1'b1, payload_t'(33'h1_aaaaaaaa), 1'b0);
    cycle(1'b1, payload_t'(33'h0_bbbbbbbb), 1'b0);
    df_verify_pkg::check(scoreboard.pending_count() == 2, "Reset test did not fill both slots");
    reset_dut();
    drain_dut();
  endtask

  task automatic test_random_traffic();
    logic offered_valid;
    payload_t offered_payload;
    // Randomize traffic/backpressure while holding unaccepted inputs stable.
    reset_dut();
    df_verify_pkg::check(RANDOM_CYCLES > 0, "RANDOM_CYCLES must be positive");
    offered_valid   = 1'b0;
    offered_payload = '0;
    repeat (RANDOM_CYCLES) begin
      if (!offered_valid || pushed_last) begin
        offered_valid   = 1'($urandom);
        offered_payload = payload_t'({$urandom, $urandom});
      end
      cycle(offered_valid, offered_payload, 1'($urandom));
    end
    // Complete any still-offered input before withdrawing valid for the drain.
    if (offered_valid && !pushed_last) begin
      for (int unsigned i = 0; i < 3; i++) begin
        cycle(1'b1, offered_payload, 1'b1);
        if (pushed_last) break;
      end
      df_verify_pkg::check(pushed_last,
                           "Pending input was not accepted after backpressure release");
    end
    drain_dut();
  endtask

  task automatic check_results();
    scoreboard.check_empty();
  endtask

  initial begin
    clk_i = 1'b0;
    scoreboard = new("skid_buffer");
    rst_n_i = 1'b0;
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    stalled = 1'b0;
    stalled_payload = '0;
    pushed_last = 1'b0;
    popped_last = 1'b0;

    test_reset_empty();
    test_reset_occupied();
    test_throughput();
    test_backpressure_replay();
    test_reset_full();
    test_random_traffic();
    check_results();
    df_verify_pkg::finish_test();
  end
endmodule
