interface handshake_if #(
    parameter type payload_t = logic
);

  logic valid;
  logic ready;
  payload_t payload;

  modport sink(input valid, payload, output ready);
  modport source(input ready, output valid, payload);
  modport monitor(input valid, ready, payload);

endinterface
