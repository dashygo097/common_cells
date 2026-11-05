`ifndef CC_ASSERTIONS_SVH_
`define CC_ASSERTIONS_SVH_

`ifndef SYNTHESIS
`ifndef CC_ASSERTIONS_OFF
`define CC_ASSERTIONS_ENABLED_
`endif
`endif

`ifdef CC_ASSERTIONS_ENABLED_

`define CC_ASSERT_FAIL_(_name, _message) \
  $fatal(1, "%m: assertion failed: %s (%s:%0d) %s", \
         `"_name`", `__FILE__, `__LINE__, (_message));

`define CC_ASSERT_I(_name, _condition, _message = "") \
  _name: assert ((_condition) === 1'b1) \
    else begin \
      `CC_ASSERT_FAIL_(_name, _message) \
    end

`define CC_ASSERT_INIT(_name, _condition, _message = "") \
  initial begin \
    `CC_ASSERT_I(_name, _condition, _message) \
  end

`define CC_ASSERT_FINAL(_name, _condition, _message = "") \
  final begin \
    `CC_ASSERT_I(_name, _condition, _message) \
  end

`define CC_ASSERT(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  _name: assert property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property)) \
    else begin \
      `CC_ASSERT_FAIL_(_name, _message) \
    end

`define CC_ASSERT_IF(_name, _property, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `CC_ASSERT(_name, (_enable) |-> (_property), _clk, _rst_n, _message)

`define CC_ASSERT_NEVER(_name, _condition, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `CC_ASSERT(_name, !(_condition), _clk, _rst_n, _message)

`define CC_ASSERT_KNOWN(_name, _signal, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `CC_ASSERT(_name, !$isunknown(_signal), _clk, _rst_n, _message)

`define CC_ASSERT_KNOWN_IF(_name, _signal, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `CC_ASSERT_IF(_name, !$isunknown(_signal), _enable, _clk, _rst_n, _message)

`define CC_ASSUME(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  _name: assume property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property)) \
    else begin \
      `CC_ASSERT_FAIL_(_name, _message) \
    end

`define CC_COVER(_name, _property, _clk = clk_i, _rst_n = rst_n_i) \
  _name: cover property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property));

`undef CC_ASSERTIONS_ENABLED_

`else

`define CC_ASSERT_I(_name, _condition, _message = "")
`define CC_ASSERT_INIT(_name, _condition, _message = "")
`define CC_ASSERT_FINAL(_name, _condition, _message = "")
`define CC_ASSERT(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_ASSERT_IF(_name, _property, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_ASSERT_NEVER(_name, _condition, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_ASSERT_KNOWN(_name, _signal, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_ASSERT_KNOWN_IF(_name, _signal, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_ASSUME(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define CC_COVER(_name, _property, _clk = clk_i, _rst_n = rst_n_i)

`endif

`endif  // CC_ASSERTIONS_SVH_
