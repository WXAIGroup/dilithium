// =============================================================================
// File:        keccak_constants.svh
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Module:      keccak_constants (include header)
// Description: Keccak-p[1600] round constants.
//              These 24 constants are XORed into the state during the Iota
//              step of each round. Values are exactly those from the FIPS 202
//              reference and the C reference implementation in ref/fips202.c.
//
// Usage:       `include "keccak_constants.svh"
//
// Author:      Generated for Dilithium HW IP Core
// Date:        2026-06-23
// Version:     1.0 (Phase 1: Core Arithmetic Units)
//
// Compliance:  IEEE 1800-2017 SystemVerilog
// =============================================================================

`ifndef DILITHIUM_KECCAK_CONSTANTS_SVH
`define DILITHIUM_KECCAK_CONSTANTS_SVH

// 64-bit round constants for Keccak-p[1600]
// Index = round number (0..23)
localparam logic [63:0] KECCAK_RC [24] = '{
  64'h0000_0000_0000_0001,
  64'h0000_0000_0000_8082,
  64'h8000_0000_0000_808a,
  64'h8000_0000_8000_8000,
  64'h0000_0000_0000_808b,
  64'h0000_0000_8000_0001,
  64'h8000_0000_8000_8081,
  64'h8000_0000_0000_8009,
  64'h0000_0000_0000_008a,
  64'h0000_0000_0000_0088,
  64'h0000_0000_8000_8009,
  64'h0000_0000_8000_000a,
  64'h0000_0000_8000_808b,
  64'h8000_0000_0000_008b,
  64'h8000_0000_0000_8089,
  64'h8000_0000_0000_8003,
  64'h8000_0000_0000_8002,
  64'h8000_0000_0000_0080,
  64'h0000_0000_0000_800a,
  64'h8000_0000_8000_000a,
  64'h8000_0000_8000_8081,
  64'h8000_0000_0000_8080,
  64'h0000_0000_8000_0001,
  64'h8000_0000_8000_8008
};

// Rotation offsets used in the Rho step of Keccak-p[1600].
// These are the lane-wise rotation offsets indexed by (x, y) where the lane
// index is 5*y + x. Index 0 corresponds to lane (0, 0).
//
// This array is provided for reference; the actual rotation offsets are
// hard-coded inside keccak_permutation.sv to match the C reference.
localparam logic [5:0] KECCAK_RHO_OFFSETS [25] = '{
  6'd0,   // (0,0)
  6'd1,   // (1,0) -> 36 in some references, but C ref uses 1
  6'd62,  // (2,0)
  6'd28,  // (3,0)
  6'd27,  // (4,0)
  6'd36,  // (0,1)
  6'd44,  // (1,1)
  6'd6,   // (2,1)
  6'd55,  // (3,1)
  6'd20,  // (4,1)
  6'd3,   // (0,2)
  6'd10,  // (1,2)
  6'd43,  // (2,2)
  6'd25,  // (3,2)
  6'd39,  // (4,2)
  6'd41,  // (0,3)
  6'd45,  // (1,3)
  6'd15,  // (2,3)
  6'd21,  // (3,3)
  6'd8,   // (4,3)
  6'd18,  // (0,4)
  6'd2,   // (1,4)
  6'd61,  // (2,4)
  6'd56,  // (3,4)
  6'd14   // (4,4)
};

`endif // DILITHIUM_KECCAK_CONSTANTS_SVH
