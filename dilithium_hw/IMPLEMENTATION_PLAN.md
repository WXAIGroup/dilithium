# Dilithium SystemVerilog Hardware Implementation Plan

**Project:** Post-Quantum Digital Signature IP Core (FIPS 204)
**Date:** 2026-06-23
**Version:** 1.0

---

## 1. Overview

This document defines a comprehensive, resource-optimized SystemVerilog hardware implementation of the Dilithium post-quantum digital signature scheme. The implementation supports all three NIST security levels (Dilithium2/3/5) with runtime parameter configuration via registers.

### 1.1 Design Goals

| Requirement | Implementation |
|-------------|----------------|
| Synthesizable | IEEE 1800 SystemVerilog, no vendor-specific constructs |
| Parameter configurability | Runtime register configuration via APB/AHB slave interface |
| Communication interface | define selection: SPI or AXI (for I/O and configuration) |
| Resource minimization | Shared SRAM for all parameter sets, time-multiplexed processing |
| Algorithm compliance | FIPS 204 compliant reference |

---

## 2. Algorithm Analysis

### 2.1 Dilithium Parameter Sets

| Parameter | Dilithium2 | Dilithium3 | Dilithium5 | Notes |
|-----------|------------|------------|------------|-------|
| **Security Level** | NIST Level 2 | NIST Level 3 | NIST Level 5 | |
| **k** | 4 | 6 | 8 | Matrix A rows, pub vector size |
| **l** | 4 | 5 | 7 | Priv vector s1 size |
| **n** | 256 | 256 | 256 | Polynomial degree (all) |
| **q** | 8380417 | 8380417 | 8380417 | Modulus (all) |
| **d** | 13 | 13 | 13 | Power-of-two round bits |
| **ETA** | 2 | 4 | 2 | Secret key bound |
| **TAU** | 39 | 49 | 60 | Challenge weight |
| **BETA** | 78 | 196 | 120 | Signature norm bound |
| **GAMMA1** | 2^17 | 2^19 | 2^19 | Poly norm bound (y, z) |
| **GAMMA2** | (q-1)/88 | (q-1)/32 | (q-1)/32 | Decomposition bound |
| **OMEGA** | 80 | 55 | 75 | Hint size |
| **PK bytes** | 1312 | 1952 | 2592 | |
| **SK bytes** | 2560 | 4032 | 4896 | |
| **SIG bytes** | 2420 | 3309 | 4627 | |

### 2.2 Polynomial Storage Requirements

Each polynomial: **256 coefficients x 24 bits (packed, q < 2^24)** = 256 x 24b

Storage by parameter set:
- Dil2: polyvecl[4] + polyveck[4] + Matrix A[16] = 24 polys
- Dil3: polyvecl[5] + polyveck[6] + Matrix A[30] = 41 polys
- Dil5: polyvecl[7] + polyveck[8] + Matrix A[56] = 71 polys

Maximum SRAM needed (Dilithium5):
- Matrix A: 56 polys x 256 coeff x 24b = ~430 Kbits
- Temp buf: 15 polys x 256 x 24b = ~115 Kbits
- Total: ~545 Kbits (68 KB)

### 2.3 Key Computational Blocks

| Block | Operations | Cycles (est.) | Reuse Potential |
|-------|-----------|---------------|-----------------|
| **NTT** | 256-pt forward/inverse | ~2000 | Multiply via pointwise |
| **Keccak-p** | 24 rounds | ~500 | SHA3, SHAKE, hashing |
| **Poly x Poly** | Via NTT | ~2500 | All polynomial muls |
| **Matrix x Vec** | K x L NTTs + adds | ~K x 2500 | KeyGen, Sign, Verif |
| **Decompose** | Shift, mask, compare | ~500 | Sign, Verif |
| **Sampling** | CBD, rejection | Variable | KeyGen, Sign |

---

## 3. Interface Specification

