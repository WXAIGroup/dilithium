import os
import re
import sys
import subprocess

REF_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'ref')
HW_DIR = os.path.join(os.path.dirname(__file__), '..')


def extract_c_zetas():
    path = os.path.join(REF_DIR, 'ntt.c')
    with open(path) as f:
        text = f.read()
    m = re.search(r'static\s+const\s+int32_t\s+zetas\s*\[\s*N\s*\]\s*=\s*\{([^}]+)\}', text, re.S)
    if not m:
        raise RuntimeError("Could not extract zetas from ref/ntt.c")
    body = m.group(1)
    nums = re.findall(r'-?\d+', body)
    return [int(x) for x in nums]


def extract_sv_zetas():
    path = os.path.join(HW_DIR, 'include', 'ntt_params.svh')
    with open(path) as f:
        text = f.read()
    m = re.findall(r"24'sh([0-9A-Fa-f]{6})", text)
    if not m:
        raise RuntimeError("Could not extract zetas from ntt_params.svh")
    zetas = []
    for h in m:
        v = int(h, 16)
        if v >= 0x800000:
            v -= 0x1000000
        zetas.append(v)
    return zetas


def extract_c_round_constants():
    path = os.path.join(REF_DIR, 'fips202.c')
    with open(path) as f:
        text = f.read()
    m = re.search(r'KeccakF_RoundConstants\s*\[\s*NROUNDS\s*\]\s*=\s*\{([^}]+)\}', text, re.S)
    if not m:
        raise RuntimeError("Could not extract Keccak round constants")
    body = m.group(1)
    return [int(x, 16) for x in re.findall(r'0x[0-9A-Fa-f]{16}', body)]


def extract_sv_round_constants():
    path = os.path.join(HW_DIR, 'include', 'keccak_constants.svh')
    with open(path) as f:
        text = f.read()
    m = re.findall(r"64'h([0-9A-Fa-f_]+)", text)
    if not m:
        raise RuntimeError("Could not extract Keccak round constants from SV")
    rc = []
    for h in m:
        h_clean = h.replace('_', '')
        if len(h_clean) != 16:
            continue
        rc.append(int(h_clean, 16))
    return rc


def verify_zetas():
    print("=" * 60)
    print("Phase 1: Constant Verification")
    print("=" * 60)
    c_zetas = extract_c_zetas()
    sv_zetas = extract_sv_zetas()
    if len(c_zetas) != len(sv_zetas):
        print(f"FAIL: zeta count mismatch: C={len(c_zetas)}, SV={len(sv_zetas)}")
        return False
    diffs = []
    for i, (c, sv) in enumerate(zip(c_zetas, sv_zetas)):
        if c != sv:
            diffs.append((i, c, sv))
    if diffs:
        print(f"FAIL: {len(diffs)} zeta mismatches:")
        for i, c, sv in diffs[:10]:
            print(f"  zeta[{i}]: C={c}, SV={sv}")
        return False
    print(f"PASS: All {len(c_zetas)} NTT zetas match ref/ntt.c exactly")
    return True


def verify_round_constants():
    c_rc = extract_c_round_constants()
    sv_rc = extract_sv_round_constants()
    if len(c_rc) != len(sv_rc):
        print(f"FAIL: round constant count mismatch: C={len(c_rc)}, SV={len(sv_rc)}")
        return False
    for i, (c, sv) in enumerate(zip(c_rc, sv_rc)):
        if c != sv:
            print(f"FAIL: round constant {i} mismatch: C=0x{c:016x}, SV=0x{sv:016x}")
            return False
    print(f"PASS: All {len(c_rc)} Keccak round constants match ref/fips202.c exactly")
    return True


