`include "cc/assertions.svh"

module dyn_addr_decode
  import cc_pkg::*;
#(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_IDS = 1,
    // NOTE: Manually overriding parameters below when instantiation is not recommended
    parameter int unsigned ID_WIDTH = index_width(NUM_IDS),
    parameter type addr_t = logic [ADDR_WIDTH - 1:0],
    parameter type id_t = logic [ID_WIDTH - 1:0],
    // verilog_lint: waive typedef-structs-unions
    parameter type addr_range_t = struct packed {
      id_t                 id;
      addr_t               addr_start;
      logic [ADDR_WIDTH:0] addr_end;
    },
    parameter int unsigned NUM_RULES = NUM_IDS
) (
    input addr_t                         addr_i,
    input addr_range_t [NUM_RULES - 1:0] addr_map_i,

    valid_if.source result
);
  typedef logic [ADDR_WIDTH:0] bound_t;
  typedef logic [ID_WIDTH:0] id_check_t;

  localparam bound_t AddressLimit = {1'b1, {ADDR_WIDTH{1'b0}}};
  localparam id_check_t IdLimit = id_check_t'(NUM_IDS);
  localparam int unsigned RangeIdWidth = $bits(addr_map_i[0].id);
  localparam int unsigned RangeStartWidth = $bits(addr_map_i[0].addr_start);
  localparam int unsigned RangeEndWidth = $bits(addr_map_i[0].addr_end);

  logic map_valid;
  logic matched;
  logic ambiguous;

  always_comb begin
    map_valid = 1'b1;
    matched = 1'b0;
    ambiguous = 1'b0;
    result.valid = 1'b0;
    result.payload = '0;

    for (int unsigned i = 0; i < NUM_RULES; i++) begin
      if (bound_t'(addr_map_i[i].addr_start) != bound_t'(addr_map_i[i].addr_end)) begin
        if ((bound_t'(addr_map_i[i].addr_start) > bound_t'(addr_map_i[i].addr_end)) ||
            (bound_t'(addr_map_i[i].addr_end) > AddressLimit) ||
            (id_check_t'(addr_map_i[i].id) >= IdLimit)) begin
          map_valid = 1'b0;
        end
        if ((bound_t'(addr_i) >= bound_t'(addr_map_i[i].addr_start)) &&
            (bound_t'(addr_i) < bound_t'(addr_map_i[i].addr_end))) begin
          ambiguous = ambiguous || matched;
          matched = 1'b1;
          result.payload = id_t'(addr_map_i[i].id);
        end
      end
    end

    result.valid = map_valid && matched && !ambiguous;
    if (!result.valid) begin
      result.payload = '0;
    end
  end

  `CC_ASSERT_INIT(AddressWidthPositive, ADDR_WIDTH > 0)
  `CC_ASSERT_INIT(IdCountPositive, NUM_IDS > 0)
  `CC_ASSERT_INIT(RuleCountPositive, NUM_RULES > 0)
  `CC_ASSERT_INIT(IdWidthSufficient, ID_WIDTH >= index_width(NUM_IDS))
  `CC_ASSERT_INIT(AddressTypeWidth, $bits(addr_t) == ADDR_WIDTH)
  `CC_ASSERT_INIT(IdTypeWidth, $bits(id_t) == ID_WIDTH)
  `CC_ASSERT_INIT(OutputPayloadWidth, $bits(result.payload) == ID_WIDTH)
  `CC_ASSERT_INIT(RuleIdWidth, RangeIdWidth == ID_WIDTH)
  `CC_ASSERT_INIT(RuleStartWidth, RangeStartWidth == ADDR_WIDTH)
  `CC_ASSERT_INIT(RuleEndWidth, RangeEndWidth == ADDR_WIDTH || RangeEndWidth == ADDR_WIDTH + 1)

endmodule
