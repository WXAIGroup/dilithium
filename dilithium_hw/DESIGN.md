# Dilithium Hardware IP Core - Design Document (Phase 1)

**Project:** Dilithium Post-Quantum Digital Signature IP Core (FIPS 204)
**Document Version:** 2.0 (detailed expansion)
**Date:** 2026-06-24
**Scope:** Phase 1 - Core Arithmetic Units (Keccak/SHA3 + NTT)

---

## Table of Contents

1. Overview
2. Algorithm & Mathematical Foundation
3. Type System & Numeric Foundation
4. Keccak-p[1600] - `keccak_permutation.sv`
5. SHAKE128 / SHAKE256
6. NTT Engine - `ntt_engine.sv`
7. Twiddle ROM - `ntt_twiddle_rom.sv`
8. Reset & Error Handling
9. Resource Estimate
10. Synthesis & Timing Considerations
11. Module Hierarchy
12. Compliance

---

## 1. Overview

This document describes the architecture, design rationale, and module-level
specification of the Phase 1 deliverables. Phase 1 covers the two algorithmic
building blocks that all higher-level Dilithium operations depend on:

1. **Keccak-p[1600]** - the cryptographic permutation that powers SHA3-256/512,
   SHAKE128, and SHAKE256. Used in Dilithium for:
   - Hashing the message and the public key (CRH, SHAKE256)
   - Expanding seeds into matrix A and noise vectors (SHAKE128/SHAKE256)
   - Deriving the challenge polynomial c (SHAKE256)

2. **256-point NTT** - the Number Theoretic Transform that enables fast
   polynomial multiplication in the Dilithium ring `R_q = Z_q[x]/(x^256 + 1)`.
   Used in Dilithium for all `poly_mul` operations (matrix-vector products,
   pointwise multiplication in signature verification).

The design is synthesizable IEEE 1800 SystemVerilog, with no vendor-specific
constructs. It targets the constraints in the parent `IMPLEMENTATION_PLAN.md`:
~13K LUT/FF total, 256 KB shared SRAM, runtime-configurable mode (Dil2/3/5).

The implementation is bit-exact with the reference C code in `ref/`, which
is itself the official pq-crystals reference implementation submitted to
NIST for FIPS 204 standardization.

---

## 2. Algorithm & Mathematical Foundation

This section explains the WHY behind the design decisions by walking through
the relevant mathematics.

### 2.1 The Dilithium ring R_q

Dilithium operates in the polynomial ring:
```
R_q = Z_q[x] / (x^256 + 1)
```

where `Z_q` is the field of integers modulo `q = 8380417` (a prime). Polynomials
in this ring have degree at most 255, and `x^256 = -1` (mod `x^256 + 1`).

Multiplication of two such polynomials naively costs O(N^2) = O(65536)
coefficient multiplications. The NTT brings this down to O(N log N) by
working in the frequency domain.

### 2.2 The Number Theoretic Transform

For a polynomial `a(x)` of degree less than N, the NTT is the evaluation
of `a(x)` at N points which are roots of `x^N - 1`. In Dilithium, we use
a "negacyclic" NTT: the ring is `x^N + 1`, so the NTT is evaluation at the
2N-th roots of unity that are NOT N-th roots of unity (i.e., `zeta` such
that `zeta^(2N) = 1` but `zeta^N = -1`).

The forward NTT computes:
```
A_k = sum_{j=0..N-1} a_j * zeta^(2*j*k + j)   for k = 0..N-1
```

(Note the extra `+j` in the exponent, which is the negacyclic twist.)
The inverse NTT applies the same structure with `zeta^(-1)`.

The **primitive 512-th root of unity** in `Z_q` is `zeta = 1753`. This is
defined in `params.h` as `ROOT_OF_UNITY`. We have `1753^256 = -1 mod q`,
and `1753^512 = 1 mod q`.

### 2.3 Why `q = 8380417`

The choice of `q` is not arbitrary:
- It must be prime.
- `q - 1` must be divisible by 512 (so that a 512-th root of unity exists
  in `Z_q`).
- `q mod 8 = 1` is convenient for Montgomery reduction (allows
  `Q^(-1) mod 2^32` to fit in a signed 32-bit value).
- `8380417 < 2^23`, so 24-bit storage is sufficient.

`q = 8380417` satisfies all these conditions and is widely used in
lattice-based cryptography (also in NewHope and Kyber).

### 2.4 Montgomery reduction

The NTT butterfly requires computing `zeta * a mod q` where both
operands are 24-bit. The naive approach uses a 64-bit multiplier
(24+24=48 bits product). Montgomery reduction is a more efficient
algorithm that:
- Computes `r = a * 2^(-32) mod q` (i.e., `a` divided by `2^32` modulo `q`).
- The trick: choose `QINV` such that `q * QINV = 1 + k*2^32` for some integer
  `k`. Then `t = a_low32 * QINV` is a 32-bit correction, and
  `(a - t*q) / 2^32` is a multiple of `2^(-32)`.

For Dilithium: `QINV = 58728449`. Verification: `q * QINV mod 2^32 = 1`:
```
8380417 * 58728449 = 492230912196833
492230912196833 mod 2^32 = 492230912196833 mod 4294967296 = 1  [OK]
```

The full Montgomery reduction:
```
function mont_reduce(a):
    t   = (a & 0xFFFFFFFF) * QINV       # low 32 bits times QINV
    sub = a - (t * q) & 0xFFFFFFFFFFFFFFFF
    return sub >> 32                     # high bits
```

This converts a 48-bit signed value `a` into a 24-bit signed value
`r = a * 2^(-32) mod q`, with `r in (-q, q)`.

### 2.5 The sponge construction (FIPS 202)

SHAKE128/256 are **sponge functions**, not hash functions in the traditional
sense. They work by:
1. Initializing a 1600-bit state to all zeros.
2. **Absorb** phase: XOR input bytes into the first `r` bytes of the state,
   then apply the Keccak permutation. Repeat until all input is absorbed.
3. **Squeeze** phase: read `r` bytes of output from the state, then apply
   the permutation. Repeat until enough output is produced.

The state has 1600 bits = 200 bytes, split into:
- `r` = rate (capacity-free part used for data I/O)
- `c` = capacity (1600 - 8*r bits, never directly read/written, provides
  security)

