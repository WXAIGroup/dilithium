// =============================================================================
// File:        shake128.sv
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Module:      shake128_absorb_once / shake128_squeezeblocks
// Description: SHAKE128 extendable-output function (FIPS 202).
//
//              Provides the two SHAKE128 operations used in Dilithium:
//                1. shake128_absorb_once(state, in, inlen)
//                   Initialize state to zero, absorb inlen bytes, apply
//                   SHAKE padding (0x1F at end of last block, 0x80 at end
//                   of rate).
//                2. shake128_squeezeblocks(out, nblocks, state)
//                   Squeeze nblocks * 168 bytes by running the Keccak
//                   permutation once per block.
//
//              Both modules wrap the keccak_permutation core.
//
// Author:      Generated for Dilithium HW IP Core
// Date:        2026-06-23
// Version:     1.0 (Phase 1: Core Arithmetic Units)
//
// Compliance:  IEEE 1800-2017 SystemVerilog, synthesizable.
// =============================================================================

`ifndef DILITHIUM_SHAKE128_SV
`define DILITHIUM_SHAKE128_SV

`include "dilithium_pkg.sv"
`include "keccak_constants.svh"


// =============================================================================
// Module: shake128_absorb_once
// =============================================================================
module shake128_absorb_once #(
    parameter int unsigned MAX_INPUT_BYTES = 1024
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    start,
    input  logic [7:0]              in_data [MAX_INPUT_BYTES],
    input  logic [15:0]             in_len,
    output logic                    done,
    output logic [1599:0]           state_out,
    output logic                    err
);

  localparam int unsigned RATE_BYTES = 168;
  localparam int unsigned RATE_LANES = RATE_BYTES / 8;
  localparam logic [7:0]   PAD_BYTE  = 8'h1F;
  localparam int unsigned LANE_W     = 64;
  localparam int unsigned N_LANES    = 25;

  typedef logic [LANE_W-1:0] lane_t;
  typedef lane_t             state_t [N_LANES];

  typedef enum logic [2:0] {
    S_IDLE,
    S_INIT,
    S_ABSORB,
    S_PERMUTE,
    S_FINALIZE,
    S_DONE
  } state_e;

  state_e        state, state_next;
  logic [15:0]   byte_idx,    byte_idx_next;
  logic [15:0]   in_len_r,    in_len_r_next;
  state_t        s_reg,       s_next;
  logic          perm_start;
  logic          perm_busy;
  logic          perm_done;
  logic [1599:0] perm_in;
  logic [1599:0] perm_out;
  logic          err_next;

  keccak_permutation #(.ROUNDS(24)) u_perm (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (perm_start),
    .busy      (perm_busy),
    .done      (perm_done),
    .state_in  (perm_in),
    .state_out (perm_out)
  );

  function automatic state_t unpack(input logic [1599:0] v);
    state_t s;
    for (int i = 0; i < N_LANES; i++) s[i] = v[((i+1)*LANE_W) - 1 -: LANE_W];
    return s;
  endfunction
  function automatic logic [1599:0] pack(input state_t s);
    logic [1599:0] v;
    for (int i = 0; i < N_LANES; i++) v[((i+1)*LANE_W) - 1 -: LANE_W] = s[i];
    return v;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      byte_idx    <= '0;
      in_len_r    <= '0;
      s_reg       <= '{default: '0};
      perm_start  <= 1'b0;
      done        <= 1'b0;
      err         <= 1'b0;
    end else begin
      done        <= 1'b0;
      perm_start  <= 1'b0;
      state       <= state_next;
      byte_idx    <= byte_idx_next;
      in_len_r    <= in_len_r_next;
      s_reg       <= s_next;
      err         <= err_next;
    end
  end

  always_comb begin
    state_next    = state;
    byte_idx_next = byte_idx;
    in_len_r_next = in_len_r;
    s_next        = s_reg;
    perm_start    = 1'b0;
    err_next      = err;

    case (state)
      S_IDLE: begin
        if (start) begin
          if (in_len > MAX_INPUT_BYTES) begin
            err_next   = 1'b1;
            state_next = S_DONE;
          end else begin
            state_next = S_INIT;
          end
        end
      end

      S_INIT: begin
        s_next        = '{default: '0};
        in_len_r_next = in_len;
        byte_idx_next = '0;
        state_next    = S_ABSORB;
      end

      S_ABSORB: begin
        if (byte_idx < in_len_r) begin
          int unsigned pos = byte_idx;
          int unsigned li  = pos / 8;
          int unsigned bi  = pos % 8;
          s_next = s_reg;
          s_next[li][bi*8 +: 8] = s_reg[li][bi*8 +: 8] ^ in_data[byte_idx];
          byte_idx_next = byte_idx + 1;
          if (byte_idx + 1 == in_len_r) begin
            state_next = S_FINALIZE;
          end else if ((byte_idx + 1) % RATE_BYTES == 0) begin
            state_next = S_PERMUTE;
          end else begin
            state_next = S_ABSORB;
          end
        end else begin
          state_next = S_FINALIZE;
        end
      end

      S_PERMUTE: begin
        perm_start = 1'b1;
        perm_in    = pack(s_reg);
        if (perm_done) begin
          s_next     = unpack(perm_out);
          state_next = S_ABSORB;
        end
      end

      S_FINALIZE: begin
        s_next = s_reg;
        s_next[0][0 +: 8]      = s_reg[0][0 +: 8] ^ PAD_BYTE;
        s_next[RATE_LANES][63] = s_reg[RATE_LANES][63] ^ 1'b1;
        state_next = S_PERMUTE;
        in_len_r_next = '0;
      end

      S_DONE: begin
        done = 1'b1;
        if (!start) state_next = S_IDLE;
      end

      default: state_next = S_IDLE;
    endcase
  end

  assign state_out = pack(s_reg);

