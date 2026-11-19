`include "cc/arbiters.svh"

module tb_arbiter_priority #(
    parameter int unsigned NUM_INPUTS   = 5,
    parameter int unsigned PRIORITY_CFG = 0,
    parameter int unsigned RANDOM_CASES = 1000
) ();
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned IndexWidth = cc_pkg::index_width(NUM_INPUTS);
  typedef logic [NUM_INPUTS-1:0] req_t;
  typedef logic [IndexWidth-1:0] index_t;
  typedef `CC_ARB_RESULT_TYPE(NUM_INPUTS) result_t;

  req_t req_i;
  valid_if #(.payload_t(result_t)) result_arb ();
  req_t granted_inputs;
  int unsigned active_cases;
  int unsigned idle_cases;
  int unsigned contended_cases;

  arbiter_priority #(
      .NUM_INPUTS  (NUM_INPUTS),
      .PRIORITY_CFG(PRIORITY_CFG)
  ) u_dut (
      .req_i (req_i),
      .result(result_arb)
  );

  // Rank physical requesters independently of the DUT's rotated-index scan.
  function automatic index_t reference_index(input req_t requests);
    int unsigned best_rank;
    int unsigned rank;
    index_t winner;
    best_rank = NUM_INPUTS;
    winner = '0;
    for (int unsigned i = 0; i < NUM_INPUTS; i++) begin
      rank = NUM_INPUTS - PRIORITY_CFG + i;
      if (rank >= NUM_INPUTS) rank -= NUM_INPUTS;
      if (requests[i] && rank < best_rank) begin
        best_rank = rank;
        winner = index_t'(i);
      end
    end
    return winner;
  endfunction

  task automatic expect_selection(input req_t requests, input logic valid, input index_t index,
                                  input string message);
    result_t expected;
    expected = '0;
    if (valid) begin
      expected.select[index] = 1'b1;
      expected.index = index;
    end
    req_i = requests;
    #1ns;
    df_verify_pkg::value_check#(logic)::equal(result_arb.valid, valid, $sformatf(
                                              "%s: requests=%h validity", message, requests));
    df_verify_pkg::value_check#(result_t)::known(result_arb.payload, message);
    df_verify_pkg::value_check#(result_t)::equal(result_arb.payload, expected, $sformatf(
                                                 "%s: requests=%h grant/index", message, requests));
    if (valid) begin
      active_cases++;
      granted_inputs |= result_arb.payload.select;
    end else idle_cases++;
    if ($countones(requests) > 1) contended_cases++;
  endtask

  task automatic check_model(input req_t requests, input string message);
    expect_selection(requests, |requests, reference_index(requests), message);
  endtask

  task automatic test_idle();
    repeat (4) expect_selection('0, 1'b0, '0, "Idle arbiter must clear valid and payload");
  endtask

  task automatic test_single_requests();
    req_t requests;
    for (int unsigned i = 0; i < NUM_INPUTS; i++) begin
      requests = '0;
      requests[i] = 1'b1;
      expect_selection(requests, 1'b1, index_t'(i), "A lone requester must win");
      expect_selection('0, 1'b0, '0, "Removing a request must clear the old grant/index");
    end
  endtask

  task automatic test_pairwise_priority();
    req_t requests;
    for (int unsigned i = 0; i < NUM_INPUTS; i++) begin
      for (int unsigned j = i + 1; j < NUM_INPUTS; j++) begin
        requests = '0;
        requests[i] = 1'b1;
        requests[j] = 1'b1;
        check_model(requests, $sformatf("Competing requesters %0d and %0d", i, j));
      end
    end
  endtask

  task automatic test_fixed_priority();
    // An unchanged request vector must not rotate the winner over time.
    repeat (8) expect_selection('1, 1'b1, index_t'(PRIORITY_CFG), "All requests remain asserted");
  endtask

  task automatic test_priority_wraparound();
    req_t requests;
    requests = '1;
    // Requesters retain their requests externally until their turn to win.
    // Two linear ranges specify the expected order without modulo arithmetic.
    for (int unsigned i = PRIORITY_CFG; i < NUM_INPUTS; i++) begin
      expect_selection(requests, 1'b1, index_t'(i), "Priority order before wraparound");
      requests[i] = 1'b0;
    end
    for (int unsigned i = 0; i != PRIORITY_CFG; i++) begin
      expect_selection(requests, 1'b1, index_t'(i), "Priority order after wraparound");
      requests[i] = 1'b0;
    end
    expect_selection(requests, 1'b0, '0, "All serviced requests have been withdrawn");
  endtask

  task automatic test_request_changes();
    req_t requests;
    int unsigned lowest;
    if (NUM_INPUTS < 2) return;
    lowest = PRIORITY_CFG == 0 ? NUM_INPUTS - 1 : PRIORITY_CFG - 1;
    requests = '0;
    requests[lowest] = 1'b1;
    expect_selection(requests, 1'b1, index_t'(lowest), "Lowest priority request alone");
    requests[PRIORITY_CFG] = 1'b1;
    expect_selection(requests, 1'b1, index_t'(PRIORITY_CFG), "Higher priority request preempts");
    requests[PRIORITY_CFG] = 1'b0;
    expect_selection(requests, 1'b1, index_t'(lowest), "Held lower priority request wins again");

    // This selector has no storage: a withdrawn losing request must not reappear.
    requests[PRIORITY_CFG] = 1'b1;
    expect_selection(requests, 1'b1, index_t'(PRIORITY_CFG), "Higher priority request returns");
    requests[lowest] = 1'b0;
    expect_selection(requests, 1'b1, index_t'(PRIORITY_CFG), "Losing request is withdrawn");
    expect_selection('0, 1'b0, '0, "No request may remain after all inputs are cleared");
  endtask

  task automatic test_exhaustive_requests();
    req_t requests;
    if (NUM_INPUTS > 10) return;
    requests = '0;
    do begin
      check_model(requests, "Exhaustive request vector");
      requests += req_t'(1);
    end while (requests != '0);
  endtask

  task automatic test_random_requests();
    req_t requests;
    repeat (RANDOM_CASES) begin
      // Randomize every bit, including requesters beyond a 32-bit random word.
      foreach (requests[i]) requests[i] = 1'($urandom);
      check_model(requests, "Random request vector");
    end
    expect_selection('0, 1'b0, '0, "Idle after random traffic");
  endtask

  task automatic check_results();
    df_verify_pkg::check(active_cases > 0 && idle_cases > 0, "Missing active/idle coverage");
    df_verify_pkg::value_check#(req_t)::equal(granted_inputs, '1, "Every requester must win");
    if (NUM_INPUTS > 1)
      df_verify_pkg::check(contended_cases > 0, "Missing competing-request coverage");
    $display("Priority arbiter: inputs=%0d priority=%0d active=%0d idle=%0d contended=%0d",
             NUM_INPUTS, PRIORITY_CFG, active_cases, idle_cases, contended_cases);
  endtask

  initial begin
    req_i = '0;
    granted_inputs = '0;
    active_cases = 0;
    idle_cases = 0;
    contended_cases = 0;
    df_verify_pkg::check(NUM_INPUTS > 0, "NUM_INPUTS must be positive");
    df_verify_pkg::check(PRIORITY_CFG < NUM_INPUTS, "PRIORITY_CFG must select an existing input");
    df_verify_pkg::check(RANDOM_CASES > 0, "RANDOM_CASES must be positive");

    test_idle();
    test_single_requests();
    test_pairwise_priority();
    test_fixed_priority();
    test_priority_wraparound();
    test_request_changes();
    test_exhaustive_requests();
    test_random_requests();
    check_results();
    df_verify_pkg::finish_test();
  end
endmodule