### 3.1 Communication Interface Selection (Compile-Time)

    // Compile-time selection via defines
    `ifdef DILITHIUM_SPI_INTERFACE
      module dilithium_spi_if (...);
    `elsif DILITHIUM_AXI_INTERFACE
      module dilithium_axi_if (...);
    `endif

### 3.2 Register Map (APB/AHB Compatible)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | CTRL | RW | Control: START, IRQ_EN, MODE, RESET |
| 0x04 | STATUS | RO | Status: DONE, READY, ERR_CODE |
| 0x08 | MODE | RW | 0=Dilithium2, 1=Dilithium3, 2=Dilithium5 |
| 0x0C | OPERATION | RW | 0=KeyGen, 1=Sign, 2=Verify |
| 0x10 | PK_BASE | RW | Public key buffer base address |
| 0x14 | PK_LEN | RO | Public key length (auto-filled) |
| 0x18 | SK_BASE | RW | Secret key buffer base address |
| 0x1C | SK_LEN | RO | Secret key length (auto-filled) |
| 0x20 | SIG_BASE | RW | Signature buffer base address |
| 0x24 | SIG_LEN | RW | Signature length |
| 0x28 | MSG_BASE | RW | Message buffer base address |
| 0x2C | MSG_LEN | RW | Message length |
| 0x30 | IRQ_STATUS | RW1C | Interrupt status |
| 0x34 | ERR_INFO | RO | Error info |

---

## 4. Core Architecture

### 4.1 Project Structure

dilithium_hw/
├── rtl/
│   ├── core/
│   │   ├── dilithium_top.sv           # Top-level module
│   │   ├── dilithium_ctrl_fsm.sv      # Main control FSM
│   │   └── dilithium_reg_bank.sv      # Parameter registers
│   ├── ntt/
│   │   ├── ntt_engine.sv              # 256-point NTT/INTT
│   │   ├── ntt_twiddle_rom.sv         # Twiddle factor ROM
│   │   └── ntt_systolic_array.sv      # Optional systolic NTT
│   ├── sha3/
│   │   ├── keccak_permutation.sv      # Keccak-p[1600]
│   │   ├── shake128.sv                # SHAKE-128 XOF
│   │   ├── shake256.sv                # SHAKE-256 XOF
│   │   └── sha3_256_512.sv            # SHA3-256/512
│   ├── poly/
│   │   ├── poly_arith_unit.sv         # Add/sub/shift
│   │   ├── poly_reduce_unit.sv        # Montgomery reduction
│   │   ├── poly_mul_unit.sv           # Pointwise mul via NTT
│   │   ├── poly_decomp_unit.sv        # Power2round/decompose
│   │   └── poly_norm_chk.sv           # Norm checking
│   ├── sampling/
│   │   ├── poly_uniform.sv            # Uniform sampling
│   │   ├── poly_uniform_eta.sv        # ETA-bounded (CBD)
│   │   ├── poly_uniform_gamma1.sv     # GAMMA1-bounded
│   │   └── poly_challenge.sv          # Challenge generation
│   ├── polyvec/
│   │   ├── polyvecl_ops.sv            # L-polynomial ops
│   │   ├── polyveck_ops.sv            # K-polynomial ops
│   │   └── matrix_vec_mul.sv          # Matrix x vector
│   ├── storage/
│   │   ├── shared_sram.sv             # Unified SRAM
│   │   ├── sram_controller.sv         # Address mux
│   │   └── coeff_buffer.sv            # Coefficient buffer
│   ├── packing/
│   │   ├── pack_pk.sv / unpack_pk.sv # Public key
│   │   ├── pack_sk.sv / unpack_sk.sv # Secret key
│   │   └── pack_sig.sv / unpack_sig.sv # Signature
│   └── io/
│       ├── dilithium_spi_if.sv        # SPI slave
│       ├── dilithium_axi_if.sv        # AXI4-Lite slave
│       └── io_mux.sv                  # Interface mux
├── include/
│   ├── dilithium_pkg.sv              # Types, parameters, macros
│   ├── ntt_params.svh                 # NTT twiddle factors
│   └── keccak_constants.svh           # Keccak round constants
├── tb/
│   ├── tb_dilithium_top.sv           # Top-level TB
│   ├── tb_ntt_engine.sv              # NTT unit TB
│   └── compare_ref.py                 # HW vs C ref comparison
└── scripts/
    ├── compile.sh                      # Verilator simulation
    ├── synthesize.sh                   # DC synthesis
    └── gen_twiddles.py               # Generate twiddle factors

### 4.2 Shared SRAM Architecture

Address map (word = 32 bits):
- 0x00000 - 0x00FFF: Matrix A[56] x 256 coeffs = 43 Kwords
- 0x01000 - 0x017FF: polyvecl s1 (7 polys) = 5.4 Kwords
- 0x01800 - 0x01DFF: polyveck temp (s2,t0,t1,w1,w0,h) = 5.4 Kwords
- 0x01E00 - 0x01FFF: Control buffers (y,z,challenge) = 0.5 Kwords

Total: 64 Kwords = 256 KB @ 32b/word

Strategy: Single-port SRAM with time-multiplexing for all parameter sets.

### 4.3 NTT Engine Design

    module ntt_engine (
      input  logic       clk,
      input  logic       rst_n,
      input  logic       start,
      input  logic       inv_ntt,       // 0=NTT, 1=INTT
      input  logic[15:0] src_base_addr,
      input  logic[15:0] dst_base_addr,
      output logic       done,
      output logic       error
    );

- 256-point NTT, radix-4 with interleaving
- Latency: ~2000 cycles per transform
- Throughput: 1 butterfly per cycle

### 4.4 Keccak/SHA3 Unit

    module keccak_permutation (
      input  logic         clk,
      input  logic         rst_n,
      input  logic         start,
      input  logic[1599:0] state_in,
      output logic[1599:0] state_out,
      output logic         done
    );

- Keccak-p[1600]: 25 x 64-bit state, 24 rounds
- SHA3-256/512: fixed output length
- SHAKE-128/256: variable output (XOF)

---

## 5. Module Decomposition

### Phase 1: Core Arithmetic Units
1. dilithium_pkg.sv - Types, parameters, macros
2. keccak_constants.svh - Round constants ROM
3. ntt_params.svh - Twiddle factor ROM
4. keccak_permutation.sv - Keccak-p[1600] core
5. shake128.sv, shake256.sv - XOF wrappers
6. ntt_twiddle_rom.sv - Twiddle storage
7. ntt_engine.sv - Forward/Inverse NTT

### Phase 2: Polynomial Operations
1. poly_reduce_unit.sv - Montgomery reduction
2. poly_arith_unit.sv - Add, subtract, shift
3. poly_mul_unit.sv - Pointwise multiply (NTT)
4. poly_decomp_unit.sv - Power2round, decompose
5. poly_norm_chk.sv - Norm checking

### Phase 3: Vector Operations
1. polyvecl_ops.sv - L-polynomial vector ops
2. polyveck_ops.sv - K-polynomial vector ops
3. matrix_vec_mul.sv - Matrix x vector

### Phase 4: Sampling
1. poly_uniform.sv - Uniform sampling
2. poly_uniform_eta.sv - ETA-bounded (CBD)
3. poly_uniform_gamma1.sv - GAMMA1-bounded
4. poly_challenge.sv - Challenge generation

### Phase 5: Packing/Unpacking
1. pack_pk.sv / unpack_pk.sv - Public key
2. pack_sk.sv / unpack_sk.sv - Secret key
3. pack_sig.sv / unpack_sig.sv - Signature

### Phase 6: Storage
1. shared_sram.sv - Unified SRAM array
2. sram_controller.sv - Address mapping
3. coeff_buffer.sv - Coefficient buffer

### Phase 7: Control & Top-Level
1. dilithium_reg_bank.sv - Register file
2. dilithium_ctrl_fsm.sv - Main FSM
3. dilithium_spi_if.sv - SPI interface
4. dilithium_axi_if.sv - AXI interface
5. dilithium_top.sv - Complete system

---

## 6. Parameter Configuration

### 6.1 MODE-Dependent Parameters

    typedef enum logic [1:0] {
      MODE_DILITHIUM2 = 2b00,
      MODE_DILITHIUM3 = 2b01,
      MODE_DILITHIUM5 = 2b10
    } dilithium_mode_t;

    function automatic int get_K(dilithium_mode_t mode);
      case(mode)
        MODE_DILITHIUM2: return 4;
        MODE_DILITHIUM3: return 6;
        MODE_DILITHIUM5: return 8;
      endcase
    endfunction

    function automatic int get_L(dilithium_mode_t mode);
      case(mode)
        MODE_DILITHIUM2: return 4;
        MODE_DILITHIUM3: return 5;
        MODE_DILITHIUM5: return 7;
      endcase
    endfunction

### 6.2 Key Parameter Values by Mode

| Parameter | Dilithium2 | Dilithium3 | Dilithium5 |
|-----------|------------|------------|------------|
| K | 4 | 6 | 8 |
| L | 4 | 5 | 7 |
| ETA | 2 | 4 | 2 |
| GAMMA1 | 2^17 | 2^19 | 2^19 |
| GAMMA2 | (q-1)/88 | (q-1)/32 | (q-1)/32 |
| OMEGA | 80 | 55 | 75 |

---

## 7. Resource Estimation

| Module | Logic (LUT/FF) | SRAM (KB) |
|-------|----------------|-----------|
| Keccak | ~3K | - |
| NTT Engine | ~5K | - |
| Poly Ops | ~2K | - |
| Sampling | ~2K | - |
| SRAM | - | 256 |
| Control FSM | ~1K | - |
| **Total** | **~13K** | **256** |

---

## 8. Verification Strategy

1. Unit tests: Each module with Verilator
2. C reference comparison: Python script
3. NIST KAT tests: Standard test vectors
4. Protocol tests: SPI/AXI end-to-end

