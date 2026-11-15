`include "cc/assertions.svh"
`include "cc/registers.svh"
`include "cc/register_bank.svh"

module register_bank #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned NUM_REGS   = 1,

    localparam type addr_t = logic [ADDR_WIDTH - 1:0],
    localparam type data_t = logic [DATA_WIDTH - 1:0],
    localparam type strb_t = logic [DATA_WIDTH / 8 - 1:0],

    // FIXME: DC compatibility: C'mon i have to do this otherwise it raises
    // ELAB-210: integer overflow.
    // original impl is typed: parameter reg_cfg_t [NUM_REGS - 1: 0] REG_CFG
    parameter logic [ADDR_WIDTH - 1:0] BASE_ADDR = '0,

    parameter logic [NUM_REGS - 1:0][ADDR_WIDTH - 1:0] OFFSET_CFG = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] RESET_CFG  = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] READ_CFG   = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] RW_CFG     = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] W1C_CFG    = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] W1S_CFG    = '0,
    parameter logic [NUM_REGS - 1:0][DATA_WIDTH - 1:0] RC_CFG     = '0,

    localparam type req_t  = `CC_REG_BANK_REQ_TYPE(addr_t, data_t, strb_t),
    localparam type resp_t = `CC_REG_BANK_RESP_TYPE(data_t)
) (
    input logic clk_i,
    input logic rst_n_i,

    handshake_if.sink   in,
    handshake_if.source out
);
  localparam int unsigned BytesPerReg = DATA_WIDTH >= 8 ? DATA_WIDTH / 8 : 1;
  localparam int unsigned CalcWidth   = (ADDR_WIDTH > 32 ? ADDR_WIDTH : 32) + 2;

  typedef logic [CalcWidth - 1:0] calc_addr_t;

  localparam calc_addr_t AddressLimit = calc_addr_t'(1) << ADDR_WIDTH;

  req_t request;
  resp_t response_d;
  resp_t response_r;

  logic response_valid_r;
  logic access_fire;
  logic [NUM_REGS - 1:0] selected;

  data_t [NUM_REGS - 1:0] registers_r;
  data_t byte_mask;
  data_t read_data;

  always_comb begin
    request = req_t'(in.payload);
  end

  always_comb begin
    in.ready = !response_valid_r || out.ready;
    access_fire = in.valid && in.ready;
    out.valid = response_valid_r;
    out.payload = response_r;

    for (int unsigned b = 0; b < DATA_WIDTH / 8; b++) begin
      byte_mask[b*8+:8] = {8{request.strb[b]}};
    end

    read_data = '0;
    for (int unsigned i = 0; i < NUM_REGS; i++) begin
      if (selected[i] && !request.write) begin
        read_data = registers_r[i] & READ_CFG[i];
      end
    end

    response_d = '{data: read_data, error: !(|selected), default: '0};
  end

  `REG_CE_ARSTN(response_valid_r, in.valid, in.ready, 1'b0)
  `REG_CE(response_r, response_d, access_fire)

  for (genvar i = 0; i < NUM_REGS; i++) begin : gen_register
    localparam addr_t RegAddress = BASE_ADDR + OFFSET_CFG[i];
    localparam calc_addr_t RegEnd = calc_addr_t'(BASE_ADDR) +
        calc_addr_t'(OFFSET_CFG[i]) + calc_addr_t'(BytesPerReg);

    data_t next_value;

    always_comb begin
      selected[i] = (request.addr == RegAddress);
    end

    always_comb begin
      if (request.write) begin
        // spyglass disable_block W415a
        next_value = (registers_r[i] & ~(RW_CFG[i] & byte_mask)) |
            (request.data & RW_CFG[i] & byte_mask);
        next_value &= ~(request.data & W1C_CFG[i] & byte_mask);
        next_value |= request.data & W1S_CFG[i] & byte_mask;
        // spyglass enable_block W415a
      end else begin
        next_value = registers_r[i] & ~RC_CFG[i];
      end
    end

    `REG_CE_ARSTN(registers_r[i], next_value, access_fire && selected[i], RESET_CFG[i])

    `ASSERT_INIT(
        ConfigKnown, !$isunknown(
        {OFFSET_CFG[i], RESET_CFG[i], READ_CFG[i], RW_CFG[i], W1C_CFG[i], W1S_CFG[i], RC_CFG[i]}))

    `ASSERT_INIT(OffsetAligned, calc_addr_t'(OFFSET_CFG[i]) % calc_addr_t'(BytesPerReg) == 0)
    `ASSERT_INIT(AddressInRange, RegEnd <= AddressLimit)
    `ASSERT_INIT(RwW1cDisjoint, (RW_CFG[i] & W1C_CFG[i]) == '0)
    `ASSERT_INIT(RwW1sDisjoint, (RW_CFG[i] & W1S_CFG[i]) == '0)
    `ASSERT_INIT(W1cW1sDisjoint, (W1C_CFG[i] & W1S_CFG[i]) == '0)
    `ASSERT_INIT(ReadClearReadable, (RC_CFG[i] & ~READ_CFG[i]) == '0)

    for (genvar j = i + 1; j < NUM_REGS; j++) begin : gen_check_unique
      `ASSERT_INIT(OffsetsUnique, OFFSET_CFG[i] != OFFSET_CFG[j])
    end

  end

  `ASSERT_INIT(AddressWidthPositive, ADDR_WIDTH > 0)
  `ASSERT_INIT(DataWidthValid, DATA_WIDTH > 0 && DATA_WIDTH % 8 == 0)
  `ASSERT_INIT(RegisterCountPositive, NUM_REGS > 0)
  `ASSERT_INIT(BaseAligned, calc_addr_t'(BASE_ADDR) % calc_addr_t'(BytesPerReg) == 0)
  `ASSERT_INIT(InputPayloadWidth, $bits(in.payload) == $bits(req_t))
  `ASSERT_INIT(OutputPayloadWidth, $bits(out.payload) == $bits(resp_t))
  `ASSERT(OutputStable, out.valid && !out.ready |=> out.valid && $stable(out.payload))
  `ASSERT_KNOWN_IF(ResponseKnown, out.payload, out.valid)

endmodule
