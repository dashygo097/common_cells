`include "cc/assertions.svh"
`include "cc/arbiters.svh"

module arbiter_priority #(
    // NOTE: example: NUM_INPUTS = 4, PRIORITY_CFG = 2
    // priority: req_i[2] > req_i[3] > req_i[0] > req_i[1]
    parameter  int unsigned NUM_INPUTS   = 2,
    parameter  int unsigned PRIORITY_CFG = 0,
    localparam int unsigned IndexWidth   = cc_pkg::index_width(NUM_INPUTS),
    localparam type         result_t     = `CC_ARB_RESULT_TYPE(NUM_INPUTS)
) (
    input logic [NUM_INPUTS-1:0] req_i,

    valid_if.source result
);

  result_t result_out;

  always_comb begin
    result.valid = 1'b0;
    result_out   = '0;

    for (int unsigned i = 0; i < NUM_INPUTS; i++) begin
      int unsigned idx;
      idx = (i + PRIORITY_CFG) % NUM_INPUTS;

      if (!result.valid && req_i[idx]) begin
        result.valid = 1'b1;
        result_out.select[idx] = 1'b1;
        result_out.index = IndexWidth'(idx);
      end
    end

    result.payload = result_out;
  end

  `ASSERT_INIT(NumInputsPositive, NUM_INPUTS > 0)
  `ASSERT_INIT(PriorityInRange, PRIORITY_CFG < NUM_INPUTS)

endmodule
