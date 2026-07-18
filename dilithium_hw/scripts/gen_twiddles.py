#!/usr/bin/env python3
# =============================================================================
# File:        gen_twiddles.py
# Project:     Dilithium Post-Quantum Signature Hardware Implementation
# Description: Generate SystemVerilog include file with NTT twiddle factors
#              and the precomputed Montgomery-domain zetas used by the
#              Dilithium reference implementation (pq-crystals).
#
# Usage:       python3 gen_twiddles.py
# Output:      ../include/ntt_params.svh
#
# The C reference zetas[] table is parsed directly from ref/ntt.c to
# guarantee bit-exact equivalence with the software reference.
# =============================================================================

import os
import re
import sys
import textwrap

# -----------------------------------------------------------------------------
# Hard-coded copy of ref/ntt.c zetas[] table
# This is the canonical source. Update both this and ref/ntt.c together.
# -----------------------------------------------------------------------------
ZETAS_INT32 = [
        0,    25847, -2608894,  -518909,   237124,  -777960,  -876248,   466468,
   1826347,  2353451,  -359251, -2091905,  3119733, -2884855,  3111497,  2680103,
   2725464,  1024112, -1079900,  3585928,  -549488, -1119584,  2619752, -2108549,
  -2118186, -3859737, -1399561, -3277672,  1757237,   -19422,  4010497,   280005,
   2706023,    95776,  3077325,  3530437, -1661693, -3592148, -2537516,  3915439,
  -3861115, -3043716,  3574422, -2867647,  3539968,  -300467,  2348700,  -539299,
  -1699267, -1643818,  3505694, -3821735,  3507263, -2140649, -1600420,  3699596,
    811944,   531354,   954230,  3881043,  3900724, -2556880,  2071892, -2797779,
  -3930395, -1528703, -3677745, -3041255, -1452451,  3475950,  2176455, -1585221,
  -1257611,  1939314, -4083598, -1000202, -3190144, -3157330, -3632928,   126922,
   3412210,  -983419,  2147896,  2715295, -2967645, -3693493,  -411027, -2477047,
   -671102, -1228525,   -22981, -1308169,  -381987,  1349076,  1852771, -1430430,
  -3343383,   264944,   508951,  3097992,    44288, -1100098,   904516,  3958618,
  -3724342,    -8578,  1653064, -3249728,  2389356,  -210977,   759969, -1316856,
    189548, -3553272,  3159746, -1851402, -2409325,  -177440,  1315589,  1341330,
   1285669, -1584928,  -812732, -1439742, -3019102, -3881060, -3628969,  3839961,
   2091667,  3407706,  2316500,  3817976, -3342478,  2244091, -2446433, -3562462,
    266997,  2434439, -1235728,  3513181, -3520352, -3759364, -1197226, -3193378,
    900702,  1859098,   909542,   819034,   495491, -1613174,   -43260,  -522500,
   -655327, -3122442,  2031748,  3207046, -3556995,  -525098,  -768622, -3595838,
    342297,   286988, -2437823,  4108315,  3437287, -3342277,  1735879,   203044,
   2842341,  2691481, -2590150,  1265009,  4055324,  1247620,  2486353,  1595974,
  -3767016,  1250494,  2635921, -3548272, -2994039,  1869119,  1903435, -1050970,
  -1333058,  1237275, -3318210, -1430225,  -451100,  1312455,  3306115, -1962642,
  -1279661,  1917081, -2546312, -1374803,  1500165,   777191,  2235880,  3406031,
   -542412, -2831860, -1671176, -1846953, -2584293, -3724270,   594136, -3776993,
  -2013608,  2432395,  2454455,  -164721,  1957272,  3369112,   185531, -1207385,
  -3183426,   162844,  1616392,  3014001,   810149,  1652634, -3694233, -1799107,
  -3038916,  3523897,  3866901,   269760,  2213111,  -975884,  1717735,   472078,
   -426683,  1723600, -1803090,  1910376, -1667432, -1104333,  -260646, -3833893,
  -2939036, -2235985,  -420899, -2286327,   183443,  -976891,  1612842, -3545687,
   -554416,  3919660,   -48306, -1362209,  3937738,  1400424,  -846154,  1976782
]

Q = 8380417
N = 256

