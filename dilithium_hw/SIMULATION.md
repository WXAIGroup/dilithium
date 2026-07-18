# Dilithium Hardware IP Core - Simulation & Verification Guide (Phase 1)

**Project:** Dilithium Post-Quantum Digital Signature IP Core (FIPS 204)
**Document Version:** 1.0
**Date:** 2026-06-24
**Scope:** Phase 1 - how to simulate and verify the delivered modules

---

## 1. Overview

This guide explains how to verify that the Phase 1 SystemVerilog modules
(`keccak_permutation`, `shake128`, `shake256`, `ntt_engine`, `ntt_twiddle_rom`)
are functionally correct and bit-exact with the C reference implementation.

The verification strategy has three layers, listed from cheap to thorough:

1. **Static constant verification** (no simulator needed) - compares
   constants in the SV headers against the C reference.
2. **C reference execution** (no SV simulator needed) - runs the C
   reference's own self-tests and SHAKE/NTT golden output generation.
3. **RTL simulation** (requires Verilator/iverilog) - runs the SV modules
   in a testbench and compares against the C golden output.

The first two layers can be run today (no hardware simulator needed).
The third layer requires a SystemVerilog simulator.

---

## 2. Layer 1: Static Constant Verification

This is the fastest check. It cross-references the constants in the
SystemVerilog include files against the C reference sources.

### 2.1 What it verifies

| Constant | C source | SV location |
|---|---|---|
| Modulus `q` | `ref/params.h` | `include/dilithium_pkg.sv` |
| `QINV` | `ref/reduce.h` | `include/dilithium_pkg.sv` |
| SHA3/SHAKE rates | `ref/fips202.h` | `include/dilithium_pkg.sv` |
| 24 Keccak round constants | `ref/fips202.c` | `include/keccak_constants.svh` |
| 256 NTT zetas | `ref/ntt.c` | `include/ntt_params.svh` (generated) |

### 2.2 How to run

```bash
python3 dilithium_hw/scripts/verify_constants.py
```

Expected output (truncated):
```
PASS: Q=8380417 and QINV=58728449 match C reference exactly
PASS: All 256 NTT zetas match ref/ntt.c exactly
PASS: All 24 Keccak round constants match ref/fips202.c exactly
PASS: All SHA3/SHAKE rates match ref/fips202.h
...
ALL CHECKS PASSED (6/6)
```

If any check fails, the script prints the first 10 mismatches with both
the C and SV values. Common causes:
- Hand-edited values in SV that drifted from the C reference.
- A new Dilithium version that changed zetas (regenerate via
  `gen_twiddles.py`).

### 2.3 Regenerating NTT zetas

If `ref/ntt.c` is updated:

```bash
python3 dilithium_hw/scripts/gen_twiddles.py
```

This rewrites `include/ntt_params.svh` from the hard-coded zetas table in
the Python script (which is a verbatim copy of the C source). The
`gen_twiddles.py` script validates that all 256 zetas are in the valid
range `(-q, q)`.

---

## 3. Layer 2: C Reference Execution

The C reference implementation in `ref/` includes self-tests that exercise
the exact same Keccak/SHA3 and NTT code that we are translating.

### 3.1 Build the C reference

```bash
make -C ref                    # Builds test binaries for all 3 modes
make -C ref speed             # Also builds test_mul (NTT correctness)
```

### 3.2 Run the C reference tests

```bash
ref/test/test_mul             # Validates poly_mul -> NTT roundtrip
ref/test/test_dilithium2      # Full Dilithium2 sign/verify
ref/test/test_dilithium3
ref/test/test_dilithium5
ref/test/test_vectors2        # Deterministic test vectors
```

If `test_mul` exits 0, the C reference's NTT implementation is correct
(this is the same code that the SV engine implements).

### 3.3 Generate golden output vectors

```bash
# Build the golden generator
cc -O2 -Iref -DDILITHIUM_MODE=2 -o /tmp/gen_golden \
    dilithium_hw/scripts/gen_golden.c \
    ref/fips202.c ref/ntt.c ref/reduce.c

# Run it to produce golden output
/tmp/gen_golden > dilithium_hw/scripts/golden_output.txt
cat dilithium_hw/scripts/golden_output.txt
```

The `golden_output.txt` file contains:
- SHAKE128/256 outputs for empty and "abc" inputs
- Forward NTT of a small polynomial
- Inverse NTT roundtrip
- Montgomery reduction results for several test values

These are the **expected outputs** that the RTL simulation must reproduce.

---

