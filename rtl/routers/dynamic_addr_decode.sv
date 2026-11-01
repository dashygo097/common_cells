module dynamic_addr_decode #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_IDS = 1,
    // NOTE: Manually overriding parameters below when instantiation is not recommended
    parameter int unsigned ID_WIDTH = $clog2(NUM_IDS),
    parameter type addr_t = logic [ADDR_WIDTH - 1:0],
    parameter type id_t = logic [ID_WIDTH - 1:0],
    // verilog_lint: waive typedef-structs-unions
    parameter type addr_range_t = struct packed {
      logic [ID_WIDTH - 1:0]   id;
      logic [ADDR_WIDTH - 1:0] addr_start;
      logic [ADDR_WIDTH - 1:0] addr_end;
    }
) (
    input logic clk_i,
    input logic rst_n_i,

    input addr_t addr_i,
    input addr_range_t [NUM_IDS - 1:0] addr_map_i
);

endmodule
