module tb_fifo #(
    parameter int unsigned DEPTH = 4,
    parameter int unsigned RANDOM_CYCLES = 1000
) ();
  timeunit 1ns; timeprecision 1ps;

  typedef struct packed {logic [31:0] data;} packet_t;

  logic clk_i;
  logic rst_n_i;
  handshake_if #(.payload_t(packet_t)) upstream ();
  handshake_if #(.payload_t(packet_t)) downstream ();
  logic empty_o;
  logic full_o;

  packet_t expected[$];
  int unsigned cycles;
  int unsigned pushes;
  int unsigned pops;
  int unsigned replacements;
  int unsigned stalls;

  fifo #(
      .DEPTH(DEPTH),
      .payload_t(packet_t)
  ) u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .in(upstream),
      .out(downstream),
      .empty_o(empty_o),
      .full_o(full_o)
  );

  always #5ns clk_i = ~clk_i;

  task automatic check_output();
    df_verify_pkg::value_check#(logic)::equal(empty_o, expected.size() == 0, $sformatf(
                                              "Cycle %0d: incorrect empty flag", cycles));
    df_verify_pkg::value_check#(logic)::equal(full_o, expected.size() == DEPTH, $sformatf(
                                              "Cycle %0d: incorrect full flag", cycles));
    df_verify_pkg::value_check#(logic)::equal(downstream.valid, expected.size() != 0, $sformatf(
                                              "Cycle %0d: incorrect output validity", cycles));
    if (expected.size() != 0) begin
      df_verify_pkg::value_check#(packet_t)::equal(downstream.payload, expected[0], $sformatf(
                                                   "Cycle %0d: output ordering/stability", cycles));
    end
  endtask

  task automatic reset_dut();
    @(negedge clk_i);
    upstream.valid   = 1'b0;
    upstream.payload = '0;
    downstream.ready = 1'b0;
    // Assert between clock edges; validity and flags must reset before a rising edge.
    #2ns;
    rst_n_i = 1'b0;
    expected.delete();
    #1ns;
    check_output();
    df_verify_pkg::wait_cycles(clk_i, 2);
    @(negedge clk_i);
    rst_n_i = 1'b1;
    #1ns;
    check_output();
  endtask

  task automatic cycle(input logic valid, input packet_t payload, input logic ready,
                       output logic accepted);
    logic take_output;
    logic can_accept;

    @(negedge clk_i);
    upstream.valid   = valid;
    upstream.payload = payload;
    downstream.ready = ready;
    #1ns;
    check_output();
    take_output = (expected.size() != 0) && ready;
    can_accept  = (expected.size() < DEPTH) || take_output;
    df_verify_pkg::value_check#(logic)::equal(upstream.ready, can_accept, $sformatf(
                                              "Cycle %0d: incorrect input readiness", cycles));
    accepted = valid && can_accept;
    if (valid && !can_accept) stalls++;
    if (accepted && take_output) replacements++;

    @(posedge clk_i);
    // Retire the old head before appending the accepted input. An empty FIFO
    // does not bypass a newly presented word to the output in the same cycle.
    if (take_output) begin
      void'(expected.pop_front());
      pops++;
    end
    if (accepted) begin
      expected.push_back(payload);
      pushes++;
    end
    cycles++;
    #1ns;
    df_verify_pkg::check(expected.size() <= DEPTH, "Reference occupancy exceeded FIFO capacity");
    check_output();
  endtask

  task automatic test_empty_reads();
    logic accepted;
    // Empty reads must not consume data or change occupancy.
    reset_dut();
    repeat (3) cycle(1'b0, '0, 1'b1, accepted);
  endtask

  task automatic test_capacity_and_replacement();
    logic accepted;
    // All DEPTH entries are usable; an additional write must be backpressured.
    for (int unsigned i = 0; i < DEPTH; i++) begin
      cycle(1'b1, packet_t'(i), 1'b0, accepted);
      df_verify_pkg::check(accepted, "FIFO rejected a write before reaching capacity");
    end
    repeat (20) begin
      cycle(1'b1, packet_t'(32'hdeadbeef), 1'b0, accepted);
      df_verify_pkg::check(!accepted, "Full FIFO accepted a write without a simultaneous read");
    end

    // Complete the producer word held during the full stall before changing data.
    cycle(1'b1, packet_t'(32'hdeadbeef), 1'b1, accepted);
    df_verify_pkg::check(accepted && full_o, "Full FIFO did not accept its stalled producer word");

    // A full FIFO must accept a replacement on every pop, including DEPTH=1.
    // Run long enough to wrap both pointers repeatedly for non-power-of-two depths.
    for (int unsigned i = 0; i < 4 * DEPTH + 5; i++) begin
      cycle(1'b1, packet_t'(32'h10000000 + i), 1'b1, accepted);
      df_verify_pkg::check(accepted && full_o, "Full FIFO failed to sustain simultaneous push/pop");
    end
    repeat (DEPTH) cycle(1'b0, '0, 1'b1, accepted);
    df_verify_pkg::check(empty_o, "FIFO did not become empty after draining DEPTH entries");
    repeat (3) cycle(1'b0, '0, 1'b1, accepted);
  endtask

  task automatic test_reset_occupied();
    logic accepted;
    // Reset discards occupied storage and must restore the empty interface.
    repeat (DEPTH) cycle(1'b1, packet_t'(32'ha5a55a5a), 1'b0, accepted);
    reset_dut();
    cycle(1'b0, '0, 1'b1, accepted);
  endtask

  task automatic test_wraparound();
    logic accepted;
    // Repeated empty/full transitions exercise wraparound independently of streaming.
    repeat (3) begin
      for (int unsigned i = 0; i < DEPTH; i++) begin
        cycle(1'b1, packet_t'(~i), 1'b0, accepted);
        df_verify_pkg::check(accepted, "FIFO rejected a burst write");
      end
      repeat (DEPTH) cycle(1'b0, '0, 1'b1, accepted);
    end
  endtask

  task automatic test_continuous_traffic();
    logic accepted;
    // Maintain one outstanding word with continuous traffic.
    cycle(1'b1, packet_t'(32'h12345678), 1'b0, accepted);
    for (int unsigned i = 0; i < 3 * DEPTH + 20; i++) begin
      cycle(1'b1, packet_t'(i), 1'b1, accepted);
      df_verify_pkg::check(accepted, "FIFO inserted a bubble into continuous traffic");
    end
    cycle(1'b0, '0, 1'b1, accepted);
  endtask

  task automatic test_random_traffic();
    logic accepted;
    logic pending;
    packet_t pending_payload;
    // The producer holds valid/payload until accepted, even across long stalls.
    pending = 1'b0;
    pending_payload = '0;
    repeat (RANDOM_CYCLES) begin
      if (!pending) begin
        pending = $urandom_range(0, 3) != 0;
        pending_payload = packet_t'($urandom);
      end
      cycle(pending, pending_payload, $urandom_range(0, 3) != 0, accepted);
      if (accepted) pending = 1'b0;
      if ($urandom_range(0, 63) == 0) begin
        reset_dut();
        pending = 1'b0;
      end
    end

    // Complete an unaccepted producer word before draining the remaining queue.
    repeat (DEPTH + 2) begin
      cycle(pending, pending_payload, 1'b1, accepted);
      if (accepted) pending = 1'b0;
    end
    df_verify_pkg::check(!pending && expected.size() == 0 && empty_o, "FIFO did not drain");
  endtask

  task automatic check_results();
    df_verify_pkg::check(pushes > 0 && pops > 0, "No input/output transfers checked");
    df_verify_pkg::check(stalls > 0 && replacements > 0,
                         "Missing backpressure or replacement coverage");
  endtask

  initial begin
    clk_i = 1'b0;
    rst_n_i = 1'b0;
    upstream.valid = 1'b0;
    upstream.payload = '0;
    downstream.ready = 1'b0;
    cycles = 0;
    pushes = 0;
    pops = 0;
    replacements = 0;
    stalls = 0;
    df_verify_pkg::check(DEPTH > 0, "DEPTH must be positive");
    df_verify_pkg::check(RANDOM_CYCLES > 0, "RANDOM_CYCLES must be positive");

    test_empty_reads();
    test_capacity_and_replacement();
    test_reset_occupied();
    test_wraparound();
    test_continuous_traffic();
    test_random_traffic();
    check_results();
    df_verify_pkg::finish_test();
  end
endmodule