## 4. Layer 3: RTL Simulation

This is the end-to-end verification. It requires a SystemVerilog simulator
(Verilator recommended, iverilog acceptable).

### 4.1 Prerequisites

Install one of:
```bash
# Verilator (preferred, fastest)
sudo apt install verilator   # Debian/Ubuntu
brew install verilator        # macOS

# Icarus Verilog (alternative)
sudo apt install iverilog
```

Verilator >= 4.200 is recommended for SystemVerilog 2017 support.

### 4.2 Testbench structure

The `tb/` directory is reserved for testbenches. Recommended file layout:

```
tb/
+-- tb_keccak_permutation.sv   # Keccak unit test
+-- tb_shake128.sv             # SHAKE128 unit test
+-- tb_shake256.sv             # SHAKE256 unit test
+-- tb_ntt_engine.sv           # NTT engine unit test
+-- tb_dilithium_top.sv        # Top-level (Phase 7+)
+-- compare_golden.py          # Python: parses VCD, compares to golden
```

These testbenches are not yet created (Phase 1 of the plan focused on
RTL). They are scheduled for Phase 8 (Verification) of the plan.

### 4.3 Suggested testbench pattern (skeleton)

For each module, the testbench:
1. Instantiates the DUT
2. Applies reset
3. Loads stimulus from a file (or generates random)
4. Pulses `start`, waits for `done`
5. Captures output, writes to VCD or $display
6. A Python post-processor compares the VCD/$display against `golden_output.txt`

Example skeleton for `tb_keccak_permutation.sv` (not yet written):

```systemverilog
module tb_keccak_permutation;
    logic clk, rst_n, start, busy, done;
    logic [1599:0] state_in, state_out;

    keccak_permutation #(.ROUNDS(24)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .busy(busy), .done(done),
        .state_in(state_in), .state_out(state_out)
    );

    initial begin
        clk = 0; forever #5 clk = ~clk;  // 100 MHz
        rst_n = 0; #20; rst_n = 1;
        // Test: zero state -> 1 permutation
        state_in = '0;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        @(posedge done);
        $display("KECCAK_ZERO_STATE: %032h %032h ...",
                 state_out[63:0], state_out[127:64]);
        $finish;
    end
endmodule
```

### 4.4 Compilation & run

```bash
# Verilator
verilator --binary -j 0 \
    --top-module tb_keccak_permutation \
    --timing \
    dilithium_hw/include/*.svh \
    dilithium_hw/rtl/sha3/keccak_permutation.sv \
    dilithium_hw/tb/tb_keccak_permutation.sv

./obj_dir/Vtb_keccak_permutation

# Icarus Verilog
iverilog -g2012 \
    -I dilithium_hw/include \
    -o /tmp/tb_keccak \
    dilithium_hw/rtl/sha3/keccak_permutation.sv \
    dilithium_hw/tb/tb_keccak_permutation.sv
vvp /tmp/tb_keccak
```

### 4.5 Comparing to golden output

After simulation, the `$display` output can be compared to
`golden_output.txt` (manually or via `compare_golden.py`).

For example, the C reference's SHAKE128("") output is:
`7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26`

The RTL simulation must produce the same 32 bytes (or rather, the
`shake128_absorb_once` output state, which when squeezed gives those bytes).

---

## 5. Known Verification Gaps

Because no SystemVerilog simulator was available during Phase 1
development, the following items are **not yet verified end-to-end**:

| Item | Status | Mitigation |
|---|---|---|
| Keccak round function | Static code review; constants checked | RTL sim required |
| SHAKE128 absorb/squeeze state machine | Same as above | RTL sim required |
| SHAKE256 absorb/squeeze state machine | Same as above | RTL sim required |
| NTT butterfly combinational path | Same as above | RTL sim required |
| NTT Montgomery reduction | Static review | RTL sim required |
| NTT controller FSM transitions | Static review | RTL sim required |
| End-to-end Dilithium2 sign | Requires Phases 2-7 first | Phases 2-7 + sim |

The static constant verification (Layer 1) and C reference execution
(Layer 2) provide strong evidence that the algorithm logic is correct,
since:
- All constants are bit-exact copies of the C reference.
- The Keccak chi/rho/pi/theta/iota expressions are line-by-line ports of
  the C reference (with one bug caught and fixed during development - see
  `VERIFICATION_REPORT.md`).
- The NTT butterfly is a direct translation of the C reference's loop
  structure.

The remaining verification requires an SV simulator, which should be
performed in Phase 8 (Verification) of the plan.