endmodule


// =============================================================================
// Module: shake128_squeezeblocks
// =============================================================================
module shake128_squeezeblocks #(
    parameter int unsigned MAX_BLOCKS = 64
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    start,
    input  logic [1599:0]           state_in,
    input  logic [15:0]             nblocks,
    output logic                    done,
    output logic [7:0]              out_data [MAX_BLOCKS*168],
    output logic                    err
);

  localparam int unsigned RATE_BYTES = 168;
  localparam int unsigned RATE_LANES = 21;
  localparam int unsigned LANE_W     = 64;
  localparam int unsigned N_LANES    = 25;

  typedef logic [LANE_W-1:0] lane_t;
  typedef lane_t             state_t [N_LANES];

  typedef enum logic [1:0] {
    S_IDLE,
    S_PERMUTE,
    S_NEXT,
    S_DONE
  } state_e;

  state_e        state, state_next;
  logic [15:0]   block_idx, block_idx_next;
  state_t        s_reg, s_next;
  logic          perm_start;
  logic          perm_busy;
  logic          perm_done;
  logic [1599:0] perm_in;
  logic [1599:0] perm_out;
  logic          err_next;

  keccak_permutation #(.ROUNDS(24)) u_perm (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (perm_start),
    .busy      (perm_busy),
    .done      (perm_done),
    .state_in  (perm_in),
    .state_out (perm_out)
  );

  function automatic state_t unpack(input logic [1599:0] v);
    state_t s;
    for (int i = 0; i < N_LANES; i++) s[i] = v[((i+1)*LANE_W) - 1 -: LANE_W];
    return s;
  endfunction
  function automatic logic [1599:0] pack(input state_t s);
    logic [1599:0] v;
    for (int i = 0; i < N_LANES; i++) v[((i+1)*LANE_W) - 1 -: LANE_W] = s[i];
    return v;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      block_idx   <= '0;
      s_reg       <= '{default: '0};
      perm_start  <= 1'b0;
      done        <= 1'b0;
      err         <= 1'b0;
    end else begin
      done       <= 1'b0;
      perm_start <= 1'b0;
      state      <= state_next;
      block_idx  <= block_idx_next;
      s_reg      <= s_next;
      err        <= err_next;
    end
  end

  always_comb begin
    state_next     = state;
    block_idx_next = block_idx;
    s_next         = s_reg;
    perm_start     = 1'b0;
    err_next       = err;

    case (state)
      S_IDLE: begin
        if (start) begin
          if (nblocks > MAX_BLOCKS) begin
            err_next   = 1'b1;
            state_next = S_DONE;
          end else if (nblocks == 0) begin
            state_next = S_DONE;
          end else begin
            s_next         = unpack(state_in);
            block_idx_next = '0;
            state_next     = S_PERMUTE;
          end
        end
      end

      S_PERMUTE: begin
        perm_start = 1'b1;
        perm_in    = pack(s_reg);
        if (perm_done) begin
          s_next     = unpack(perm_out);
          state_next = S_NEXT;
        end
      end

      S_NEXT: begin
        block_idx_next = block_idx + 1;
        if (block_idx + 1 >= nblocks) begin
          state_next = S_DONE;
        end else begin
          state_next = S_PERMUTE;
        end
      end

      S_DONE: begin
        done = 1'b1;
        if (!start) state_next = S_IDLE;
      end

      default: state_next = S_IDLE;
    endcase
  end

  always_comb begin
    for (int b = 0; b < MAX_BLOCKS; b++) begin
      for (int i = 0; i < RATE_LANES; i++) begin
        for (int j = 0; j < 8; j++) begin
          out_data[b * RATE_BYTES + i*8 + j] = s_reg[i][j*8 +: 8];
        end
      end
    end
  end

endmodule

`endif // DILITHIUM_SHAKE128_SV
