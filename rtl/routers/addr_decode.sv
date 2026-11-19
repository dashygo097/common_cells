`include "cc/addr_decode.svh"

module addr_decode #(
    parameter  int unsigned ADDR_WIDTH = 32,
    parameter  int unsigned NUM_IDS    = 1,
    localparam int unsigned IdWidth    = cc_pkg::index_width(NUM_IDS),

    localparam type addr_t = logic [ADDR_WIDTH - 1:0],
    localparam type id_t   = logic [   IdWidth - 1:0],

    localparam type                       addr_range_t = `CC_ADDR_RANGE_TYPE(addr_t, id_t),
    parameter  addr_range_t [NUM_IDS-1:0] ADDR_MAP     = '0
) (
    input addr_t addr_i,

    valid_if.source result
);
  addr_decode_dyn #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .NUM_IDS(NUM_IDS)
  ) i_addr_decode_dyn (
      .addr_i(addr_i),
      .addr_map_i(ADDR_MAP),
      .result(result)
  );

endmodule
