module tb_dynamic_addr_decode
  import df_verify_pkg::*;
#(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_IDS = 3,
    parameter int unsigned NUM_RULES = 4,
    parameter bit EXTENDED_END = 1'b1,
    parameter int unsigned RANDOM_CASES = 1000
) ();
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned IdWidth  = cc_pkg::index_width(NUM_IDS);
  localparam int unsigned EndWidth = ADDR_WIDTH + int'(EXTENDED_END);
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [ADDR_WIDTH:0] bound_t;
  typedef logic [ADDR_WIDTH+32:0] calculation_t;
  typedef logic [IdWidth-1:0] id_t;
  typedef struct packed {
    id_t id;
    addr_t addr_start;
    logic [EndWidth-1:0] addr_end;
  } rule_t;
  typedef struct packed {
    logic valid;
    id_t  id;
  } result_t;

  localparam bound_t AddressLimit = {1'b1, {ADDR_WIDTH{1'b0}}};
  localparam bound_t UpperEnd = EXTENDED_END ? AddressLimit : AddressLimit - 1'b1;
  localparam bound_t Split = AddressLimit >> 1;
  localparam logic [IdWidth:0] IdLimit = {1'b1, {IdWidth{1'b0}}};

  addr_t addr_i;
  rule_t [NUM_RULES-1:0] addr_map_i;
  logic valid_o;
  id_t id_o;
  int unsigned hits;
  int unsigned rejects;

  dynamic_addr_decode #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .NUM_IDS(NUM_IDS),
      .addr_range_t(rule_t),
      .NUM_RULES(NUM_RULES)
  ) u_dut (
      .addr_i(addr_i),
      .addr_map_i(addr_map_i),
      .valid_o(valid_o),
      .id_o(id_o)
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
    value_check#(logic)::equal(valid_o, valid, $sformatf("%s: addr=%h validity", message, address));
    value_check#(id_t)::equal(id_o, id, $sformatf("%s: addr=%h destination", message, address));
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

  initial begin
    bound_t first;
    bound_t limit;
    bound_t temporary;
    bound_t span;
    int unsigned index;
    id_t last_id;

    addr_i = '0;
    addr_map_i = '0;
    hits = 0;
    rejects = 0;
    last_id = id_t'(NUM_IDS - 1);
    check(ADDR_WIDTH > 0 && NUM_IDS > 0 && NUM_RULES > 0, "Widths/counts must be positive");
    check(RANDOM_CASES > 0, "RANDOM_CASES must be positive");

    // Disabled maps and a single half-open interval, with explicit expected results.
    expect_decode('0, 1'b0, '0, "All rules disabled");
    expect_decode('1, 1'b0, '0, "Disabled map at highest address");
    set_rule(0, last_id, '0, Split);
    expect_decode('0, 1'b1, last_id, "Inclusive lower endpoint");
    expect_decode(addr_t'(Split - 1'b1), 1'b1, last_id, "Last included address");
    expect_decode(addr_t'(Split), 1'b0, '0, "Exclusive upper endpoint");
    expect_decode('1, 1'b0, '0, "Unmapped high address");

    // Wide end bounds can represent 2**ADDR_WIDTH without wrapping to zero.
    set_rule(0, last_id, '0, UpperEnd);
    expect_decode('0, 1'b1, last_id, "Whole representable range start");
    expect_decode(addr_t'(UpperEnd - 1'b1), 1'b1, last_id, "Highest included address");
    expect_decode('1, EXTENDED_END, EXTENDED_END ? last_id : '0, "Address-space upper boundary");

    if (NUM_RULES >= 2) begin
      // Adjacency is legal. Repeated IDs in disjoint ranges are also legal.
      addr_map_i = '0;
      set_rule(0, '0, '0, Split);
      set_rule(1, last_id, addr_t'(Split), UpperEnd);
      expect_decode(addr_t'(Split - 1'b1), 1'b1, '0, "Adjacent lower rule");
      expect_decode(addr_t'(Split), UpperEnd > Split, UpperEnd > Split ? last_id : '0,
                    "Adjacent upper rule");
      addr_map_i[0].id = last_id;
      expect_decode('0, 1'b1, last_id, "ID changes without address/reset changes");
      if (UpperEnd > Split) begin
        expect_decode(addr_t'(Split), 1'b1, last_id, "Disjoint ranges may share an ID");

        // Overlap is ambiguous only where the queried address matches both rules.
        set_rule(0, '0, '0, UpperEnd);
        expect_decode('0, 1'b1, '0, "Overlap elsewhere must not invalidate unique hit");
        expect_decode(addr_t'(Split), 1'b0, '0, "Overlapping destinations");
        addr_map_i[1].id = '0;
        expect_decode(addr_t'(Split), 1'b0, '0, "Overlap is ambiguous even with equal IDs");
      end
    end

    // A reversed rule invalidates an unrelated, otherwise valid destination.
    addr_map_i = '0;
    set_rule(0, '0, '1, '0);
    if (NUM_RULES >= 2) set_rule(1, last_id, '0, Split);
    expect_decode('0, 1'b0, '0, "Malformed rule invalidates the entire map");
    set_rule(0, '1, addr_t'(Split), Split);
    expect_decode('0, NUM_RULES >= 2, NUM_RULES >= 2 ? last_id : '0,
                  "Zero-length rules ignore all other fields");

    // Non-power-of-two destination counts leave representable but invalid IDs.
    if (IdLimit > (IdWidth + 1)'(NUM_IDS)) begin
      addr_map_i = '0;
      set_rule(0, id_t'(NUM_IDS), '0, Split);
      if (NUM_RULES >= 2) set_rule(1, last_id, addr_t'(Split), UpperEnd);
      expect_decode('0, 1'b0, '0, "Out-of-range destination ID");
      if (NUM_RULES >= 2 && UpperEnd > Split)
        expect_decode(addr_t'(Split), 1'b0, '0, "Invalid ID on an unrelated active rule");
    end
    if (EXTENDED_END) begin
      addr_map_i = '0;
      set_rule(0, '0, '1, AddressLimit + 1'b1);
      if (NUM_RULES >= 2) set_rule(1, last_id, '0, Split);
      expect_decode('0, 1'b0, '0, "End beyond address space invalidates the map");
    end

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
          set_rule($urandom_range(0, NUM_RULES - 1), id_t'($urandom_range(0, NUM_IDS - 1)),
                   addr_t'(first), limit);
        end
        1: begin
          span = bound_t'(calculation_t'(UpperEnd) / calculation_t'(NUM_RULES));
          for (int unsigned i = 0; i < NUM_RULES; i++) begin
            first = span * bound_t'(i);
            limit = i == NUM_RULES - 1 ? UpperEnd : span * (bound_t'(i) + 1'b1);
            if ($urandom_range(0, 3) != 0)
              set_rule(i, id_t'($urandom_range(0, NUM_IDS - 1)), addr_t'(first), limit);
          end
        end
        default: begin
          for (int unsigned i = 0; i < NUM_RULES; i++) begin
            first = bound_t'(random_address());
            if ($urandom_range(0, 3) == 0) limit = first;
            else
              limit = EXTENDED_END ? {1'($urandom), random_address()} : bound_t'(random_address());
            set_rule(i, id_t'($urandom), addr_t'(first), limit);
          end
        end
      endcase
      check_model(random_address(), "Random map/address");
      index = $urandom_range(0, NUM_RULES - 1);
      check_model(addr_map_i[index].addr_start, "Random lower endpoint");
      limit = bound_t'(addr_map_i[index].addr_end);
      if (limit > 0 && limit <= AddressLimit)
        check_model(addr_t'(limit - 1'b1), "Random last included address");
      if (limit < AddressLimit) check_model(addr_t'(limit), "Random exclusive endpoint");
      addr_map_i[index].id = id_t'($urandom_range(0, NUM_IDS - 1));
      check_model(addr_i, "Dynamic map update at unchanged address");
    end

    // Small-width regression configurations can sweep every address affordably.
    if (ADDR_WIDTH <= 8) begin
      addr_map_i = '0;
      span = bound_t'(calculation_t'(UpperEnd) / calculation_t'(NUM_RULES));
      for (int unsigned i = 0; i < NUM_RULES; i++) begin
        first = span * bound_t'(i);
        limit = i == NUM_RULES - 1 ? UpperEnd : span * (bound_t'(i) + 1'b1);
        set_rule(i, id_t'(i % NUM_IDS), addr_t'(first), limit);
      end
      for (bound_t address = '0; address < AddressLimit; address++)
      check_model(addr_t'(address), "Exhaustive partition map");
    end
    check(hits > 0 && rejects > 0, "Missing mapped/unmapped result coverage");
    finish_test();
  end
endmodule
