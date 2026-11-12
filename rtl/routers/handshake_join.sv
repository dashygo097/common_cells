`include "cc/assertions.svh"

module handshake_join #(
    parameter int unsigned NUM_INPUTS = 2
) (
    input  logic [NUM_INPUTS - 1:0] valid_i,
    output logic [NUM_INPUTS - 1:0] ready_o,

    output logic valid_o,
    input  logic ready_i
);

  always_comb begin
    valid_o = &valid_i;
    ready_o = {NUM_INPUTS{valid_o && ready_i}};
  end

  `CC_ASSERT_INIT(NumInputsPositive, NUM_INPUTS > 0)
endmodule
