interface valid_if #(
    parameter type payload_t = logic
);

  logic valid;
  payload_t payload;

  modport sink(input valid, payload);
  modport source(output valid, payload);
  modport monitor(input valid, payload);

endinterface
