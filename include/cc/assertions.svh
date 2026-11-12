`ifndef ASSERTIONS_SVH_
`define ASSERTIONS_SVH_

`ifndef SYNTHESIS
`ifndef ASSERTIONS_OFF
`define ASSERTIONS_ENABLED_
`endif
`endif

`ifdef ASSERTIONS_ENABLED_

`define ASSERT_FAIL_(_name, _message) \
  $fatal(1, "%m: assertion failed: %s (%s:%0d) %s", \
         `"_name`", `__FILE__, `__LINE__, (_message));

`define ASSERT_I(_name, _condition, _message = "") \
  _name: assert ((_condition) === 1'b1) \
    else begin \
      `ASSERT_FAIL_(_name, _message) \
    end

`define ASSERT_INIT(_name, _condition, _message = "") \
  initial begin \
    `ASSERT_I(_name, _condition, _message) \
  end

`define ASSERT_FINAL(_name, _condition, _message = "") \
  final begin \
    `ASSERT_I(_name, _condition, _message) \
  end

`define ASSERT(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  _name: assert property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property)) \
    else begin \
      `ASSERT_FAIL_(_name, _message) \
    end

`define ASSERT_IF(_name, _property, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `ASSERT(_name, (_enable) |-> (_property), _clk, _rst_n, _message)

`define ASSERT_NEVER(_name, _condition, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `ASSERT(_name, !(_condition), _clk, _rst_n, _message)

`define ASSERT_KNOWN(_name, _signal, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `ASSERT(_name, !$isunknown(_signal), _clk, _rst_n, _message)

`define ASSERT_KNOWN_IF(_name, _signal, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  `ASSERT_IF(_name, !$isunknown(_signal), _enable, _clk, _rst_n, _message)

`define ASSUME(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "") \
  _name: assume property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property)) \
    else begin \
      `ASSERT_FAIL_(_name, _message) \
    end

`define COVER(_name, _property, _clk = clk_i, _rst_n = rst_n_i) \
  _name: cover property (@(posedge (_clk)) \
      disable iff ((_rst_n) !== 1'b1) (_property));

`undef ASSERTIONS_ENABLED_

`else

`define ASSERT_I(_name, _condition, _message = "")
`define ASSERT_INIT(_name, _condition, _message = "")
`define ASSERT_FINAL(_name, _condition, _message = "")
`define ASSERT(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define ASSERT_IF(_name, _property, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define ASSERT_NEVER(_name, _condition, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define ASSERT_KNOWN(_name, _signal, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define ASSERT_KNOWN_IF(_name, _signal, _enable, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define ASSUME(_name, _property, _clk = clk_i, _rst_n = rst_n_i, _message = "")
`define COVER(_name, _property, _clk = clk_i, _rst_n = rst_n_i)

`endif

`endif  // ASSERTIONS_SVH_
