// =============================================================================
// File:        dilithium_pkg.sv
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Module:      dilithium_pkg (package)
// Description: Common types, parameters, enums and constants for the
//              FIPS 204 (Dilithium) SystemVerilog hardware implementation.
//              All values match the C reference in /ref/ (pqcrystals).
//
// Author:      Generated for Dilithium HW IP Core
// Date:        2026-06-23
// Version:     1.0 (Phase 1: Core Arithmetic Units)
//
// Compliance:  IEEE 1800-2017 SystemVerilog
//              No vendor-specific constructs. Synthesizable.
// =============================================================================

`ifndef DILITHIUM_PKG_SV
`define DILITHIUM_PKG_SV

package dilithium_pkg;

  // ---------------------------------------------------------------------------
  // Compile-time interface selection
  // ---------------------------------------------------------------------------
  // Exactly one of these should be defined before compilation:
  //   `define DILITHIUM_SPI_INTERFACE
  //   `define DILITHIUM_AXI_INTERFACE
  // If neither is defined, the design defaults to APB-like register access.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Algorithm constants (from ref/params.h)
  // ---------------------------------------------------------------------------
  localparam int unsigned N              = 256;     // Polynomial degree
  localparam int unsigned Q              = 8380417; // Modulus (q)
  localparam int unsigned D_PARAM        = 13;      // Power-of-two round bits
  localparam int unsigned ROOT_OF_UNITY  = 1753;    // Primitive 512-th root of unity mod Q
  localparam int unsigned MONT           = -4186625;// 2^32 mod Q
  localparam int unsigned QINV           = 58728449;// Q^(-1) mod 2^32

  // Derived constants
  localparam int unsigned POLY_BYTES     = N * 3;   // 768 (packed 24-bit per coeff)
  localparam int unsigned POLY_WORDS     = N;       // 32-bit aligned words
  localparam int unsigned NTT_LATENCY    = 8 * 8 + 1; // 8 stages x (N/2) butterflies + 1

  // ---------------------------------------------------------------------------
  // Mode-dependent parameter sets
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    MODE_DILITHIUM2 = 2'b00,
    MODE_DILITHIUM3 = 2'b01,
    MODE_DILITHIUM5 = 2'b10
  } dilithium_mode_t;

  // Operation request
  typedef enum logic [1:0] {
    OP_IDLE  = 2'b00,
    OP_KEYGEN = 2'b01,
    OP_SIGN   = 2'b10,
    OP_VERIFY = 2'b11
  } dilithium_op_t;

  // ---------------------------------------------------------------------------
  // Parameter set accessor functions (purely combinational)
  // ---------------------------------------------------------------------------
  function automatic int unsigned get_K(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 4;
      MODE_DILITHIUM3: return 6;
      MODE_DILITHIUM5: return 8;
      default:         return 4;
    endcase
  endfunction

  function automatic int unsigned get_L(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 4;
      MODE_DILITHIUM3: return 5;
      MODE_DILITHIUM5: return 7;
      default:         return 4;
    endcase
  endfunction

  function automatic int unsigned get_eta(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 2;
      MODE_DILITHIUM3: return 4;
      MODE_DILITHIUM5: return 2;
      default:         return 2;
    endcase
  endfunction

  function automatic int unsigned get_tau(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 39;
      MODE_DILITHIUM3: return 49;
      MODE_DILITHIUM5: return 60;
      default:         return 39;
    endcase
  endfunction

  function automatic int unsigned get_beta(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 78;
      MODE_DILITHIUM3: return 196;
      MODE_DILITHIUM5: return 120;
      default:         return 78;
    endcase
  endfunction

  function automatic int unsigned get_gamma1(dilithium_mode_t mode);
    // Returns the bit-width of gamma1: 17 for Dil2, 19 for Dil3/Dil5
    case (mode)
      MODE_DILITHIUM2: return 17;
      MODE_DILITHIUM3: return 19;
      MODE_DILITHIUM5: return 19;
      default:         return 17;
    endcase
  endfunction

  function automatic int unsigned get_gamma2(dilithium_mode_t mode);
    // Returns (q-1)/gamma2 divisor: 88 for Dil2, 32 for Dil3/Dil5
    case (mode)
      MODE_DILITHIUM2: return 88;
      MODE_DILITHIUM3: return 32;
      MODE_DILITHIUM5: return 32;
      default:         return 88;
    endcase
  endfunction

  function automatic int unsigned get_omega(dilithium_mode_t mode);
    case (mode)
      MODE_DILITHIUM2: return 80;
      MODE_DILITHIUM3: return 55;
      MODE_DILITHIUM5: return 75;
      default:         return 80;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Size constants
  // ---------------------------------------------------------------------------
  localparam int unsigned SEEDBYTES    = 32;
  localparam int unsigned CRHBYTES     = 64;
  localparam int unsigned TRBYTES      = 64;
  localparam int unsigned RNDBYTES      = 32;

  localparam int unsigned POLYT1_PACKEDBYTES = 320;
  localparam int unsigned POLYT0_PACKEDBYTES = 416;

  // ---------------------------------------------------------------------------
  // Key/Signature size helper functions
  // ---------------------------------------------------------------------------
  function automatic int unsigned get_pk_bytes(dilithium_mode_t mode);
    return SEEDBYTES + get_K(mode) * POLYT1_PACKEDBYTES;
  endfunction

  function automatic int unsigned get_sk_bytes(dilithium_mode_t mode);
    int unsigned polyeta_k, polyeta_l;
    polyeta_l = (get_eta(mode) == 2) ? 96 : 128;
    polyeta_k = (get_eta(mode) == 2) ? 96 : 128;
    return 2*SEEDBYTES + TRBYTES
         + get_L(mode)*polyeta_l
         + get_K(mode)*polyeta_k
         + get_K(mode)*POLYT0_PACKEDBYTES;
  endfunction

  function automatic int unsigned get_sig_bytes(dilithium_mode_t mode);
    int unsigned polyz_bytes, polyw1_bytes, polyvech_bytes, ctilde_bytes;
    polyz_bytes    = (get_gamma1(mode) == 17) ? 576 : 640;
    polyw1_bytes   = (get_gamma2(mode) == 88) ? 192 : 128;
    polyvech_bytes = get_omega(mode) + get_K(mode);
    ctilde_bytes   = (mode == MODE_DILITHIUM2) ? 32 :
                     (mode == MODE_DILITHIUM3) ? 48 : 64;
    return ctilde_bytes + get_L(mode)*polyz_bytes + polyvech_bytes;
  endfunction

  // ---------------------------------------------------------------------------
  // Coefficient type definitions
  // ---------------------------------------------------------------------------
  // - coeff_t:       Normalized coefficient in (-Q, Q). 24-bit signed because
  //                  Q = 8380417 < 2^23. We use 24 bits to accommodate
  //                  sums of two Q-bounded values which can be up to 2*Q-2.
  // - coeff32_t:     Signed 32-bit, used for intermediate sums.
  // - coeff_wide_t:  Signed 48-bit, used for products of two coeff_t values.
  //                  24+24 = 48 bits, sufficient to avoid overflow in
  //                  Montgomery reduction.
  // - coef_pack_t:   Unsigned 24-bit packed storage (no sign in storage).
  // ---------------------------------------------------------------------------
  typedef logic signed [23:0]  coeff_t;
  typedef logic signed [31:0]  coeff32_t;
  typedef logic signed [47:0]  coeff_wide_t;
  typedef logic        [23:0]  coeff_pack_t;

  // NTT Zeta type: also 24-bit signed (matches C reference zetas[]).
  typedef logic signed [23:0]  zeta_t;

  // ---------------------------------------------------------------------------
  // Polynomial type: 256 coefficients
  // ---------------------------------------------------------------------------
  typedef coeff_t poly_t [N];

  // Polynomial packed byte stream (used for external SRAM)
  typedef logic [7:0] poly_bytes_t [POLY_BYTES];

  // ---------------------------------------------------------------------------
  // Keccak / SHA3 types
  // ---------------------------------------------------------------------------
  // State: 1600 bits = 25 lanes x 64 bits
  localparam int unsigned KECCAK_STATE_BITS  = 1600;
  localparam int unsigned KECCAK_STATE_LANES = 25;
  localparam int unsigned KECCAK_LANE_BITS   = 64;
  localparam int unsigned KECCAK_ROUNDS      = 24;

  typedef logic [KECCAK_LANE_BITS-1:0]   keccak_lane_t;
  typedef keccak_lane_t                   keccak_state_t [KECCAK_STATE_LANES];

  // SHA3 / SHAKE rates (in bytes)
  localparam int unsigned SHAKE128_RATE  = 168; // 200 - 2*16
  localparam int unsigned SHAKE256_RATE  = 136; // 200 - 2*32
  localparam int unsigned SHA3_256_RATE  = 136;
  localparam int unsigned SHA3_512_RATE  = 72;

  // Domain separation bytes (FIPS 202 / FIPS 204)
  localparam logic [7:0] DS_SHAKE128  = 8'h1F; // SHAKE128
  localparam logic [7:0] DS_SHAKE256  = 8'h1F; // SHAKE256
  localparam logic [7:0] DS_SHA3_256  = 8'h06;
  localparam logic [7:0] DS_SHA3_512  = 8'h06;

  // ---------------------------------------------------------------------------
  // Register map offsets (APB / AHB compatible, 32-bit aligned)
  // ---------------------------------------------------------------------------
  typedef enum logic [5:0] {
    REG_CTRL       = 6'h00,
    REG_STATUS     = 6'h04,
    REG_MODE       = 6'h08,
    REG_OPERATION  = 6'h0C,
    REG_PK_BASE    = 6'h10,
    REG_PK_LEN     = 6'h14,
    REG_SK_BASE    = 6'h18,
    REG_SK_LEN     = 6'h1C,
    REG_SIG_BASE   = 6'h20,
    REG_SIG_LEN    = 6'h24,
    REG_MSG_BASE   = 6'h28,
    REG_MSG_LEN    = 6'h2C,
    REG_IRQ_STATUS = 6'h30,
    REG_ERR_INFO   = 6'h34
  } reg_offset_t;

  // CTRL register bit fields
  localparam int unsigned CTRL_START_BIT = 0;
  localparam int unsigned CTRL_RESET_BIT = 1;
  localparam int unsigned CTRL_IRQEN_BIT = 2;

  // STATUS register bit fields
  localparam int unsigned STATUS_READY_BIT = 0;
  localparam int unsigned STATUS_DONE_BIT  = 1;
  localparam int unsigned STATUS_ERR_BIT   = 2;
  localparam int unsigned STATUS_BUSY_BIT  = 3;

  // IRQ_STATUS register bit fields (write-1-to-clear)
  localparam int unsigned IRQ_DONE_BIT  = 0;
  localparam int unsigned IRQ_ERROR_BIT = 1;

  // ---------------------------------------------------------------------------
  // Status / Error codes
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ERR_NONE         = 4'h0,
    ERR_INVALID_MODE = 4'h1,
    ERR_INVALID_OP   = 4'h2,
    ERR_LENGTH       = 4'h3,
    ERR_VERIFY       = 4'h4,
    ERR_TIMEOUT      = 4'h5,
    ERR_INTERNAL     = 4'hF
  } err_code_t;

  // ---------------------------------------------------------------------------
  // Shared SRAM sizing (max worst-case for Dilithium5)
  // ---------------------------------------------------------------------------
  // Dil5: 56 matrix polys + 7 s1 + 8 s2/t0/t1/w1/w0/h + 1 y/z/c = 72 polys max
  // 72 * 256 * 24b = 442368 bytes = 432 KB. We round up to 64 Kwords (256 KB)
  // when using 32b/word and assume bit-packing for coefficients; alternatively
  // a 24b/word SRAM yields 4608 words. We choose 32b/word for simplicity and
  // let the upper 8 bits be zero-padded.
  localparam int unsigned SRAM_WORDS      = 16 * 1024;     // 16K x 32b = 64 KB
  localparam int unsigned SRAM_ADDR_WIDTH = $clog2(SRAM_WORDS);

  // ---------------------------------------------------------------------------
  // NTT control signals
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    NTT_OP_IDLE  = 2'b00,
    NTT_OP_NTT   = 2'b01,
    NTT_OP_INTT  = 2'b10
  } ntt_op_t;

  // ---------------------------------------------------------------------------
  // Useful utility macros
  // ---------------------------------------------------------------------------
  `define DILITHIUM_ASSERT(cond, msg) \
    assert(cond) else $error("ASSERT FAILED: %s @ %m", msg)

endpackage : dilithium_pkg

`endif // DILITHIUM_PKG_SV
