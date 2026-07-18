// =============================================================================
// File:        keccak_permutation.sv
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Module:      keccak_permutation
// Description: Keccak-p[1600] permutation core (FIPS 202 / FIPS 204).
//
//              Implements the 24-round Keccak-f[1600] permutation used by
//              SHA3-256/512, SHAKE128, and SHAKE256. Bit-exact with the
//              KeccakF1600_StatePermute() function in ref/fips202.c.
//
//              Latency: 24 cycles, one round per cycle.
//              Interface:
//                start    : pulse to begin a permutation
//                busy     : high while processing
//                done     : 1-cycle pulse when permutation completes
//                state_in : 1600-bit input state (little-endian lanes)
//                state_out: 1600-bit output state, valid with done
//
// Author:      Generated for Dilithium HW IP Core
// Date:        2026-06-23
// Version:     1.0 (Phase 1: Core Arithmetic Units)
//
// Compliance:  IEEE 1800-2017 SystemVerilog, synthesizable.
// =============================================================================

`ifndef DILITHIUM_KECCAK_PERMUTATION_SV
`define DILITHIUM_KECCAK_PERMUTATION_SV

`include "dilithium_pkg.sv"
`include "keccak_constants.svh"

module keccak_permutation #(
    parameter int unsigned ROUNDS = 24
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    output logic          busy,
    output logic          done,
    input  logic [1599:0] state_in,
    output logic [1599:0] state_out
);

  // ---------------------------------------------------------------------------
  // Lane and state types
  // ---------------------------------------------------------------------------
  localparam int unsigned LANE_W = 64;
  typedef logic [LANE_W-1:0] lane_t;

  // State: array of 25 lanes, indexed as state[5*y + x] (matches C ref).
  typedef lane_t state_t [25];

  localparam int unsigned CNT_W = $clog2(ROUNDS + 1);

  // ---------------------------------------------------------------------------
  // Registers
  // ---------------------------------------------------------------------------
  state_t            s_reg;      // Working state
  logic [CNT_W-1:0]  round_cnt;
  logic              running;

  // Combinational next-state signals
  state_t            s_next;
  logic [CNT_W-1:0]  round_next;
  logic              running_next;
  logic              done_pulse;

  // ---------------------------------------------------------------------------
  // Unpack input state (little-endian lane 0 in low bits)
  // ---------------------------------------------------------------------------
  state_t s_in_unpacked;
  always_comb begin
    for (int i = 0; i < 25; i++) begin
      s_in_unpacked[i] = state_in[((i+1)*LANE_W) - 1 -: LANE_W];
    end
  end

  // ---------------------------------------------------------------------------
  // Combinational Keccak round: compute next state from current state and
  // round constant. Implements all 5 steps (theta, rho, pi, chi, iota) in
  // their fused form, exactly matching ref/fips202.c.
  // ---------------------------------------------------------------------------
  function automatic state_t keccak_round_fn(input state_t A, input logic [63:0] rc);
    state_t E;
    logic [63:0] Aba, Abe, Abi, Abo, Abu;
    logic [63:0] Aga, Age, Agi, Ago, Agu;
    logic [63:0] Aka, Ake, Aki, Ako, Aku;
    logic [63:0] Ama, Ame, Ami, Amo, Amu;
    logic [63:0] Asa, Ase, Asi, Aso, Asu;
    logic [63:0] BCa, BCe, BCi, BCo, BCu;
    logic [63:0] Da,  De,  Di,  Do,  Du;
    logic [63:0] Eba, Ebe, Ebi, Ebo, Ebu;
    logic [63:0] Ega, Ege, Egi, Ego, Egu;
    logic [63:0] Eka, Eke, Eki, Eko, Eku;
    logic [63:0] Ema, Eme, Emi, Emo, Emu;
    logic [63:0] Esa, Ese, Esi, Eso, Esu;

    // Unpack: lane (x, y) is at index 5*y + x
    Aba = A[ 0]; Abe = A[ 1]; Abi = A[ 2]; Abo = A[ 3]; Abu = A[ 4];
    Aga = A[ 5]; Age = A[ 6]; Agi = A[ 7]; Ago = A[ 8]; Agu = A[ 9];
    Aka = A[10]; Ake = A[11]; Aki = A[12]; Ako = A[13]; Aku = A[14];
    Ama = A[15]; Ame = A[16]; Ami = A[17]; Amo = A[18]; Amu = A[19];
    Asa = A[20]; Ase = A[21]; Asi = A[22]; Aso = A[23]; Asu = A[24];

    // --- Theta: column parity ---------------------------------------------
    BCa = Aba ^ Aga ^ Aka ^ Ama ^ Asa;
    BCe = Abe ^ Age ^ Ake ^ Ame ^ Ase;
    BCi = Abi ^ Agi ^ Aki ^ Ami ^ Asi;
    BCo = Abo ^ Ago ^ Ako ^ Amo ^ Aso;
    BCu = Abu ^ Agu ^ Aku ^ Amu ^ Asu;

    // --- Theta D + Rho + Pi + Chi + Iota ----------------------------------
    Da = BCu ^ {BCe[0], BCe[63:1]};
    De = BCa ^ {BCi[0], BCi[63:1]};
    Di = BCe ^ {BCo[0], BCo[63:1]};
    Do = BCi ^ {BCu[0], BCu[63:1]};
    Du = BCo ^ {BCa[0], BCa[63:1]};

    // First plane (Eba..Ebu)
    // Chi: E[i] = BC[i] ^ (~BC[(i+1) mod 5] & BC[(i+2) mod 5])
    //   i=0: BCa ^ (n(BCe) & BCi) = (Aba^Da) ^ (n(ROL(Age^De, 44)) & ROL(Aki^Di, 43))
    Eba = (Aba ^ Da) ^ ((~((Age ^ De) <<< 44)) &  ((Aki ^ Di) <<< 43));
    Eba = Eba ^ rc;  // Iota
    Ebe = ((Age ^ De) <<< 44) ^ ((~((Aki ^ Di) <<< 43)) & ((Amo ^ Do) <<< 21));
    Ebi = ((Aki ^ Di) <<< 43) ^ ((~((Amo ^ Do) <<< 21)) & ((Asu ^ Du) <<< 14));
    Ebo = ((Amo ^ Do) <<< 21) ^ ((~((Asu ^ Du) <<< 14)) &  (Aba ^ Da));
    Ebu = ((Asu ^ Du) <<< 14) ^ ((~(Aba ^ Da)) & ((Age ^ De) <<< 44));

    // Second plane (Ega..Egu)
    Ega = ((Abo ^ Do) <<< 28) ^ ((~((Agu ^ Du) <<< 20)) & ((Aka ^ Da) <<< 3));
    Ege = ((Agu ^ Du) <<< 20) ^ ((~((Aka ^ Da) <<< 3))  & ((Ame ^ De) <<< 45));
    Egi = ((Aka ^ Da) <<< 3)  ^ ((~((Ame ^ De) <<< 45)) & ((Asi ^ Di) <<< 61));
    Ego = ((Ame ^ De) <<< 45) ^ ((~((Asi ^ Di) <<< 61)) & ((Abo ^ Do) <<< 28));
    Egu = ((Asi ^ Di) <<< 61) ^ ((~((Abo ^ Do) <<< 28)) & ((Agu ^ Du) <<< 20));

    // Third plane (Eka..Eku)
    Eka = ((Abe ^ De) <<< 1)  ^ ((~((Agi ^ Di) <<< 6))  & ((Ako ^ Do) <<< 25));
    Eke = ((Agi ^ Di) <<< 6)  ^ ((~((Ako ^ Do) <<< 25)) & ((Amu ^ Du) <<< 8));
    Eki = ((Ako ^ Do) <<< 25) ^ ((~((Amu ^ Du) <<< 8))  & ((Asa ^ Da) <<< 18));
    Eko = ((Amu ^ Du) <<< 8)  ^ ((~((Asa ^ Da) <<< 18)) & ((Abe ^ De) <<< 1));
    Eku = ((Asa ^ Da) <<< 18) ^ ((~((Abe ^ De) <<< 1))  & ((Agi ^ Di) <<< 6));

    // Fourth plane (Ema..Emu)
    Ema = ((Abu ^ Du) <<< 27) ^ ((~((Aga ^ Da) <<< 36)) & ((Ake ^ De) <<< 10));
    Eme = ((Aga ^ Da) <<< 36) ^ ((~((Ake ^ De) <<< 10)) & ((Ami ^ Di) <<< 15));
    Emi = ((Ake ^ De) <<< 10) ^ ((~((Ami ^ Di) <<< 15)) & ((Aso ^ Do) <<< 56));
    Emo = ((Ami ^ Di) <<< 15) ^ ((~((Aso ^ Do) <<< 56)) & ((Abu ^ Du) <<< 27));
    Emu = ((Aso ^ Do) <<< 56) ^ ((~((Abu ^ Du) <<< 27)) & ((Aga ^ Da) <<< 36));

    // Fifth plane (Esa..Esu)
    Esa = ((Abi ^ Di) <<< 62) ^ ((~((Ago ^ Do) <<< 55)) & ((Aku ^ Du) <<< 39));
    Ese = ((Ago ^ Do) <<< 55) ^ ((~((Aku ^ Du) <<< 39)) & ((Ama ^ Da) <<< 41));
    Esi = ((Aku ^ Du) <<< 39) ^ ((~((Ama ^ Da) <<< 41)) & ((Ase ^ De) <<< 2));
    Eso = ((Ama ^ Da) <<< 41) ^ ((~((Ase ^ De) <<< 2))  & ((Abi ^ Di) <<< 62));
    Esu = ((Ase ^ De) <<< 2)  ^ ((~((Abi ^ Di) <<< 62)) & ((Ago ^ Do) <<< 55));

    // Pack output
    E[ 0] = Eba; E[ 1] = Ebe; E[ 2] = Ebi; E[ 3] = Ebo; E[ 4] = Ebu;
    E[ 5] = Ega; E[ 6] = Ege; E[ 7] = Egi; E[ 8] = Ego; E[ 9] = Egu;
    E[10] = Eka; E[11] = Eke; E[12] = Eki; E[13] = Eko; E[14] = Eku;
    E[15] = Ema; E[16] = Eme; E[17] = Emi; E[18] = Emo; E[19] = Emu;
    E[20] = Esa; E[21] = Ese; E[22] = Esi; E[23] = Eso; E[24] = Esu;
    return E;
  endfunction

  // ---------------------------------------------------------------------------
  // Next-state computation
  // ---------------------------------------------------------------------------
  always_comb begin
    if (!running) begin
      s_next      = s_in_unpacked;
      round_next  = '0;
      running_next = start;
      done_pulse  = 1'b0;
    end else begin
      s_next      = keccak_round_fn(s_reg, KECCAK_RC[round_cnt]);
      round_next  = round_cnt + 1'b1;
      running_next = (round_cnt + 1'b1) != ROUNDS;
      done_pulse  = ((round_cnt + 1'b1) == ROUNDS);
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential update
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      running   <= 1'b0;
      round_cnt <= '0;
      s_reg     <= '{default: '0};
    end else begin
      running   <= running_next;
      round_cnt <= round_next;
      s_reg     <= s_next;
    end
  end

  // ---------------------------------------------------------------------------
  // Output mapping
  // ---------------------------------------------------------------------------
  assign busy      = running;
  assign done      = done_pulse;
  always_comb begin
    for (int i = 0; i < 25; i++) begin
      state_out[((i+1)*LANE_W) - 1 -: LANE_W] = s_reg[i];
    end
  end

endmodule

`endif // DILITHIUM_KECCAK_PERMUTATION_SV
