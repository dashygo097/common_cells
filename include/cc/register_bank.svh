`ifndef CC_REGISTER_BANK_SVH_
`define CC_REGISTER_BANK_SVH_

// Public packed type expressions. Use with typedef in a consuming package, or
// with localparam type in a module. Field order is part of the interface ABI.
// Example: typedef `CC_REG_BANK_REQ_TYPE(addr_t, data_t, strb_t) reg_req_t;
// Addresses are byte addresses; strobe bit b selects data bits [8*b +: 8].

`define CC_REG_BANK_REQ_TYPE(_addr_t, _data_t, _strb_t) \
  struct packed { \
    _addr_t addr; \
    logic write; \
    _data_t data; \
    _strb_t strb; \
  }

`define CC_REG_BANK_RESP_TYPE(_data_t) \
  struct packed { \
    _data_t data; \
    logic error; \
  }

`endif  // CC_REGISTER_BANK_SVH_
