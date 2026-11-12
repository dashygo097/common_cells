`include "cc/register_bank.svh"

module tb_register_bank
  import df_verify_pkg::*;
#(
    parameter int unsigned RANDOM_CYCLES = 1000
) ();
  timeunit 1ns; timeprecision 1ps;

  localparam int unsigned AddrWidth = 16;
  localparam int unsigned DataWidth = 32;
  localparam int unsigned NumRegs   = 5;
  typedef logic [AddrWidth - 1:0] addr_t;
  typedef logic [DataWidth - 1:0] data_t;
  typedef logic [DataWidth / 8 - 1:0] strb_t;
  typedef `CC_REG_BANK_REQ_TYPE(addr_t, data_t, strb_t) req_t;
  typedef `CC_REG_BANK_RESP_TYPE(data_t) resp_t;
  typedef `CC_REG_BANK_CFG_TYPE(addr_t, data_t) reg_cfg_t;

  localparam addr_t BaseAddr = 'h100;
  localparam reg_cfg_t [NumRegs - 1:0] RegCfg = '{
      0: '{
          offset: 'h00,
          reset_value: 'h11223344,
          read_mask: '1,
          rw_mask: '1,
          w1c_mask: '0,
          w1s_mask: '0,
          rc_mask: '0
      },
      1: '{
          offset: 'h04,
          reset_value: 'hA500FF5A,
          read_mask: '1,
          rw_mask: 'h000000FF,
          w1c_mask: 'h0000FF00,
          w1s_mask: 'h00FF0000,
          rc_mask: '0
      },
      2: '{
          offset: 'h08,
          reset_value: 'h89ABCDEF,
          read_mask: 'h00FF00FF,
          rw_mask: '0,
          w1c_mask: '0,
          w1s_mask: '0,
          rc_mask: 'h000000FF
      },
      3: '{
          offset: 'h0C,
          reset_value: '0,
          read_mask: '0,
          rw_mask: '1,
          w1c_mask: '0,
          w1s_mask: '0,
          rc_mask: '0
      },
      4: '{
          offset: 'h10,
          reset_value: 'hCAFEBABE,
          read_mask: '1,
          rw_mask: '0,
          w1c_mask: '0,
          w1s_mask: '0,
          rc_mask: '0
      }
  };

  logic clk_i;
  logic rst_n_i;
  handshake_if #(.payload_t(req_t)) in ();
  handshake_if #(.payload_t(resp_t)) out ();
  data_t model_regs[NumRegs];
  ordered_scoreboard #(resp_t) scoreboard;
  logic pushed_last;
  logic popped_last;
  logic stalled;
  resp_t stalled_response;

  register_bank #(
      .ADDR_WIDTH(AddrWidth),
      .DATA_WIDTH(DataWidth),
      .NUM_REGS(NumRegs),
      .BASE_ADDR(BaseAddr),
      .REG_CFG(RegCfg)
  ) u_dut (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .in(in),
      .out(out)
  );

  always #5ns clk_i = ~clk_i;

  // Model each enabled bit independently of the RTL's vector mask expressions.
  // Only accepted requests invoke this function; reads return the pre-clear value.
  function automatic resp_t reference_access(input req_t request);
    resp_t response;
    response = '{data: '0, error: 1'b1};
    foreach (model_regs[i]) begin
      if (request.addr != BaseAddr + RegCfg[i].offset) continue;
      response.error = 1'b0;
      for (int unsigned b = 0; b < DataWidth; b++) begin
        if (request.write) begin
          if (!request.strb[b/8]) continue;
          if (RegCfg[i].rw_mask[b]) model_regs[i][b] = request.data[b];
          if (RegCfg[i].w1c_mask[b] && request.data[b]) model_regs[i][b] = 1'b0;
          if (RegCfg[i].w1s_mask[b] && request.data[b]) model_regs[i][b] = 1'b1;
        end else begin
          if (RegCfg[i].read_mask[b]) response.data[b] = model_regs[i][b];
          if (RegCfg[i].rc_mask[b]) model_regs[i][b] = 1'b0;
        end
      end
    end
    return response;
  endfunction

  task automatic reset_dut();
    @(negedge clk_i);
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    rst_n_i = 1'b0;
    scoreboard.clear();
    foreach (model_regs[i]) model_regs[i] = RegCfg[i].reset_value;
    pushed_last = 1'b0;
    popped_last = 1'b0;
    stalled = 1'b0;
    stalled_response = '0;
    #1ns;
    check(!out.valid, "Reset must discard a pending response asynchronously");
    wait_cycles(clk_i, 2);
    @(negedge clk_i);
    rst_n_i = 1'b1;
  endtask

  task automatic cycle(input logic valid, input req_t request, input logic ready);
    resp_t expected;
    @(negedge clk_i);
    in.valid   = valid;
    in.payload = request;
    out.ready  = ready;
    #1ns;
    value_check#(logic)::equal(out.valid, scoreboard.pending_count() != 0,
                               "Output validity disagrees with pending responses");
    value_check#(logic)::equal(in.ready, scoreboard.pending_count() == 0 || ready,
                               "Request ready disagrees with response capacity");
    if (stalled) begin
      check(out.valid, "Stalled response lost validity");
      value_check#(resp_t)::equal(out.payload, stalled_response, "Stalled response changed");
    end
    if (out.valid) value_check#(resp_t)::known(out.payload, "Unknown valid response");
    pushed_last = in.valid && in.ready;
    popped_last = out.valid && out.ready;
    stalled = out.valid && !out.ready;
    stalled_response = out.payload;

    @(posedge clk_i);
    // Consume the old response before queuing the newly accepted request.
    if (popped_last) scoreboard.check_actual(out.payload);
    if (pushed_last) begin
      expected = reference_access(request);
      scoreboard.push_expected(expected);
    end
    check(scoreboard.pending_count() <= 1, "Register bank exceeded one pending response");
    #1ns;
    value_check#(logic)::equal(out.valid, scoreboard.pending_count() != 0,
                               "Incorrect registered response validity");
    if (pushed_last)
      value_check#(resp_t)::equal(out.payload, expected, "New response disagrees with model");
    if (stalled)
      value_check#(resp_t)::equal(out.payload, stalled_response,
                                  "Clock edge changed stalled response");
  endtask

  task automatic expect_response(input data_t data, input logic error, input string message);
    resp_t expected;
    expected = '{data: data, error: error};
    check(out.valid, "Expected a registered response");
    value_check#(resp_t)::equal(out.payload, expected, message);
  endtask

  // Complete one directed transaction and check an independently specified result.
  task automatic access (input addr_t address, input logic write, input data_t data,
                         input strb_t strb, input data_t expected_data = '0,
                         input logic expected_error = 1'b0);
    req_t request;
    request = '{addr: address, write: write, data: data, strb: strb};
    cycle(1'b1, request, 1'b1);
    check(pushed_last, "Directed request was not accepted");
    expect_response(expected_data, expected_error, $sformatf(
                    "Directed access: addr=%h write=%b strb=%b", address, write, strb));
    cycle(1'b0, '0, 1'b1);
    scoreboard.check_empty();
  endtask

  task automatic drain_dut();
    cycle(1'b0, '0, 1'b1);
    scoreboard.check_empty();
    check(!out.valid, "Response slot did not drain");
  endtask

  initial begin
    req_t request;
    logic offered_valid;
    longint unsigned comparisons_before;
    int unsigned index;

    clk_i = 1'b0;
    rst_n_i = 1'b0;
    in.valid = 1'b0;
    in.payload = '0;
    out.ready = 1'b0;
    scoreboard = new("register_bank");
    pushed_last = 1'b0;
    popped_last = 1'b0;
    stalled = 1'b0;
    stalled_response = '0;
    check(RANDOM_CYCLES > 0, "RANDOM_CYCLES must be positive");

    // Test 1: Reset values, read masks, and read strobes independent of byte enables.
    reset_dut();
    access ('h100, 1'b0, '0, '0, 'h11223344);
    access ('h104, 1'b0, '0, '1, 'hA500FF5A);
    access ('h108, 1'b0, '0, '0, 'h00AB00EF);
    access ('h10C, 1'b0, '0, '1, '0);
    access ('h110, 1'b0, '0, '0, 'hCAFEBABE);

    // Test 2: RW writes update selected bytes; zero strobes leave the value unchanged.
    reset_dut();
    access ('h100, 1'b1, 'hDEADBEEF, 4'b0101);
    access ('h100, 1'b0, '0, '1, 'h11AD33EF);
    access ('h100, 1'b1, '0, '0);
    access ('h100, 1'b0, '0, '1, 'h11AD33EF);
    for (int unsigned b = 0; b < DataWidth / 8; b++) begin
      access ('h100, 1'b1, '1, strb_t'(1 << b));
    end
    access ('h100, 1'b0, '0, '1, '1);
    access ('h100, 1'b1, '0, '1);
    access ('h100, 1'b0, '0, '1, '0);

    // Test 3: Mixed RW/W1C/W1S fields obey masks, write-one semantics, and byte strobes.
    reset_dut();
    access ('h104, 1'b1, 'h003C0F12, '1);
    access ('h104, 1'b0, '0, '1, 'hA53CF012);
    access ('h104, 1'b1, 'hFFFFFFFF, 4'b0001);
    access ('h104, 1'b0, '0, '1, 'hA53CF0FF);
    access ('h104, 1'b1, 'h0000F000, 4'b0010);
    access ('h104, 1'b0, '0, '1, 'hA53C00FF);
    access ('h104, 1'b1, 'h00030000, 4'b0100);
    access ('h104, 1'b0, '0, '1, 'hA53F00FF);
    access ('h104, 1'b1, '0, 4'b1110);
    access ('h104, 1'b1, '1, '0);
    access ('h104, 1'b0, '0, '1, 'hA53F00FF);

    // Test 4: RO writes acknowledge without changing state; write-only reads return zero.
    reset_dut();
    access ('h110, 1'b1, '0, '1);
    access ('h110, 1'b0, '0, '1, 'hCAFEBABE);
    access ('h10C, 1'b1, 'hDEADBEEF, '1);
    access ('h10C, 1'b0, '0, '1, '0);

    // Test 5: Invalid requests have no effects; RC reads return data before clearing.
    reset_dut();
    request = '{addr: 'h108, write: 1'b0, data: '0, strb: '1};
    repeat (4) cycle(1'b0, request, 1'b1);
    access ('h108, 1'b0, '0, '1, 'h00AB00EF);
    access ('h108, 1'b0, '0, '1, 'h00AB0000);
    request = '{addr: 'h100, write: 1'b1, data: '1, strb: '1};
    repeat (4) cycle(1'b0, request, 1'b1);
    access ('h100, 1'b0, '0, '1, 'h11223344);

    // Test 6: Unmapped and misaligned addresses return errors without aliasing a register.
    reset_dut();
    access ('h180, 1'b0, '0, '1, '0, 1'b1);
    access ('h0FC, 1'b1, '1, '1, '0, 1'b1);
    access ('h114, 1'b1, '1, '1, '0, 1'b1);
    for (int unsigned b = 1; b < DataWidth / 8; b++) begin
      access (BaseAddr + addr_t'(b), 1'b1, '1, '1, '0, 1'b1);
      access (BaseAddr + addr_t'(b), 1'b0, '0, '1, '0, 1'b1);
    end
    access ('h100, 1'b0, '0, '1, 'h11223344);
    access ('h104, 1'b0, '0, '1, 'hA500FF5A);

    // Test 7: Hold a response stable and defer a blocked RC read until acceptance.
    reset_dut();
    cycle(1'b1, '{addr: 'h110, write: 1'b0, data: '0, strb: '1}, 1'b0);
    check(pushed_last && !popped_last, "Empty response slot must accept a request");
    request = '{addr: 'h108, write: 1'b0, data: '0, strb: '1};
    repeat (12) begin
      cycle(1'b1, request, 1'b0);
      check(!pushed_last && !popped_last, "Stalled bank accepted a request or response");
      expect_response('hCAFEBABE, 1'b0, "Blocked request must not overwrite response");
    end
    cycle(1'b1, request, 1'b1);
    check(pushed_last && popped_last, "Response consumption must permit same-cycle acceptance");
    expect_response('h00AB00EF, 1'b0, "Blocked RC request must not clear before acceptance");
    request = '{addr: 'h100, write: 1'b1, data: 'h12345678, strb: '1};
    repeat (8) begin
      cycle(1'b1, request, 1'b0);
      check(!pushed_last, "Blocked write was accepted");
      expect_response('h00AB00EF, 1'b0, "RC response must retain its pre-clear value");
    end
    cycle(1'b1, request, 1'b1);
    check(pushed_last && popped_last, "Blocked write did not resume with the consumer");
    drain_dut();
    access ('h108, 1'b0, '0, '1, 'h00AB0000);
    access ('h100, 1'b0, '0, '1, 'h12345678);

    // Test 8: Sustain one request and response per cycle, including write/read dependencies.
    reset_dut();
    comparisons_before = scoreboard.comparison_count();
    for (int unsigned i = 0; i < 100; i++) begin
      request = '{addr: 'h100, write: (i % 2 == 0), data: data_t'(i), strb: '1};
      cycle(1'b1, request, 1'b1);
      check(pushed_last, "Ready consumer failed to sustain request throughput");
      if (i > 0) check(popped_last, "Bubble in continuous response traffic");
      if (i % 2 == 1) expect_response(data_t'(i - 1), 1'b0, "Read following a write");
    end
    drain_dut();
    check(scoreboard.comparison_count() - comparisons_before == 100,
          "Throughput test did not return all 100 responses");

    // Test 9: Reset modified registers and discard a stalled pending response.
    access ('h104, 1'b1, '1, '1);
    access ('h108, 1'b0, '0, '1, 'h00AB00EF);
    cycle(1'b1, '{addr: 'h100, write: 1'b1, data: '1, strb: '1}, 1'b0);
    check(out.valid, "Reset test must have a pending response");
    reset_dut();
    drain_dut();
    access ('h100, 1'b0, '0, '1, 'h11223344);
    access ('h104, 1'b0, '0, '1, 'hA500FF5A);
    access ('h108, 1'b0, '0, '1, 'h00AB00EF);

    // Test 10: Random reads/writes, byte strobes, misses, idle cycles, and backpressure.
    reset_dut();
    request = '0;
    offered_valid = 1'b0;
    repeat (RANDOM_CYCLES) begin
      if (!offered_valid || pushed_last) begin
        offered_valid = ($urandom_range(0, 3) != 0);
        index = $urandom_range(0, NumRegs - 1);
        request.addr = BaseAddr + RegCfg[index].offset;
        case ($urandom_range(
            0, 7
        ))
          0: request.addr += addr_t'($urandom_range(1, 3));
          1: request.addr = 'h180;
          default: ;
        endcase
        request.write = 1'($urandom);
        request.data  = data_t'($urandom);
        request.strb  = strb_t'($urandom);
      end
      cycle(offered_valid, request, 1'($urandom));
    end
    // Complete a still-offered request before withdrawing valid to drain.
    if (offered_valid && !pushed_last) begin
      cycle(1'b1, request, 1'b1);
      check(pushed_last, "Pending request did not complete after backpressure release");
    end
    drain_dut();

    // Check every final readable register against the model after randomized writes.
    foreach (model_regs[i]) begin
      cycle(1'b1, '{addr: BaseAddr + RegCfg[i].offset, write: 1'b0, data: '0, strb: '1}, 1'b1);
    end
    drain_dut();
    finish_test();
  end

endmodule