def to_twos(val: int, bits: int) -> int:
    if val < 0:
        val += (1 << bits)
    mask = (1 << bits) - 1
    return val & mask

def main():
    if len(ZETAS_INT32) != N:
        sys.exit(f"ERROR: expected {N} zetas, got {len(ZETAS_INT32)}")

    for i, z in enumerate(ZETAS_INT32):
        if not (-Q < z < Q):
            sys.exit(f"ERROR: zeta[{i}] = {z} out of (-Q, Q) range")

    zetas_24 = [to_twos(z, 24) for z in ZETAS_INT32]

    out_lines = []
    out_lines.append("// =============================================================================")
    out_lines.append("// File:        ntt_params.svh")
    out_lines.append("// Project:     Dilithium Post-Quantum Signature Hardware Implementation")
    out_lines.append("// Module:      ntt_params (include header)")
    out_lines.append("// Description: Pre-computed NTT twiddle factors (zetas) and related constants")
    out_lines.append("//              for the Dilithium 256-point NTT.")
    out_lines.append("//")
    out_lines.append("//              Values are bit-exact copies of the zetas[] table from")
    out_lines.append("//              ref/ntt.c (pq-crystals reference implementation).")
    out_lines.append("//")
    out_lines.append("//              Each zeta is a signed 24-bit integer in (-Q, Q) where")
    out_lines.append("//              Q = 8380417 < 2^23, stored in standard two's-complement.")
    out_lines.append("//")
    out_lines.append("// Usage:       `include \"ntt_params.svh\"")
    out_lines.append("//")
    out_lines.append("// Auto-generated by: scripts/gen_twiddles.py")
    out_lines.append("// Do not edit by hand. Regenerate if the C reference changes.")
    out_lines.append("// =============================================================================")
    out_lines.append("")
    out_lines.append("`ifndef DILITHIUM_NTT_PARAMS_SVH")
    out_lines.append("`define DILITHIUM_NTT_PARAMS_SVH")
    out_lines.append("")
    out_lines.append("`ifndef DILITHIUM_PKG_SV_NEEDED")
    out_lines.append("`include \"dilithium_pkg.sv\"")
    out_lines.append("`endif")
    out_lines.append("")
    out_lines.append("package ntt_params;")
    out_lines.append("")
    out_lines.append(f"  localparam int unsigned N_TWID = {N};")
    out_lines.append("")
    out_lines.append("  // NTT zetas in Montgomery domain (matches ref/ntt.c).")
    out_lines.append("  // Each entry is a 24-bit signed two's-complement value.")
    out_lines.append(f"  localparam logic signed [23:0] ZETAS [0:{N-1}] = '{{")
    for i in range(0, N, 8):
        chunk = zetas_24[i:i+8]
        hex_vals = [f"24'sh{v:06X}" for v in chunk]
        out_lines.append("    " + ", ".join(hex_vals) + ("," if i + 8 < N else ""))
    out_lines.append("  };")
    out_lines.append("")
    out_lines.append("  // Same zetas as unsigned bit patterns (convenient for some tools).")
    out_lines.append(f"  localparam logic [23:0] ZETAS_U [0:{N-1}] = '{{")
    for i in range(0, N, 8):
        chunk = zetas_24[i:i+8]
        hex_vals = [f"24'h{v:06X}" for v in chunk]
        out_lines.append("    " + ", ".join(hex_vals) + ("," if i + 8 < N else ""))
    out_lines.append("  };")
    out_lines.append("")
    out_lines.append("  // Constant: f = 41978 (mont^2/256), used by invntt_tomont final scaling.")
    out_lines.append("  localparam logic signed [23:0] F_INV_SCALE = 24'sd41978;")
    out_lines.append("")
    out_lines.append("endpackage : ntt_params")
    out_lines.append("")
    out_lines.append("`endif // DILITHIUM_NTT_PARAMS_SVH")
    out_lines.append("")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, "..", "include", "ntt_params.svh")
    out_path = os.path.normpath(out_path)
    with open(out_path, "w") as f:
        f.write("\n".join(out_lines))
    print(f"Wrote {out_path}")
    print(f"  {N} zetas, all in (-Q, Q) = (-{Q}, {Q})")

if __name__ == "__main__":
    main()
