`include "cc/addr_decode.svh"

module tb_addr_decode_dyn #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_IDS = 3,
    parameter bit EXTENDED_END = 1'b1,
    parameter int unsigned RANDOM_CASES = 1000
) ();
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned IdWidth  = cc_pkg::index_width(NUM_IDS);
  localparam int unsigned EndWidth = ADDR_WIDTH + 1;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [ADDR_WIDTH:0] bound_t;
  typedef logic [ADDR_WIDTH+32:0] calculation_t;
  typedef logic [IdWidth-1:0] id_t;
  typedef `CC_ADDR_RANGE_TYPE(addr_t, id_t) rule_t;
  typedef struct packed {
    logic valid;
    id_t  id;
  } result_t;

  localparam id_t LastId = id_t'(NUM_IDS - 1);

  localparam bound_t AddressLimit = {1'b1, {ADDR_WIDTH{1'b0}}};
  localparam bound_t UpperEnd = EXTENDED_END ? AddressLimit : AddressLimit - 1'b1;
  localparam bound_t Split = AddressLimit >> 1;
  localparam logic [IdWidth:0] IdLimit = {1'b1, {IdWidth{1'b0}}};

  addr_t addr_i;
  rule_t [NUM_IDS-1:0] addr_map_i;
  valid_if #(.payload_t(id_t)) decoded_id ();
  int unsigned hits;
  int unsigned rejects;

  addr_decode_dyn #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .NUM_IDS(NUM_IDS)
  ) u_dut (
      .addr_i(addr_i),
      .addr_map_i(addr_map_i),
      .result(decoded_id)
  );

  task automatic set_rule(input int unsigned index, input id_t id, input addr_t first,
                          input bound_t limit);
    addr_map_i[index] = '{id: id, addr_start: first, addr_end: EndWidth'(limit)};
  endtask

  // Use interval lengths/offsets and a queue of matches rather than the DUT's
  // comparator chain. Any malformed active rule invalidates the whole map.
  function automatic result_t reference_decode(input addr_t address);
    id_t selected_ids[$];
    bound_t first;
    bound_t limit;
    bound_t length;
    bound_t offset;

    foreach (addr_map_i[i]) begin
      first = bound_t'(addr_map_i[i].addr_start);
      limit = bound_t'(addr_map_i[i].addr_end);
      if (first == limit) continue;
      if (limit < first || limit > AddressLimit || int'(addr_map_i[i].id) >= NUM_IDS) return '0;
      length = limit - first;
      offset = bound_t'(address) - first;
      if (offset < length) selected_ids.push_back(addr_map_i[i].id);
    end
    if (selected_ids.size() != 1) return '0;
    return '{valid: 1'b1, id: selected_ids[0]};
  endfunction

  task automatic expect_decode(input addr_t address, input logic valid, input id_t id,
                               input string message);
    addr_i = address;
    #1ns;
    df_verify_pkg::value_check#(logic)::equal(decoded_id.valid, valid, $sformatf(
                                              "%s: addr=%h validity", message, address));
    df_verify_pkg::value_check#(id_t)::equal(decoded_id.payload, id, $sformatf(
                                             "%s: addr=%h destination", message, address));
    if (valid) hits++;
    else rejects++;
  endtask

  task automatic check_model(input addr_t address, input string message);
    result_t expected;
    expected = reference_decode(address);
    expect_decode(address, expected.valid, expected.id, message);
  endtask

  function automatic addr_t random_address();
    addr_t value;
    for (int unsigned i = 0; i < ADDR_WIDTH; i++) value[i] = 1'($urandom);
    return value;
  endfunction

  task automatic test_disabled_and_single_range();
    // Disabled maps and a single half-open interval, with explicit expected results.
    expect_decode('0, 1'b0, '0, "All rules disabled");
    expect_decode('1, 1'b0, '0, "Disabled map at highest address");
    set_rule(0, LastId, '0, Split);
    expect_decode('0, 1'b1, LastId, "Inclusive lower endpoint");
    expect_decode(addr_t'(Split - 1'b1), 1'b1, LastId, "Last included address");
    expect_decode(addr_t'(Split), 1'b0, '0, "Exclusive upper endpoint");
    expect_decode('1, 1'b0, '0, "Unmapped high address");
  endtask

  task automatic test_address_space_boundary();
    // Wide end bounds can represent 2**ADDR_WIDTH without wrapping to zero.
    set_rule(0, LastId, '0, UpperEnd);
    expect_decode('0, 1'b1, LastId, "Whole representable range start");
    expect_decode(addr_t'(UpperEnd - 1'b1), 1'b1, LastId, "Highest included address");
    expect_decode('1, EXTENDED_END, EXTENDED_END ? LastId : '0, "Address-space upper boundary");
  endtask

  task automatic test_adjacent_and_overlapping_ranges();
    if (NUM_IDS >= 2) begin
      // Adjacency is legal. Repeated IDs in disjoint ranges are also legal.
      addr_map_i = '0;
      set_rule(0, '0, '0, Split);
      set_rule(1, LastId, addr_t'(Split), UpperEnd);
      expect_decode(addr_t'(Split - 1'b1), 1'b1, '0, "Adjacent lower rule");
      expect_decode(addr_t'(Split), UpperEnd > Split, UpperEnd > Split ? LastId : '0,
                    "Adjacent upper rule");
      addr_map_i[0].id = LastId;
      expect_decode('0, 1'b1, LastId, "ID changes without address/reset changes");
      if (UpperEnd > Split) begin
        expect_decode(addr_t'(Split), 1'b1, LastId, "Disjoint ranges may share an ID");

        // Overlap is ambiguous only where the queried address matches both rules.
        set_rule(0, '0, '0, UpperEnd);
        expect_decode('0, 1'b1, '0, "Overlap elsewhere must not invalidate unique hit");
        expect_decode(addr_t'(Split), 1'b0, '0, "Overlapping destinations");
        // Keep the index legal even when this procedural branch is inactive.
        addr_map_i[NUM_IDS > 1 ? 1 : 0].id = '0;
        expect_decode(addr_t'(Split), 1'b0, '0, "Overlap is ambiguous even with equal IDs");
      end
    end
  endtask

  task automatic test_reversed_and_disabled_rules();
    // A reversed rule invalidates an unrelated, otherwise valid destination.
    addr_map_i = '0;
    set_rule(0, '0, '1, '0);
    if (NUM_IDS >= 2) set_rule(1, LastId, '0, Split);
    expect_decode('0, 1'b0, '0, "Malformed rule invalidates the entire map");
    set_rule(0, '1, addr_t'(Split), Split);
    expect_decode('0, NUM_IDS >= 2, NUM_IDS >= 2 ? LastId : '0,
                  "Zero-length rules ignore all other fields");
  endtask

  task automatic test_invalid_ids();
    // Non-power-of-two destination counts leave representable but invalid IDs.
    if (IdLimit > (IdWidth + 1)'(NUM_IDS)) begin
      addr_map_i = '0;
      set_rule(0, id_t'(NUM_IDS), '0, Split);
      if (NUM_IDS >= 2) set_rule(1, LastId, addr_t'(Split), UpperEnd);
      expect_decode('0, 1'b0, '0, "Out-of-range destination ID");
      if (NUM_IDS >= 2 && UpperEnd > Split)
        expect_decode(addr_t'(Split), 1'b0, '0, "Invalid ID on an unrelated active rule");
    end
  endtask

  task automatic test_invalid_end_bound();
    if (EXTENDED_END) begin
      addr_map_i = '0;
      set_rule(0, '0, '1, AddressLimit + 1'b1);
      if (NUM_IDS >= 2) set_rule(1, LastId, '0, Split);
      expect_decode('0, 1'b0, '0, "End beyond address space invalidates the map");
    end
  endtask

  task automatic test_random_maps();
    bound_t first;
    bound_t limit;
    bound_t temporary;
    bound_t span;
    int unsigned index;
    // Three traffic families: single valid interval, partitioned maps with holes,
    // and unrestricted maps including disabled, reversed, overlapping and invalid rules.
    repeat (RANDOM_CASES) begin
      addr_map_i = '0;
      case ($urandom_range(
          0, 2
      ))
        0: begin
          first = bound_t'(random_address());
          limit = bound_t'(random_address());
          if (first > limit) begin
            temporary = first;
            first = limit;
            limit = temporary;
          end
          if (first == limit) begin
            if (limit < UpperEnd) limit++;
            else first--;
          end
          set_rule($urandom_range(0, NUM_IDS - 1), id_t'($urandom_range(0, NUM_IDS - 1)),
                   addr_t'(first), limit);
        end
        1: begin
          span = bound_t'(calculation_t'(UpperEnd) / calculation_t'(NUM_IDS));
          for (int unsigned i = 0; i < NUM_IDS; i++) begin
            first = span * bound_t'(i);
            limit = i == NUM_IDS - 1 ? UpperEnd : span * (bound_t'(i) + 1'b1);
            if ($urandom_range(0, 3) != 0)
              set_rule(i, id_t'($urandom_range(0, NUM_IDS - 1)), addr_t'(first), limit);
          end
        end
        default: begin
          for (int unsigned i = 0; i < NUM_IDS; i++) begin
            first = bound_t'(random_address());
            if ($urandom_range(0, 3) == 0) limit = first;
            else
              limit = EXTENDED_END ? {1'($urandom), random_address()} : bound_t'(random_address());
            set_rule(i, id_t'($urandom), addr_t'(first), limit);
          end
        end
      endcase
      check_model(random_address(), "Random map/address");
      index = $urandom_range(0, NUM_IDS - 1);
      check_model(addr_map_i[index].addr_start, "Random lower endpoint");
      limit = bound_t'(addr_map_i[index].addr_end);
      if (limit > 0 && limit <= AddressLimit)
        check_model(addr_t'(limit - 1'b1), "Random last included address");
      if (limit < AddressLimit) check_model(addr_t'(limit), "Random exclusive endpoint");
      addr_map_i[index].id = id_t'($urandom_range(0, NUM_IDS - 1));
      check_model(addr_i, "Dynamic map update at unchanged address");
    end
  endtask

  task automatic test_exhaustive_partition();
    bound_t first;
    bound_t limit;
    bound_t span;
    // Small-width regression configurations can sweep every address affordably.
    if (ADDR_WIDTH <= 8) begin
      addr_map_i = '0;
      span = bound_t'(calculation_t'(UpperEnd) / calculation_t'(NUM_IDS));
      for (int unsigned i = 0; i < NUM_IDS; i++) begin
        first = span * bound_t'(i);
        limit = i == NUM_IDS - 1 ? UpperEnd : span * (bound_t'(i) + 1'b1);
        set_rule(i, id_t'(i % NUM_IDS), addr_t'(first), limit);
      end
      for (bound_t address = '0; address < AddressLimit; address++)
      check_model(addr_t'(address), "Exhaustive partition map");
    end
  endtask

  task automatic check_results();
    df_verify_pkg::check(hits > 0 && rejects > 0, "Missing mapped/unmapped result coverage");
  endtask

  initial begin
    addr_i = '0;
    addr_map_i = '0;
    hits = 0;
    rejects = 0;
    df_verify_pkg::check(ADDR_WIDTH > 0 && NUM_IDS > 0, "Widths/counts must be positive");
    df_verify_pkg::check(RANDOM_CASES > 0, "RANDOM_CASES must be positive");

    test_disabled_and_single_range();
    test_address_space_boundary();
    test_adjacent_and_overlapping_ranges();
    test_reversed_and_disabled_rules();
    test_invalid_ids();
    test_invalid_end_bound();
    test_random_maps();
    test_exhaustive_partition();
    check_results();
    df_verify_pkg::finish_test();
  end
endmodule
