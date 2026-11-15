`include "cc/assertions.svh"
`include "cc/addr_decode.svh"

module addr_decode_dyn #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_IDS = 1,
    localparam int unsigned IdWidth = cc_pkg::index_width(NUM_IDS),
    localparam type addr_t = logic [ADDR_WIDTH - 1:0],
    localparam type id_t = logic [IdWidth - 1:0],
    localparam type addr_range_t = `CC_ADDR_RANGE_TYPE(addr_t, id_t)
) (
    input addr_t                       addr_i,
    input addr_range_t [NUM_IDS - 1:0] addr_map_i,

    valid_if.source result
);
  typedef logic [ADDR_WIDTH:0] bound_t;
  typedef logic [IdWidth:0] id_check_t;

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

    for (int unsigned i = 0; i < NUM_IDS; i++) begin
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

  `ASSERT_INIT(AddressWidthPositive, ADDR_WIDTH > 0)
  `ASSERT_INIT(IdCountPositive, NUM_IDS > 0)
  `ASSERT_INIT(IdWidthSufficient, IdWidth >= cc_pkg::index_width(NUM_IDS))
  `ASSERT_INIT(AddressTypeWidth, $bits(addr_t) == ADDR_WIDTH)
  `ASSERT_INIT(IdTypeWidth, $bits(id_t) == IdWidth)
  `ASSERT_INIT(OutputPayloadWidth, $bits(result.payload) == IdWidth)
  `ASSERT_INIT(RuleIdWidth, RangeIdWidth == IdWidth)
  `ASSERT_INIT(RuleStartWidth, RangeStartWidth == ADDR_WIDTH)
  `ASSERT_INIT(RuleEndWidth, RangeEndWidth == ADDR_WIDTH || RangeEndWidth == ADDR_WIDTH + 1)

endmodule
