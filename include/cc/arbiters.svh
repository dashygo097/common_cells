`ifndef CC_ARBITER_SVH_
`define CC_ARBITER_SVH_

`define CC_ARB_RESULT_TYPE(_num_inputs) \
  struct packed { \
      logic [_num_inputs - 1:0] select; \
      logic [cc_pkg::index_width(_num_inputs) - 1:0] index; \
    }

`endif  // CC_ARBITER_SVH_