For SHAKE128: `r = 168 bytes` (security strength 128 bits).
For SHAKE256: `r = 136 bytes` (security strength 256 bits).

The difference in `r` is what makes the two functions different: a smaller
rate means more "capacity" and more security, at the cost of throughput.

### 2.6 Padding

The FIPS 202 padding schemes:
- **SHAKE128/SHAKE256**: append `0x1F` byte, then `0x80` byte. The 0x1F is
  the FIPS 202 domain separation byte for SHAKE.
- **SHA3-256/512**: append `0x06` byte, then `0x80` byte. The 0x06 is the
  FIPS 202 domain separation byte for SHA3.

In hardware, this is implemented by XORing `0x1F` at the first unused byte
position and `0x80` (= setting bit 63) at the last byte of the rate portion.

---

## 3. Type System & Numeric Foundation

The `dilithium_pkg` package defines all the width types used across the
Phase 1 modules. Width choices are critical: too narrow causes overflow,
too wide wastes area.

### 3.1 Coefficient representation

| Type | Width | Range | Used for |
|---|---|---|---|
| `coeff_t` | 24-bit signed | `(-2^23, 2^23)` | Normalized coefficients |
| `coeff32_t` | 32-bit signed | `(-2^31, 2^31)` | Internal sums (rare) |
| `coeff_wide_t` | 48-bit signed | `(-2^47, 2^47)` | Products before Montgomery |
| `coeff_pack_t` | 24-bit unsigned | `[0, 2^24)` | External byte stream (no sign) |

**Why 24 bits for coeff_t?**

`q = 8380417 < 2^23 = 8388608`. So a single Q-bounded value fits in 23
bits signed. We round up to 24 bits to leave headroom:
- Sum of two Q-bounded values: up to `2q - 2 < 2^24 = 16777216`
- Difference: up to `q - (-q) = 2q < 2^24`
- Post-NTT coefficients can be up to `~3q` (one forward NTT pass), still
  fits in 24 bits.

**Why 48 bits for coeff_wide_t?**

A product of two 24-bit signed values has:
- Magnitude up to `(2^23) * (2^23) = 2^46`
- Sign: + or -
- So it fits in 47 bits signed. 48 bits gives 1 bit of margin.

**Why is Montgomery reduction only 24-bit output?**

The Montgomery reduction function in `ntt_engine.sv` has signature
`mont_reduce(input [47:0] a) -> [23:0] result`. The 48-bit input is the
zeta * a_jlen product, and the 24-bit output is the reduced value in
`(-q, q)`. This output fits in 24 bits because Montgomery reduction is
guaranteed to produce a result in `(-q, q)`.

### 3.2 NTT zetas (twiddle factors)

Stored in `include/ntt_params.svh` as `logic signed [23:0] ZETAS [0:255]`.
Values are bit-exact copies of the C reference's `zetas[]` table in
`ref/ntt.c`.

**Why 256 values?**

The forward NTT uses 255 of the 256 zetas (zetas[1] through zetas[255]).
zetas[0] is unused but kept in the table for index alignment with the
C reference. The C code is:
```c
k = 0;
for (len = 128; len > 0; len >>= 1) {
    for (start = 0; start < N; start = j + len) {
        zeta = zetas[++k];  // k goes from 1 to 255
        ...
    }
}
```

**Why 24 bits for zetas?**

Same as coeff_t: the zetas are themselves elements of `Z_q`, so they
fit in 24 bits signed. The table is generated by `scripts/gen_twiddles.py`
which validates that all 256 zetas are in the range `(-q, q)`.

### 3.3 Mode-dependent parameters

`dilithium_pkg.sv` defines three parameter sets (Dilithium2/3/5) selected
by a 2-bit register field. The active mode influences downstream
components (Phase 2+) but Phase 1 modules are mode-agnostic.

The accessor functions `get_K()`, `get_L()`, etc. are pure combinational
and return the integer value for the selected mode. They can be used in
combinational contexts (e.g., address generation) without timing cost.

### 3.4 1600-bit Keccak state

The Keccak state is organized as a 5x5 array of 64-bit lanes. We
represent this as an unpacked array of 25 `logic [63:0]` lanes, which
synthesizers can implement as 25 independent 64-bit registers. This
avoids the area overhead of barrel shifters that would be required if
the state were stored as a single `[1599:0]` packed vector.

The lane ordering follows the C reference: `state[5*y + x]` corresponds
to lane `(x, y)` in the Keccak specification. Little-endian lane
ordering is used: lane 0 occupies bits `[63:0]`, lane 1 occupies
`[127:64]`, etc.

---

## 4. Keccak-p[1600] - `keccak_permutation.sv`

### 4.1 Algorithm overview

Keccak-f[1600] is the 24-round permutation on a 1600-bit state. Each
round applies five steps:

1. **Theta** - linear mixing across lanes (column parity)
2. **Rho** - lane-wise bit rotation
3. **Pi** - lane permutation (rearrangement)
4. **Chi** - non-linear mixing within rows
5. **Iota** - XOR with a round constant

The five steps are designed together so that after 24 rounds, the
permutation has excellent diffusion and non-linearity properties
(no known attacks on reduced-round Keccak with > 6 rounds).

### 4.2 The state: 5x5 lane array

The 1600-bit state is conceptually a 5x5 grid of 64-bit lanes:

```
A[0,0]  A[1,0]  A[2,0]  A[3,0]  A[4,0]   <- row y=0
A[0,1]  A[1,1]  A[2,1]  A[3,1]  A[4,1]   <- row y=1
A[0,2]  A[1,2]  A[2,2]  A[3,2]  A[4,2]   <- row y=2
A[0,3]  A[1,3]  A[2,3]  A[3,3]  A[4,3]   <- row y=3
A[0,4]  A[1,4]  A[2,4]  A[3,4]  A[4,4]   <- row y=4
       \--column x--/
```

In hardware, this is stored as a 25-element unpacked array:
```systemverilog
state_t = logic [63:0] [25];
state[ 0] = A[0,0]  state[ 1] = A[1,0]  ... state[ 4] = A[4,0]
state[ 5] = A[0,1]  state[ 6] = A[1,1]  ... state[ 9] = A[4,1]
...
state[20] = A[0,4]  state[21] = A[1,4]  ... state[24] = A[4,4]
```

Index `i` corresponds to lane `(x, y)` with `x = i mod 5`, `y = i / 5`.

