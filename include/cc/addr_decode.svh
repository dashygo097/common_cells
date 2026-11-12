`ifndef CC_ADDR_DECODE_SVH_
`define CC_ADDR_DECODE_SVH_

// Public packed type expression for unsigned half-open address ranges.
// The extra end bit represents 2**$bits(_addr_t), including the highest address.
// Example: typedef `CC_ADDR_RANGE_TYPE(addr_t, id_t) addr_range_t;
`define CC_ADDR_RANGE_TYPE(_addr_t, _id_t) \
  struct packed { \
    _id_t id; \
    _addr_t addr_start; \
    logic [$bits(_addr_t):0] addr_end; \
  }

`endif  // CC_ADDR_DECODE_SVH_
