# Dilithium

[![Build Status](https://travis-ci.org/pq-crystals/dilithium.svg?branch=master)](https://travis-ci.org/pq-crystals/dilithium) [![Coverage Status](https://coveralls.io/repos/github/pq-crystals/dilithium/badge.svg?branch=master)](https://coveralls.io/github/pq-crystals/dilithium?branch=master)

**Dilithium** is a post-quantum digital signature scheme standardized as [FIPS 204](https://csrc.nist.gov/pubs/fips/204/final) by NIST. It is based on the hardness of the Module Learning With Errors (MLWE) problem over NTRU lattices.

This repository contains:
- **Reference implementation** in C (clean, portable code)
- **AVX2-optimized implementation** for x86 CPUs with AVX2/BMI2 instructions

## Background

Dilithium belongs to the "Cryptographic Suite for Algebraic Lattices" (CRYSTALS) alongside Kyber (KEM). It uses:
- **NTRU lattice** with Module structure
- **Ring Learning With Errors (RLWE)** hardness assumption
- **SHAKE-128/256** (FIPS 202) for hashing and entropy
- **Number Theoretic Transform (NTT)** for efficient polynomial multiplication

## Parameter Sets

| Parameter Set | Public Key | Secret Key | Signature | Security Level |
|---------------|------------|------------|-----------|----------------|
| **Dilithium2** | 1,312 B | 2,560 B | 2,420 B | NIST Level 2 |
| **Dilithium3** | 1,952 B | 4,032 B | 3,309 B | NIST Level 3 |
| **Dilithium5** | 2,592 B | 4,896 B | 4,627 B | NIST Level 5 |

**Core Parameters** (shared across all sets):
- Polynomial degree N = 256
- Modulus q = 8,380,417
- NTT modulus: primitive root of unity 1753

## Project Structure

```
dilithium/
├── ref/                    # Reference C implementation
│   ├── sign.c              # Key generation, signing, verification
│   ├── poly.c              # Polynomial operations (NTT, pointwise mult)
│   ├── polyvec.c           # Vector of polynomials
│   ├── fips202.c           # SHAKE-128/256 (Keccak-p1600)
│   ├── packing.c           # Serialize/deserialize signatures
│   ├── rounding.c          # Power-of-two rounding
│   ├── reduce.c            # Modular reduction
│   ├── ntt.c               # Number Theoretic Transform
│   ├── test/               # Test programs
│   └── nistkat/            # NIST KAT test vectors
├── avx2/                   # AVX2-optimized x86 implementation
│   ├── poly.c              # Vectorized polynomial ops (AVX2)
│   ├── sign.c              # Optimized signing/verification
│   └── test/
├── *.yml                   # META configuration files
└── *.sh                    # Test scripts
```

## Building

### Prerequisites

- C compiler (gcc or clang recommended)
- OpenSSL (optional, for NIST KAT tests)
- For AVX2: x86 CPU with AVX2 and BMI2 instruction sets

### Build Commands

```bash
# Build reference implementation
make -C ref

# Build AVX2 optimized (amd64 only)
make -C avx2

# Build with sanitizers (debug)
export CC=/usr/bin/clang
export CFLAGS="-fsanitize=undefined,address"
make -C ref clean && make -C ref

# Build shared libraries
make -C ref shared
```

### Build Outputs

After building `ref/` or `avx2/`, you get:

| Binary | Purpose |
|--------|---------|
| `test/test_dilithium2/3/5` | Functional tests (10,000 iterations) |
| `test/test_vectors2/3/5` | Deterministic test vectors for compatibility |
| `test/test_speed2/3/5` | Performance benchmarking |
| `test/test_mul` | Polynomial multiplication test |

### macOS OpenSSL Setup

```bash
brew install openssl
export CFLAGS="-I/opt/homebrew/opt/openssl@1.1/include"
export NISTFLAGS="-I/opt/homebrew/opt/openssl@1.1/include"
export LDFLAGS="-L/opt/homebrew/opt/openssl@1.1/lib"
```

## API Usage

### Function Signatures

```c
// Key Generation
int crypto_sign_keypair(uint8_t *pk, uint8_t *sk);

// Detached signature (recommended)
int crypto_sign_signature(uint8_t *sig, size_t *siglen,
                         const uint8_t *m, size_t mlen,
                         const uint8_t *ctx, size_t ctxlen,
                         const uint8_t *sk);

// Combined signature (message + signature in one buffer)
int crypto_sign(uint8_t *sm, size_t *smlen,
                const uint8_t *m, size_t mlen,
                const uint8_t *ctx, size_t ctxlen,
                const uint8_t *sk);

// Verification
int crypto_sign_verify(const uint8_t *sig, size_t siglen,
                       const uint8_t *m, size_t mlen,
                       const uint8_t *ctx, size_t ctxlen,
                       const uint8_t *pk);

// Open combined signature
int crypto_sign_open(uint8_t *m, size_t *mlen,
                     const uint8_t *sm, size_t smlen,
                     const uint8_t *ctx, size_t ctxlen,
                     const uint8_t *pk);
```

### Example Usage

```c
#include "api.h"

uint8_t pk[CRYPTO_PUBLICKEYBYTES];
uint8_t sk[CRYPTO_SECRETKEYBYTES];
uint8_t sig[CRYPTO_BYTES];
uint8_t msg[] = "Hello, post-quantum world!";
size_t siglen, mlen;

// Generate keypair
crypto_sign_keypair(pk, sk);

// Sign message
crypto_sign_signature(sig, &siglen, msg, sizeof(msg)-1, NULL, 0, sk);

// Verify signature
int valid = crypto_sign_verify(sig, siglen, msg, sizeof(msg)-1, NULL, 0, pk);
```

### Context Parameter

The `ctx` parameter allows binding the signature to an application-specific context (e.g., a protocol version, user ID). Pass `NULL` with `ctxlen=0` if not used.

## Signing Modes

### Randomized Signing (Default)

Dilithium uses **hedged signing** by default, which randomizes the signing process to provide forward security against future key compromises:

```c
#define DILITHIUM_RANDOMIZED_SIGNING  // Enabled by default
```

### Deterministic Signing

To disable randomization:

```bash
# Option 1: Compile flag
make -C ref CFLAGS="-UDILITHIUM_RANDOMIZED_SIGNING"

# Option 2: Edit config.h
// #define DILITHIUM_RANDOMIZED_SIGNING  // Comment out
```

## Algorithm Flow

Dilithium is based on the ** Fiat-Shamir with Aborts** technique. The signature scheme uses a lattice-based identification protocol converted to a signature scheme through the Fiat-Shamir transformation.

### Key Generation (`crypto_sign_keypair`)

```
1. Generate random seed (32 bytes)
   └─> Expand via SHAKE-256 to get ρ (rho), ρ' (rhoprime), κ (key)

2. Expand matrix A from seed ρ (K×L matrix of polynomials)
   └─> Uses rejection sampling to ensure uniform distribution

3. Sample secret vectors s1, s2 from binomial distribution
   └─> s1: L polynomials (small coefficients, ETA-bounded)
   └─> s2: K polynomials (small coefficients, ETA-bounded)

4. Compute t = A·s1 + s2
   └─> A (K×L) × s1 (L) → t (K)
   └─> Uses NTT for polynomial multiplication

5. Power-of-two round t → (t1, t0)
   └─> t1: high bits (GAMMA2 precision)
   └─> t0: low bits (GAMMA2 precision)

6. Output:
   └─> Public key: (ρ, t1)
   └─> Secret key: (ρ, t0, s1, s2, tr) where tr = H(pk)
```

### Signing (`crypto_sign_signature`)

```
1. Compute μ = CRH(tr, pre, msg)
   └─> Hash of secret key trace, prefix, and message

2. Compute ρ' = CRH(key, rnd, μ)
   └─> rnd: 32 bytes random (hedged signing) or zero (deterministic)

3. Sample vector y with high entropy (GAMMA1-bounded)

4. (Rejection loop):
   a. w = A·y (K polynomials)
   b. Decompose w → (w1, w0) using high/low bit splitting
   c. c = H(μ, w1)  (challenge from hash)
   d. z = y + c·s1 (check: ||z|| < GAMMA1)
   e. cs2 = c·s2 (check: ||w0 - cs2|| < GAMMA2)
   f. Compute hint h for w1 recovery
   g. If checks pass: output signature (c, z, h)
```

### Verification (`crypto_sign_verify`)

```
1. Compute μ = CRH(H(pk), pre, msg)

2. Unpack signature (c, z, h) and public key (ρ, t1)

3. Reconstruct w1 from c, z, t1, h
   └─> w1 = use_hint(Az - c·2^d·t1, h)

4. Verify c == H(μ, w1)
   └─> If match: signature valid
   └─> If mismatch: signature invalid
```

### Core Components Used

| Component | File | Purpose |
|-----------|------|---------|
| **NTT** | `ntt.c`, `poly.c` | Number Theoretic Transform for polynomial multiplication |
| **Keccak/SHAKE** | `fips202.c` | SHAKE-128/256 hash functions for extendable output |
| **Polynomial** | `poly.c` | Operations on degree-256 polynomials modulo q |
| **PolyVec** | `polyvec.c` | Vector operations on arrays of polynomials |
| **Rounding** | `rounding.c` | Power-of-two decomposition and hint generation |
| **Packing** | `packing.c` | Serialize signatures/keys to compact byte representation |
| **Reduction** | `reduce.c` | Modular arithmetic optimization |

### Polynomial Format

```
Each poly = array of 256 int32 coefficients
- Coefficients in range [0, q-1] where q = 8380417
- Operations in Montgomery domain for efficient multiplication
- NTT transforms: R[x]/(x^256 + 1) ↔ Z_q^256
```

### Lattice Structure

Dilithium uses a **module lattice** with:
- Ring: R = Z_q[x]/(x^n + 1) with n = 256
- Module rank k and dimension l vary by parameter set
- Security based on Module RLWE hardness

## Testing

```bash
# Run full test suite (both ref and avx2 on amd64)
./runtests.sh

# Run individual tests
./ref/test/test_dilithium2
./ref/test/test_vectors2

# Coverage report
./runlcov.sh
```

### Test Results

**Build Status**: ✓ Successful (gcc, amd64)

**Functional Tests** (`test_dilithium`):
- 10,000 iterations per parameter set
- Key generation → Sign → Verify → Open cycle validation
- Random byte corruption detection
- All tests returned 0 (success)

| Parameter Set | Public Key | Secret Key | Signature |
|---------------|------------|------------|-----------|
| **Dilithium2** | 1,312 B | 2,560 B | 2,420 B |
| **Dilithium3** | 1,952 B | 4,032 B | 3,309 B |
| **Dilithium5** | 2,592 B | 4,896 B | 4,627 B |

**Test Vectors** (`test_vectors`):
- Deterministic intermediate values for compatibility testing
- Covers: seed, matrix A, secret vector s, y, w, w1, w0, t1, t0, challenge c
- All outputs match expected values

## Performance

**Reference implementation** is unoptimized for readability; do not benchmark `ref/`.

**AVX2 benchmarks** on Intel KabyLake (cycles):

| Operation | Dilithium2 | Dilithium3 | Dilithium5 |
|-----------|------------|------------|------------|
| KeyGen    | ~150K      | ~300K      | ~500K      |
| Sign      | ~300K      | ~600K      | ~1M        |
| Verify    | ~100K      | ~200K      | ~350K      |

Full SUPERCOP results: [bench.cr.yp.to](http://bench.cr.yp.to/results-sign.html#amd64-kizomba)

## Security Notes

- **Post-quantum security**: Protected against quantum attacks via MLWE/Lattice hardness
- **No experimental/heuristic assumptions**: Security reducible to worst-case lattice problems
- **Constant-time operations**: Poly/crypto operations avoid secret-dependent branches
- **Forward security**: Randomized signing limits exposure if secret key is later compromised

## References

- [FIPS 204 (Official Standard)](https://csrc.nist.gov/pubs/fips/204/final)
- [Dilithium Website](https://www.pq-crystals.org/dilithium/)
- [Security Analysis Paper](https://eprint.iacr.org/2017/619)
- [SUPERCOP Benchmarking](https://bench.cr.yp.to)

## License

See [LICENSE](LICENSE) file. Implementation by the CRYSTALS team (Bos, Ducas, Kiltz, Lepoint, Lyubashevsky, Schanck, Schwabe, Stebila, Ward).