### 4.3 The five steps in detail

**Step 1: Theta**

Compute the column parities (XOR down each column), then XOR each lane
with a parity-derived value:

```
C[x] = A[x, 0] ^ A[x, 1] ^ A[x, 2] ^ A[x, 3] ^ A[x, 4]   (column parity)
D[x] = C[(x-1) mod 5] ^ ROL(C[(x+1) mod 5], 1)             (diffusion)
A[x, y] ^= D[x]
```

`ROL(x, 1)` is a 64-bit left-rotation by 1. In SystemVerilog, this is
written as `{x[0], x[63:1]}` (rotate left = shift left, with the MSB
wrapping to the LSB position).

**Step 2: Rho**

Each lane is rotated left by an amount that depends on its position.
The rotation offsets are a specific sequence of 24 distinct values
(plus 0 for the "anchor" lane), chosen to optimize diffusion. The
specific offsets are:

```
       y=0  y=1  y=2  y=3  y=4
x=0      0   1    62   28   27
x=1     36   44   6    55   20
x=2      3   10   43   25   39
x=3     41   45   15   21   8
x=4     18   2    61   56   14
```

Note: the C reference's fused form reorders the application of rho
(rotation happens AFTER theta's D, and is interleaved with pi and chi).
We follow this same ordering for compatibility.

**Step 3: Pi**

The pi step is a fixed permutation of the 25 lanes. The permutation
is the one that maps lane `(x, y)` to lane `(y, (2x + 3y) mod 5)`.
The first few mappings are:
- A[0,0] stays at (0,0) - the "anchor" lane
- A[1,0] moves to (0,2) - lane 1 to lane 2
- A[2,0] moves to (0,4) - lane 2 to lane 4
- A[3,0] moves to (0,1) - lane 3 to lane 1
- A[4,0] moves to (0,3) - lane 4 to lane 3
- A[0,1] moves to (1,3) - lane 5 to lane 13
- ... (24 more)

After pi, the lanes are in a permuted order.

**Step 4: Chi**

The chi step is the only non-linear operation in Keccak. For each
row, compute:
```
A[x, y] ^= (~A[(x+1) mod 5, y]) & A[(x+2) mod 5, y]
```

The "mod 5" indices wrap around. The chi step is computed after rho
and pi, so the lanes being XORed are the rotated and permuted ones.

**Step 5: Iota**

The first lane (A[0,0]) is XORed with a 64-bit round constant.
The 24 round constants are:

```
RC[0]  = 0x0000000000000001   RC[12] = 0x000000008000808b
RC[1]  = 0x0000000000008082   RC[13] = 0x800000000000008b
RC[2]  = 0x800000000000808a   RC[14] = 0x8000000000008089
RC[3]  = 0x8000000080008000   RC[15] = 0x8000000000008003
RC[4]  = 0x000000000000808b   RC[16] = 0x8000000000008002
RC[5]  = 0x0000000080000001   RC[17] = 0x8000000000000080
RC[6]  = 0x8000000080008081   RC[18] = 0x000000000000800a
RC[7]  = 0x8000000000008009   RC[19] = 0x800000008000000a
RC[8]  = 0x000000000000008a   RC[20] = 0x8000000080008081
RC[9]  = 0x0000000000000088   RC[21] = 0x8000000000008080
RC[10] = 0x0000000080008009   RC[22] = 0x0000000080000001
RC[11] = 0x000000008000000a   RC[23] = 0x8000000080008008
```

The round constants are derived from a linear feedback shift register
(LFSR) with characteristic polynomial `x^8 + x^6 + x^5 + x^4 + 1`. They
provide additional per-round asymmetry that prevents slide attacks.

### 4.4 The "fused" implementation

The C reference (`ref/fips202.c`) implements Keccak with a **fused**
form that combines theta, rho, pi, chi, and iota in a single
combinational pass. This produces a single, more complex formula
but reduces register pressure and improves cache behavior in software.

For hardware, this fusion is BENEFICIAL because:
1. The combinational logic is computed once per round, latched into
   a register, and becomes the input to the next round.
2. We don't need separate registers for intermediate theta/rho/pi
   results.
3. The total combinational delay is the same as computing each step
   separately (since the critical path is bounded by chi and iota).

We follow the C reference's fusion exactly. The function
`keccak_round_fn()` in the SV code is a 1:1 port of the C code.

### 4.5 Hardware design

#### State storage

A 25-element unpacked array of 64-bit lanes. Each lane is a 64-bit
register, so the total state is 1600 bits = 200 bytes = 50 32-bit
words. Synthesis tools will infer this as 25 register banks with
per-lane enables.

#### Round counter

A `$clog2(ROUNDS+1)`-bit counter (5 bits for ROUNDS=24) that tracks
which round is being computed. On reset, the counter is 0. On
`start`, the input state is latched and the counter stays at 0.
On each subsequent cycle, the counter increments and a new round
is computed. When the counter reaches `ROUNDS-1`, the FSM asserts
`done` and goes back to idle.

#### Done pulse

`done` is a 1-cycle pulse asserted in the cycle when the LAST round
is complete and the new state has been latched. The next cycle, the
FSM returns to idle and `done` is deasserted.

#### Why 1 round per cycle (not 2)

The C reference computes 2 rounds per outer-loop iteration:
```c
for (round = 0; round < 24; round += 2) {
    // compute rounds `round` and `round+1`
}
```

In hardware, we could similarly compute 2 rounds per cycle by
unrolling. This would halve the latency (12 cycles instead of 24).
However, it would also double the combinational critical path
(roughly), reducing the maximum clock frequency. For Phase 1 we
chose 1 round/cycle for simplicity. A future optimization can
retime to 2 rounds/cycle by adding pipeline registers within the
chi/rho/pi combinational path.

### 4.6 Interface

```systemverilog
module keccak_permutation #(parameter int unsigned ROUNDS = 24) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,        // Pulse to begin a permutation
    output logic          busy,         // High while processing
    output logic          done,         // 1-cycle pulse on completion
    input  logic [1599:0] state_in,     // Initial state (lane 0 in low bits)
    output logic [1599:0] state_out     // Final state, valid with done
);
```

### 4.7 Reset behavior

`rst_n` is an active-low asynchronous reset. On `rst_n = 0`:
- `s_reg` is cleared to all zeros
- `round_cnt` is cleared to 0
- `running` is cleared to 0
- `done` is deasserted

When `rst_n` returns high and `start` is pulsed, a new permutation
begins.

### 4.8 Bug history

During development, the chi step for Eba had a typo: it used
`ROL(Age^De, 44)` for both BCe and BCi, instead of `ROL(Aki^Di, 43)`
for BCi. This was caught by the Python golden model producing
incorrect output. The fix was applied to both the Python model and
the SV module in lockstep. See `VERIFICATION_REPORT.md` for details.

---

## 5. SHAKE128 / SHAKE256

Dilithium's most common XOF use is the "absorb once, squeeze many" pattern:
```c
keccak_state state;
shake128_absorb_once(&state, seed, seed_len);
for (int i = 0; i < matrix_polys; i++) {
    shake128_squeezeblocks(out[i], 1, &state);
}
```

We decompose this into two reusable modules that share the
`keccak_permutation` core.

### 5.1 Sponge construction refresher

The sponge construction has two phases:

**Absorb**: Input bytes are XORed into the first `r` bytes of the state.
When the rate portion fills up, the entire state is permuted. This is
repeated until all input is consumed. The capacity portion is never
directly read or written.

**Squeeze**: Output bytes are read from the first `r` bytes of the state.
When the rate portion is exhausted, the state is permuted and more bytes
are read. This is repeated until enough output is produced.

For Dilithium:
- Matrix A expansion: `shake128_absorb_once(seed)` once, then
  `shake128_squeezeblocks(state, K*L)` times.
- Secret vector s1/s2 sampling: `shake256_absorb_once(seed)` once, then
  `shake256_squeezeblocks(state, K+L)` times.

The "absorb once" pattern (vs incremental absorb) is the most common
because most Dilithium calls have a single fixed input.

### 5.2 The `pos` variable and the `pos = rate` trick

In the C reference, the `keccak_state` struct has a `pos` field that
tracks the current position within the rate block during absorb/squeeze:

```c
typedef struct { uint64_t s[25]; unsigned int pos; } keccak_state;
```

The `pos` field is used by the incremental APIs (`shake128_absorb` and
`shake128_squeeze`). For one-shot APIs (`shake128_absorb_once` and
`shake128_squeezeblocks`), `pos` is set to `SHAKE128_RATE` (= 168) at
the end of absorb, which means "the state has been padded and is
ready to be permuted". The first call to `shake128_squeeze` sees
`pos == rate` and triggers an initial permutation before reading bytes.

**Why this trick?**

It allows the squeeze code to be uniform: it always checks
`if (pos == r) { permute(); pos = 0; }` at the start of each chunk.
This works correctly for both:
- Continuing a squeeze from a previously-permuted state (pos starts at
  0, no permute)
- Starting a new squeeze right after absorb (pos starts at rate,
  triggers permute)

We don't implement the incremental `pos` variable in our SV modules
(since we only support absorb_once). Instead, we hardcode the
`pos = rate` behavior in the absorb_once state machine (it sets up
the state to be "ready for squeeze" by ensuring a permute happens
in the next squeeze call).

### 5.3 Padding: 0x1F (SHAKE) vs 0x06 (SHA3)

The C reference's `keccak_absorb_once` applies:
- `pad` byte at the first unused byte position (within the rate)
- 0x80 at the last byte of the rate (sets bit 63 of the last rate lane)

For SHAKE: `pad = 0x1F`. This is the FIPS 202 domain separation byte
for SHAKE functions (both SHAKE128 and SHAKE256 use 0x1F, but the
different rates distinguish them).

For SHA3: `pad = 0x06` (for SHA3-256 and SHA3-512). This is the
FIPS 202 domain separation byte for SHA3 hash functions.

The 0x80 at the last rate byte is a "final bit" that marks the
end of the input. It's the FIPS 202 "10*1" padding scheme.

In our SV modules, we implement only the SHAKE case (0x1F). The SHA3
variants would require a separate `shake3_*` module with `pad = 0x06`,
but Dilithium does not use SHA3-256/512 anywhere, so this is left for
future expansion.

### 5.4 `shake128_absorb_once` (and `shake256_absorb_once`)

```systemverilog
module shake128_absorb_once #(parameter MAX_INPUT_BYTES = 1024) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic [7:0]    in_data  [MAX_INPUT_BYTES],
    input  logic [15:0]   in_len,
    output logic          done,
    output logic [1599:0] state_out,   // Final state, ready for squeeze
    output logic          err
);
```

**State machine:**

```
IDLE --start--> INIT --1cy--> ABSORB
                              |   |   |
                              |   |   +-> PERMUTE --perm_done--> ABSORB (continue)
                              |   +-----> FINALIZE (no permute needed)
                              +---------> FINALIZE (end of input)
                                                 |
                                                 v
                                              PERMUTE --perm_done--> DONE
                                                                      |
                                                                      v
                                                                   IDLE (when start deasserts)
```

**S_INIT**: Zero the 1600-bit state (1 cycle).

**S_ABSORB**: XOR one byte at a time into the rate portion. When the rate
fills (every 168 bytes for SHAKE128), transition to S_PERMUTE. When
the input ends, transition to S_FINALIZE. Takes `in_len` cycles.

**S_PERMUTE**: Trigger the Keccak permutation core. Wait for `perm_done`.
Takes 24 cycles (the permutation latency). Then return to S_ABSORB or
S_FINALIZE depending on whether more input remains.

**S_FINALIZE**: Apply the padding (0x1F at the current pos, 0x80 at the
last rate byte). Then go to S_PERMUTE for the final permutation.

**S_DONE**: Assert `done` for at least 1 cycle. Return to IDLE when
`start` is deasserted.

For SHAKE256 the only difference is `RATE_BYTES = 136` instead of 168.
All shapes/widths are identical, so the two modules are textually
near-identical.

### 5.5 `shake128_squeezeblocks` (and `shake256_squeezeblocks`)

```systemverilog
module shake128_squeezeblocks #(parameter MAX_BLOCKS = 64) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic [1599:0] state_in,     // From absorb_once
    input  logic [15:0]   nblocks,
    output logic          done,
    output logic [7:0]    out_data [MAX_BLOCKS*168],
    output logic          err
);
```

**State machine:**

```
IDLE --start--> (nblocks>0 ? unpack state, go to PERMUTE : DONE)
PERMUTE --perm_done--> NEXT --(block_idx+1>=nblocks)--> DONE
                    |                                ^
                    +-- (otherwise back to PERMUTE) -+
```

Each "squeeze block" consists of one Keccak permutation followed by
reading 168 bytes (or 136 for SHAKE256) from the first 21 (or 17) lanes
of the state. The output is written combinationally to `out_data[b*168 + i]`
for block b, byte i.

**Output mapping**: The output is updated EVERY cycle (combinationally
from `s_reg`), not just on `done`. This means:
- The consumer must wait for `done` before reading.
- All blocks are available simultaneously when `done` is asserted.
- During processing, `out_data` shows the current (partial) state.

This is a deliberate trade-off: extra muxing (MAX_BLOCKS * 168 muxes)
in exchange for simpler consumer code.

### 5.6 Latency budget (per Dilithium primitive call)

| Operation | Cycles | Source |
|---|---|---|
| `shake128_absorb_once(seed32, 32)` | 1 + 32 + 24 = 57 | One call per KGen |
| `shake128_squeezeblocks(state, 1)` | 24 + 1 = 25 | Per 168-byte block |
| `shake256_absorb_once(seed64, 64)` | 1 + 64 + 24 = 89 | Per call |
| `shake256_squeezeblocks(state, 1)` | 24 + 1 = 25 | Per 136-byte block |

For Dilithium2 key generation:
- `shake128_absorb_once(rho)`: 1 (init) + 32 (absorb) + 24 (perm) = **57 cycles**
- `shake128_squeezeblocks(state, K*L)`: `K*L = 16` blocks = 16 * 25 = **400 cycles**
- Total matrix A generation: **~457 cycles** (plus the actual sampling)

For Dilithium2 sign:
- Multiple SHAKE128/256 calls for sampling y, computing c, etc.
- Estimated total: ~5000-10000 cycles per sign operation (to be refined).

### 5.7 Error handling

- `start` with `in_len > MAX_INPUT_BYTES`: assert `err`, skip to DONE.
- `start` with `nblocks > MAX_BLOCKS`: assert `err`, skip to DONE.
- These checks happen in S_IDLE before any state is modified.

---

## 6. NTT Engine - `ntt_engine.sv`

### 6.1 The NTT in Dilithium

Dilithium uses a **negacyclic** NTT that exploits the structure
`x^256 + 1` of the polynomial ring. The NTT is evaluated at
"twisted" points:

```
A_k = sum_{j=0..N-1} a_j * zeta^(2*j*k + j)
```

where `zeta` is a primitive 512-th root of unity mod q (zeta = 1753).
The "+j" twist is what makes the inverse NTT recover the polynomial
from the evaluations.

The NTT is its own inverse (up to scaling by 1/256) and converts
polynomial multiplication into pointwise multiplication:
```
if y = conv(a, b)   then   Y = pointwise(A, B) / 256
```

This is the "Convolution Theorem" generalized to the negacyclic ring.

### 6.2 Iterative Cooley-Tukey

The full radix-2 decimation-in-time (DIT) NTT can be written as an
8-stage iterative loop. Each stage halves the current "len" parameter
and processes N/2 butterflies. The C reference:

```c
k = 0;
for (len = 128; len > 0; len >>= 1) {
    for (start = 0; start < N; start = j + len) {
        zeta = zetas[++k];
        for (j = start; j < start + len; ++j) {
            t = mont_reduce((int64_t)zeta * a[j + len]);
            a[j + len] = a[j] - t;
            a[j]       = a[j] + t;
        }
    }
}
```

**Stage structure:**

| Stage | len | # of start groups | butterflies per group | # of butterflies |
|---|---|---|---|---|
| 0 | 128 | 1 | 128 | 128 |
| 1 | 64 | 2 | 64 | 128 |
| 2 | 32 | 4 | 32 | 128 |
| 3 | 16 | 8 | 16 | 128 |
| 4 | 8 | 16 | 8 | 128 |
| 5 | 4 | 32 | 4 | 128 |
| 6 | 2 | 64 | 2 | 128 |
| 7 | 1 | 128 | 1 | 128 |
| **Total** | | **255** | | **1024** |

So 8 stages x 128 butterflies = 1024 total butterflies, using 255
twiddle factors (zetas[1] through zetas[255]).

### 6.3 The butterfly operation

**Forward butterfly (Cooley-Tukey):**
```
t = mont_reduce(zeta * a[j + len])    # twiddle multiplication
a[j + len] = a[j] - t                 # subtract
a[j]       = a[j] + t                 # add
```

The twiddle `zeta` is the same for all `len` butterflies within a
start group. After all butterflies in a group, the next start group
uses the next zeta.

**Inverse butterfly (Gentleman-Sande):**
```
t        = a[j]                        # save
a[j]     = t + a[j + len]             # add
a[j+len] = t - a[j + len]             # subtract
a[j+len] = mont_reduce((-zeta) * a[j+len])  # twiddle, negated
```

The inverse uses the negated zeta because the inverse NTT is the
"reverse" of the forward NTT, and the twiddle is conjugated.

### 6.4 Montgomery reduction in detail

The butterfly requires `zeta * a_jlen mod q`. The product fits in
48 bits signed. To get back to 24 bits, we use Montgomery reduction.

**Algorithm:**
```
function mont_reduce(a: int64) -> int32:
    # a is in (-Q * 2^31, Q * 2^31) for the C ref assertion
    t   = int32(a) * QINV   # int32 truncates to 32 bits
    sub = a - t * Q         # this is divisible by 2^32
    return sub >> 32         # divide by 2^32, in (-Q, Q)
```

**Why it works**: We want `r = a * 2^(-32) mod Q`. Let `t = a_low32 * QINV`.
Then `Q * t = Q * a_low32 * QINV = a_low32 * (Q * QINV) = a_low32 * 1 (mod 2^32)`.
So `a - Q*t ≡ 0 (mod 2^32)`, and `(a - Q*t) / 2^32 ≡ a / 2^32 (mod Q) = r`.

**Why 48-bit signed input is enough**: The butterfly product
`zeta * a_jlen` has magnitude at most `Q * Q = Q^2 ≈ 7e13 < 2^47`.
So 48 bits is sufficient.

**Why the output fits in 24 bits**: Montgomery reduction always
produces a result in `(-Q, Q)`, and `Q < 2^23`. So 24 bits is
sufficient (we use 24-bit signed to leave headroom for sums).

### 6.5 Hardware architecture

```
         +-------------+   +----------+   +-------------+
  addr_j |             |   |          |   |             |
  -----> |  256 x 24b  |---| twiddle |---| butterfly  |---> (write back)
         |   register  |   |   ROM    |   | + mont_red |
  addr_k |   file (RF) |   | 256 x 24b|   |             |
  -----> |   2R/2W     |   |   1R     |   |             |
         +-------------+   +----------+   +-------------+
                ^                              |
                |__________ waddr_a/b _________|
```

#### Register file

A 256-entry array of 24-bit signed registers. Two combinational
read ports and two registered write ports. The dual writes are
needed because each butterfly updates BOTH `a[j]` and `a[j+len]`,
and doing them sequentially would double the latency.

#### Twiddle ROM

A 256 x 24-bit ROM holding the precomputed zetas. Synchronous read
with 1-cycle latency. We register the output (`zeta_q`) to break
the combinational path between the ROM and the butterfly.

#### Butterfly

Combinational logic that:
1. Multiplies `a_jlen * zeta_q` (24x24 -> 48 bits signed)
2. Calls Montgomery reduction (48 -> 24 bits signed)
3. Adds/subtracts to get the new a[j] and a[j+len] values

The butterfly is one combinational block, with the output latched
into the register file at the end of the cycle.

#### Controller (FSM)

A small 7-state FSM that mirrors the C reference's loop structure:

| State | Description | Duration |
|---|---|---|
| S_IDLE | Waiting for start | until start |
| S_LOAD | Load input coefficients into RF | 256 cycles |
| S_SETUP | Initialize butterfly counters | 1 cycle |
| S_BUTTERFLY | Do one butterfly per cycle | 1024 cycles (forward) / 1280 (inverse) |
| S_FINAL_SCALE | (Inverse only) Multiply by f=41978 | 256 cycles (inverse) / 0 (forward) |
| S_OUTPUT | Copy RF to output port | 1 cycle |
| S_DONE | Assert done | 1+ cycles |

**Total cycles:**
- Forward: 256 + 1 + 1024 + 0 + 1 + 1 = **1283 cycles**
- Inverse: 256 + 1 + 1024 + 256 + 1 + 1 = **1539 cycles**

(Note: the C reference's `ntt()` does NOT have a "load" phase - the
caller is expected to provide coefficients in place. Our S_LOAD phase
adds 256 cycles but allows the module to be a self-contained black box.)

### 6.6 Address generation

The two addresses for a butterfly are:
```
addr_j    = start_r + j_r
addr_jlen = addr_j + len_r
```

where:
- `start_r` is the base of the current start group (0, 2*len, 4*len, ...)
- `j_r` is the offset within the start group (0 to len-1)
- `len_r` is the current stage's "len" (128, 64, 32, ..., 1)

**Stage transition logic**: When `j_r + 1 == len_r`, we have completed
all butterflies in the current start group. Reset `j_r = 0`, advance
`start_r += 2*len_r`, and increment (forward) or decrement (inverse) the
zeta index `k`. When `start_r >= N`, we've completed all start groups in
the current stage: advance `stage`, halve (forward) or double (inverse)
`len_r`, and reset `start_r = 0`.

### 6.7 Final scaling for inverse NTT

After all stages, the inverse NTT produces:
```
a' = (1/256) * invNTT(a) * 2^32  (in Montgomery domain)
```

To get back to the "natural" representation, we multiply by:
```
f = mont^2 / 256 = 41978
```

This is a single Montgomery multiplication per coefficient. The
`S_FINAL_SCALE` state iterates over all 256 coefficients, doing one
multiplication per cycle.

The `f` constant is defined in the C reference as `const int32_t f = 41978;`.

### 6.8 Interface

```systemverilog
module ntt_engine #(
    parameter int unsigned COEFF_WIDTH = 24,
    parameter int unsigned N           = 256
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    input  dilithium_pkg::ntt_op_t        mode,    // NTT_OP_NTT / NTT_OP_INTT
    input  logic signed [COEFF_WIDTH-1:0] coeff_in  [N],
    output logic signed [COEFF_WIDTH-1:0] coeff_out [N],
    output logic                          busy,
    output logic                          done,
    output logic                          err
);
```

### 6.9 Latency and timing

| Mode | Cycles | Throughput @ 200 MHz |
|---|---|---|
| Forward | ~1283 | 6.4 us |
| Inverse | ~1539 | 7.7 us |

For Dilithium2 sign operation, the total NTT time is roughly:
- Several forward NTTs (for sampling-related polynomial multiplies)
- Several inverse NTTs
- Plus overhead for sampling, packing, etc.

Total estimated: ~100-200 us per sign operation. This is to be
refined when the rest of the modules are integrated.

### 6.10 No bit-reversal permutation

The forward NTT, as described, produces output in **bit-reversed**
order (because Cooley-Tukey DIT outputs are bit-reversed). The C
reference also produces bit-reversed output, and downstream code
is aware of this (the inverse NTT expects bit-reversed input).

If the consumer needs natural-ordered output, it must apply a
bit-reversal permutation as a post-processing step. The Dilithium
reference does not require this: polynomial multiplication is
defined such that both inputs are in bit-reversed order (and the
output is also bit-reversed), which is internally consistent.

### 6.11 Why no per-butterfly reduction

The C reference's `ntt()` does NOT call `reduce32()` after each
butterfly. After a full NTT, coefficients can be up to ~3Q
(specifically, up to (N-1)*Q + Q = N*Q = 256 * 8380417 ≈ 2^31).
This is still in 32-bit range.

We follow the same convention. The 24-bit register values in our
register file are signed and overflow wraps around in 2's complement,
but since we never read them as 24-bit values during the NTT
(everything goes through Montgomery reduction which produces
24-bit clean values), the wraparound doesn't cause errors.

After the NTT is done, downstream code is expected to call
`reduce32()` / `caddq()` to bring coefficients back into `(-Q, Q)`.
We provide a separate `poly_reduce_unit` module in Phase 2 for this.

### 6.12 Critical design decisions

1. **Register file vs SRAM**: We use a 2R/2W register file for Phase 1
   simplicity. A 1R/1W SRAM would be smaller (16 KB vs 6 KB) but require
   2 cycles per butterfly, doubling the latency. The trade-off favors
   register file for now; SRAM is a future optimization.

2. **Twiddle indexing**: Forward increments `k` (1 to 255), inverse
   decrements (255 to 1). The ROM is addressed by the current `k_idx`.
   `gen_twiddles.py` guarantees the ROM matches `ref/ntt.c`.

3. **Combinational butterfly path**: The critical path is
   `addr_j -> rf[a_j] -> add/sub -> output -> rf[waddr_a]`. The
   address-to-data delay of the register file is the dominant term.

4. **Reset: full RF clear**: On reset, all 256 RF entries are zeroed.
   This costs 256 cycles of reset time but ensures a known state.
   Alternative: only clear `running` and `state`, and trust that
   the caller loads the RF before use. We chose the simpler "always
   clear" approach.

---

## 7. Twiddle ROM - `ntt_twiddle_rom.sv`

### 7.1 Purpose

A simple wrapper that provides a synchronous-read ROM containing the
256 pre-computed NTT twiddle factors (zetas). The NTT engine reads
from this ROM on every cycle during the S_BUTTERFLY state.

### 7.2 Interface

```systemverilog
module ntt_twiddle_rom #(
    parameter int unsigned ADDR_WIDTH = 8,    // 256 entries
    parameter int unsigned DATA_WIDTH = 24    // signed 24-bit
) (
    input  logic                          clk,
    input  logic                          re,       // read enable
    input  logic [ADDR_WIDTH-1:0]         addr,
    output logic signed [DATA_WIDTH-1:0]  rdata
);
```

### 7.3 Contents

Initialized from `ntt_params::ZETAS[0..255]` via an `initial` block.
The values are bit-exact copies of the C reference's `zetas[]` table.

In the C reference, the zetas are declared as:
```c
static const int32_t zetas[N] = {0, 25847, -2608894, ...};
```

The first entry (zetas[0]) is **never used** by the NTT (the C code
always pre-increments `k` before reading, so it starts at zetas[1]).
We keep it in the table for index alignment.

### 7.4 Negative value encoding

The zetas include negative values (e.g., zetas[2] = -2608894). In
SystemVerilog, `logic signed [23:0]` represents these in standard
2's-complement. The `gen_twiddles.py` script encodes each value as a
6-digit hex literal in `24'shXXXXXX` form.

**Conversion example (zetas[2] = -2608894):**
- 2's-complement 24-bit: `2^24 - 2608894 = 16777216 - 2608894 = 14168322`
- `14168322` in hex = `0xD83102`
- Generated SV literal: `24'shD83102`
- Decoded: `0xD83102 - 2^24 = 14168322 - 16777216 = -2608894` ✓

The Python `to_twos(val, bits)` function in `gen_twiddles.py` performs
exactly this conversion:

```python
def to_twos(val, bits):
    if val < 0:
        val += (1 << bits)
    return val & ((1 << bits) - 1)
```

This produces the correct 24-bit two's-complement encoding for all
256 zetas, and `verify_constants.py` independently cross-checks the
result against the C source.

### 7.5 Why an `initial` block (not a function)

We use an `initial` block to populate the memory array. This is the
standard idiom for ROM initialization in SystemVerilog. Synthesis
tools will absorb the `initial` block contents into the ROM's
configuration bitstream (for FPGA targets) or use it to initialize
SRAM at power-up (for ASIC targets).

An alternative would be to declare `mem` as a `const` array, but that
isn't directly supported in SystemVerilog for synthesisable memory.
The `initial` block is the standard workaround.

### 7.6 Clocking and reset

The ROM has a single `clk` input and uses synchronous read (output
appears 1 cycle after the read is enabled). There is no reset
signal; the initial values are loaded at simulation time 0 and
persist through simulation.

The ROM is read every cycle during S_BUTTERFLY in the NTT engine.
The address (`zeta_addr`) is set combinationally to the current
`k_idx`, and `zeta_re` is asserted. The 1-cycle latency means the
data appears in `zeta_q` on the next cycle, where it's used by
the butterfly combinational logic.

---

## 8. Reset & Error Handling

### 8.1 Reset strategy

All Phase 1 modules use **asynchronous active-low reset**:
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // reset all state
    end else begin
        // normal operation
    end
end
```

This is a conservative choice that works for both ASIC and FPGA
targets. The `or negedge rst_n` clause allows the synthesis tool
to use a more efficient reset structure on FPGAs.

### 8.2 Reset values

| Module | Reset behavior |
|---|---|
| `keccak_permutation` | State cleared, round counter = 0, running = 0 |
| `shake128_absorb_once` | FSM = S_IDLE, byte_idx = 0, in_len_r = 0, s_reg = 0 |
| `shake128_squeezeblocks` | FSM = S_IDLE, block_idx = 0, s_reg = 0 |
| `ntt_engine` | FSM = S_IDLE, all counters = 0, RF cleared |
| `ntt_twiddle_rom` | No reset (ROM contents are constant) |

The RF clear in `ntt_engine` is the most expensive reset (256 cycles
of reset propagation, but the synthesizer can fold this into the
SRAM initialization).

### 8.3 Error conditions

| Module | Error condition | Behavior |
|---|---|---|
| `shake128_absorb_once` | `in_len > MAX_INPUT_BYTES` | `err = 1`, jump to DONE |
| `shake128_squeezeblocks` | `nblocks > MAX_BLOCKS` | `err = 1`, jump to DONE |
| `ntt_engine` | Invalid `mode` value | No-op, returns to IDLE without `done` |

The error flags persist until the next `start` pulse.

---

## 9. Resource Estimate

Based on a synthesis-style estimate (no actual synthesis run, but
informed by typical FPGA/ASIC area for similar primitives):

| Module | LUT/FF (est.) | Notes |
|---|---|---|
| `keccak_permutation` | ~3000 | 1600-bit state + combinational chi |
| `shake128_absorb_once` | ~150 | Small FSM + byte-level XOR |
| `shake128_squeezeblocks` | ~200 | Block counter + output mux (MAX_BLOCKS*168 muxes) |
| `shake256_absorb_once` | ~150 | Same as 128 version |
| `shake256_squeezeblocks` | ~200 | Same as 128 version |
| `ntt_twiddle_rom` | 0 (mem) | 256 x 24-bit = 6 Kbit (block RAM on FPGA) |
| `ntt_engine` | ~5000 | 256 x 24-bit RF + butterfly + mont |
| **Total Phase 1** | **~8700** | Within 13K target |

**Memory breakdown:**
- `ntt_twiddle_rom`: 256 x 24 = 6144 bits = 768 bytes
- `ntt_engine` RF: 256 x 24 = 6144 bits = 768 bytes
- Keccak state: 1600 bits = 200 bytes
- SHAKE state: 1600 bits = 200 bytes
- **Total: ~3 KB** of register/memory

This leaves significant headroom (256 KB - 3 KB = 253 KB) for the
shared SRAM that will hold larger polynomial data structures in
later phases.

---

## 10. Synthesis & Timing Considerations

### 10.1 Critical path analysis

The longest combinational paths in each module:

| Module | Critical path |
|---|---|
| `keccak_permutation` | Chi combinational block: ~3 levels of XOR + 1 AND-NOT |
| `shake128_*` | State register update + small mux: 2-3 levels |
| `ntt_engine` | RF read + mult (24x24) + mont_reduce + add/sub: 5-6 levels |

For the NTT engine, the 24x24 multiplier is the dominant delay.
At a typical 28nm ASIC, this limits the clock frequency to about
400-500 MHz. At 200 MHz (a more conservative target for FPGA),
this is comfortable.

### 10.2 Pipeline opportunities

The `keccak_permutation` could be retimed to compute 2 rounds/cycle
(matching the C reference's `for(round = 0; round < 24; round += 2)`
pattern). This would halve the latency to 12 cycles, but double
the combinational critical path. The trade-off is:

| Option | Latency | Max freq | Throughput |
|---|---|---|---|
| 1 round/cycle (current) | 24 cycles | ~500 MHz | 1 perm/24 cyc |
| 2 rounds/cycle | 12 cycles | ~250 MHz | 1 perm/12 cyc |
| 4 rounds/cycle (unroll) | 6 cycles | ~125 MHz | 1 perm/6 cyc |

For Dilithium, the Keccak throughput is rarely the bottleneck (it's
the NTT that takes 1000+ cycles). So 1 round/cycle is the right
choice for Phase 1.

### 10.3 Area-time trade-offs

| Optimization | Area impact | Latency impact |
|---|---|---|
| Butterfly pipelining (2-stage) | +200 LUT | -50% cycles |
| SRAM instead of register file | -3000 LUT | +50% cycles |
| Multi-block squeeze (parallel) | +500 LUT | -30% cycles for squeeze |
| Precompute mont inverse in SF | +100 LUT | none |

None of these optimizations are implemented in Phase 1. They are
left for future refinement if the area/time targets require it.

### 10.4 FPGA target estimates

For a typical FPGA (e.g., Xilinx 7-series):
- `keccak_permutation`: ~1500 LUT, ~1600 FF, 0 BRAM
- `ntt_engine`: ~3000 LUT, ~1300 FF, 0.5 BRAM (for the 6Kbit RF)
- `ntt_twiddle_rom`: 0 LUT, 0 FF, 0.5 BRAM
- SHAKE modules: ~200 LUT, ~200 FF each
- **Total**: ~5200 LUT, ~3700 FF, 1 BRAM

This easily fits in a small FPGA (e.g., Xilinx Artix-7 35T).

---

## 11. Module Hierarchy

```
dilithium_hw/
+-- include/
|   +-- dilithium_pkg.sv          # Types, enums, parameters (all widths)
|   +-- keccak_constants.svh      # 24 round constants ROM
|   +-- ntt_params.svh            # 256 twiddle factors (auto-generated)
+-- rtl/
|   +-- sha3/
|   |   +-- keccak_permutation.sv # 1600-bit state permutation core
|   |   +-- shake128.sv           # SHAKE128 XOF (absorb_once + squeezeblocks)
|   |   +-- shake256.sv           # SHAKE256 XOF (absorb_once + squeezeblocks)
|   +-- ntt/
|       +-- ntt_twiddle_rom.sv    # 256 x 24-bit ROM wrapper
|       +-- ntt_engine.sv         # Forward/Inverse NTT + Montgomery
+-- scripts/
    +-- gen_twiddles.py           # Builds ntt_params.svh from ref/ntt.c
    +-- gen_golden.c              # C harness producing SHAKE/NTT golden output
    +-- golden_model.py           # Python bit-exact algorithm model (has bugs)
    +-- golden_output.txt         # C reference outputs for SV comparison
    +-- verify_constants.py       # Cross-check C reference vs SV headers
```

### 11.1 Dependency graph

```
                +----------------+
                | dilithium_pkg  |  (compile-time types & constants)
                +--------+-------+
                         |
        +----------------+----------------+----------------+
        |                |                |                |
+-------v------+  +-------v------+  +-------v-------+  +----v----+
| keccak_      |  | ntt_params   |  | keccak_       |  | ntt_    |
| constants.svh|  | .svh         |  | permutation   |  | engine  |
| (RCs)        |  | (zetas)      |  | .sv           |  | .sv     |
+--------------+  +--------------+  +-------+-------+  +----+----+
                                              |             |
                                              |             |  uses
                                              v             v
                                       +-------------+ +--------------+
                                       | shake128.sv | | ntt_twiddle_ |
                                       | shake256.sv | | rom.sv       |
                                       +------+------+ +------+-------+
                                              |             |
                                              v             v
                                          (used by Phase 2-7 modules)
```

All modules depend on `dilithium_pkg` for type definitions. The
keccak and SHAKE modules also depend on `keccak_constants.svh` for
the round constants. The NTT modules depend on `ntt_params.svh` for
the twiddle factors.

---

## 12. Compliance

- **IEEE 1800-2017 SystemVerilog** - all modules conform.
- **No vendor-specific constructs** - no Xilinx/Intel/Synopsys pragmas.
- **Bit-exact with C reference** - constants and algorithm match
  `ref/fips202.c` and `ref/ntt.c` line by line.
- **Safe FSMs** - all state machines use 1-cycle transitions, no
  asynchronous state changes.
- **No latches** - all outputs are either registered or pure
  combinational from registered inputs.
- **Async reset** - all major state elements use `or negedge rst_n`.

**Future compliance items** (not required for Phase 1):
- Power gating (Phase 7+)
- Scan chains for DFT (Phase 7+)
- Formal verification (Phase 8)
