`ifndef CC_REGISTERS_SVH_
`define CC_REGISTERS_SVH_

// Register without reset.
`define REG(_q, _d, _clk = clk_i) \
  always_ff @(posedge (_clk)) begin \
    _q <= (_d); \
  end

// Clock enable, without reset.
`define REG_CE(_q, _d, _ce, _clk = clk_i) \
  always_ff @(posedge (_clk)) begin \
    if (_ce) begin \
      _q <= (_d); \
    end \
  end

// Asynchronous active-low reset.
`define REG_ARSTN(_q, _d, _reset_value, _clk = clk_i, _rst_n = rst_n_i) \
  always_ff @(posedge (_clk) or negedge (_rst_n)) begin \
    if (!(_rst_n)) begin \
      _q <= (_reset_value); \
    end else begin \
      _q <= (_d); \
    end \
  end

// Clock enable and asynchronous active-low reset.
`define REG_CE_ARSTN(_q, _d, _ce, _reset_value, _clk = clk_i, _rst_n = rst_n_i) \
  always_ff @(posedge (_clk) or negedge (_rst_n)) begin \
    if (!(_rst_n)) begin \
      _q <= (_reset_value); \
    end else if (_ce) begin \
      _q <= (_d); \
    end \
  end

// Clock enable and synchronous clear, without asynchronous reset.
`define REG_CE_CLR(_q, _d, _ce, _clear, _clear_value, _clk = clk_i) \
  always_ff @(posedge (_clk)) begin \
    if (_clear) begin \
      _q <= (_clear_value); \
    end else if (_ce) begin \
      _q <= (_d); \
    end \
  end

// Clock enable, synchronous clear, and asynchronous active-low reset.
// Reset and clear both assign _reset_value.
`define REG_CE_CLR_ARSTN(_q, _d, _ce, _clear, _reset_value, _clk = clk_i, _rst_n = rst_n_i) \
  always_ff @(posedge (_clk) or negedge (_rst_n)) begin \
    if (!(_rst_n)) begin \
      _q <= (_reset_value); \
    end else if (_clear) begin \
      _q <= (_reset_value); \
    end else if (_ce) begin \
      _q <= (_d); \
    end \
  end

`endif  // CC_REGISTERS_SVH_
