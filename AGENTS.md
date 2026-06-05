# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-05
**Commit:** d35ba3f
**Branch:** dev-delta

## OVERVIEW
Dilithium post-quantum digital signature scheme (FIPS 204). Reference C implementation + AVX2-optimized x86 implementation. Three parameter sets: Dilithium2/3/5.

## STRUCTURE
```
dilithium/
├── ref/           # Reference C implementation
│   ├── test/      # Test programs
│   └── nistkat/   # NIST KAT test vectors
├── avx2/          # AVX2-optimized x86 implementation (symlinks most files to ref/)
│   └── test/
├── *.yml          # META configs for each parameter set
└── *.sh           # Test scripts
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Core signing | `ref/sign.c`, `avx2/sign.c` | Main API: `crypto_sign_keypair`, `crypto_sign`, `crypto_sign_open` |
| Polynomial ops | `ref/poly.c`, `avx2/poly.c` | NTT, pointwise multiplication |
| SHA3/FIPS202 | `ref/fips202.c` | Keccak-p1600 permutation |
| API definitions | `ref/api.h`, `avx2/api.h` | Key/signature sizes by parameter set |
| Build configs | `ref/Makefile`, `avx2/Makefile` | Mode flags: `-DDILITHIUM_MODE=2\|3\|5` |

## BUILD & TEST
```bash
# Build reference implementation
make -C ref

# Build AVX2 (amd64 only)
make -C avx2

# Run tests (both implementations on amd64)
./runtests.sh

# Coverage report
./runlcov.sh

# Manual test per algorithm
./ref/test/test_dilithium2  # or 3, 5
./avx2/test/test_dilithium2
```

## CONVENTIONS
- **Algorithms**: Dilithium2 (q=8380417, k=4, l=4), Dilithium3 (q=8380417, k=6, l=5), Dilithium5 (q=8380417, k=8, l=7)
- **Mode flags**: Compile with `-DDILITHIUM_MODE=2|3|5` to select parameter set
- **Randomized signing**: Enabled by default; undef `DILITHIUM_RANDOMIZED_SIGNING` in `config.h` or add `-UDILITHIUM_RANDOMIZED_SIGNING` to disable
- **Symmetric crypto**: Uses SHAKE-128/256 (FIPS 202) for hash and entropy

## ANTI-PATTERNS (THIS PROJECT)
- Do NOT run `make speed` on `ref/` - it's unoptimized, results are meaningless
- Do NOT compile AVX2 on non-x86 hardware - requires AVX2 + BMI2 instruction sets
- Do NOT link against OpenSSL shared libs without `-L` and `-I` flags on macOS via Homebrew

## COMMANDS
```bash
# Full clean build and test
make -C ref clean && make -C ref && ./runtests.sh

# Build shared libraries
make -C ref shared

# Build with AddressSanitizer/UBSan (amd64/arm64)
export CC=/usr/bin/clang
export CFLAGS="-fsanitize=undefined,address"
make -C ref clean && make -C ref

# Speed benchmarking (AVX2 only)
make -C avx2 speed
./avx2/test/test_speed2
```

## NOTES
- `avx2/` symlinks: `fips202.c`, `packing.c`, `packing.h`, `params.h`, `randombytes.c`, `randombytes.h`, `sign.h`, `symmetric-shake.c`
- Compiler flags in `ref/Makefile`: `-Wall -Wextra -Wpedantic -Wmissing-prototypes -Wshadow -Wvla -Wpointer-arith -O3 -fomit-frame-pointer`
- Travis CI tests on: gcc/clang, amd64/arm64/ppc64le/s390x