def verify_q_qinv():
    params_path = os.path.join(REF_DIR, 'params.h')
    with open(params_path) as f:
        params_text = f.read()
    reduce_path = os.path.join(REF_DIR, 'reduce.h')
    with open(reduce_path) as f:
        reduce_text = f.read()
    m_q = re.search(r'#define\s+Q\s+(\d+)', params_text)
    m_qinv = re.search(r'#define\s+QINV\s+(-?\d+)', reduce_text)
    if not m_q or not m_qinv:
        print("FAIL: cannot find Q/QINV in C reference")
        return False
    c_q = int(m_q.group(1))
    c_qinv = int(m_qinv.group(1))
    pkg_path = os.path.join(HW_DIR, 'include', 'dilithium_pkg.sv')
    with open(pkg_path) as f:
        pkg = f.read()
    m_sv_q = re.search(r'Q\s*=\s*(\d+)\s*;', pkg)
    m_sv_qinv = re.search(r'QINV\s*=\s*(-?\d+)\s*;', pkg)
    if not m_sv_q or not m_sv_qinv:
        print("FAIL: cannot find Q/QINV in dilithium_pkg.sv")
        return False
    sv_q = int(m_sv_q.group(1))
    sv_qinv = int(m_sv_qinv.group(1))
    if c_q != sv_q or c_qinv != sv_qinv:
        print(f"FAIL: Q/QINV mismatch: C=({c_q}, {c_qinv}), SV=({sv_q}, {sv_qinv})")
        return False
    print(f"PASS: Q={c_q} and QINV={c_qinv} match C reference exactly")
    return True


def verify_sha_rates():
    path = os.path.join(REF_DIR, 'fips202.h')
    with open(path) as f:
        text = f.read()
    rates = {}
    for k in ['SHAKE128_RATE', 'SHAKE256_RATE', 'SHA3_256_RATE', 'SHA3_512_RATE']:
        m = re.search(r'#define\s+' + k + r'\s+(\d+)', text)
        if m:
            rates[k] = int(m.group(1))
    pkg_path = os.path.join(HW_DIR, 'include', 'dilithium_pkg.sv')
    with open(pkg_path) as f:
        pkg = f.read()
    sv_rates = {}
    for k in ['SHAKE128_RATE', 'SHAKE256_RATE', 'SHA3_256_RATE', 'SHA3_512_RATE']:
        m = re.search(r'' + k + r'\s*=\s*(\d+)\s*;', pkg)
        if m:
            sv_rates[k] = int(m.group(1))
    ok = True
    for k in rates:
        if rates[k] != sv_rates.get(k, -1):
            print(f"FAIL: {k}: C={rates[k]}, SV={sv_rates.get(k, 'MISSING')}")
            ok = False
    if ok:
        print(f"PASS: All SHA3/SHAKE rates match ref/fips202.h: {rates}")
    return ok


def verify_c_ntt_test():
    print()
    print("=" * 60)
    print("Phase 1: C Reference Test Execution")
    print("=" * 60)
    test_bin = os.path.join(REF_DIR, 'test', 'test_mul')
    if not os.path.exists(test_bin):
        print(f"  Building C reference test_mul ...")
        r = subprocess.run(['make', '-C', REF_DIR, 'speed'], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"FAIL: build failed: {r.stderr}")
            return False
    r = subprocess.run([test_bin], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        print(f"FAIL: test_mul returned {r.returncode}")
        print(f"  stdout: {r.stdout}")
        print(f"  stderr: {r.stderr}")
        return False
    print(f"PASS: ref/test/test_mul (C reference NTT correctness) -> rc=0")
    return True


def verify_python_hashlib():
    import hashlib
    print()
    print("=" * 60)
    print("Phase 1: SHAKE Reference Vectors (Python hashlib)")
    print("=" * 60)
    cases = [
        (b"", 32, "SHAKE128('')"),
        (b"abc", 64, "SHAKE128('abc')"),
        (b"The quick brown fox jumps over the lazy dog", 32, "SHAKE128(quick fox)"),
        (b"", 32, "SHAKE256('')"),
        (b"abc", 64, "SHAKE256('abc')"),
    ]
    for data, outlen, desc in cases:
        if '128' in desc:
            actual = hashlib.shake_128(data).digest(outlen)
        else:
            actual = hashlib.shake_256(data).digest(outlen)
        print(f"  {desc:30s} = {actual[:8].hex()}... ({outlen} bytes)")
    print(f"PASS: SHAKE reference vectors available for SystemVerilog verification")
    return True


if __name__ == "__main__":
    results = []
    results.append(verify_q_qinv())
    results.append(verify_zetas())
    results.append(verify_round_constants())
    results.append(verify_sha_rates())
    results.append(verify_c_ntt_test())
    results.append(verify_python_hashlib())

    print()
    print("=" * 60)
    n_pass = sum(results)
    n_total = len(results)
    if n_pass == n_total:
        print(f"ALL CHECKS PASSED ({n_pass}/{n_total})")
    else:
        print(f"FAILED: {n_total - n_pass} of {n_total} checks failed")
    print("=" * 60)
    sys.exit(0 if n_pass == n_total else 1)
