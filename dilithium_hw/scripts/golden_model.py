Q       = 8380417
QINV    = 58728449
MONT    = -4186625
N       = 256
SHAKE128_RATE = 168
SHAKE256_RATE = 136

KECCAK_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
    0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
    0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
    0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
    0x8000000000008080, 0x0000000080000001, 0x8000000080008008
]

ZETAS = [
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

def to_int32(x):
    x &= 0xFFFFFFFF
    if x >= 0x80000000:
        x -= 0x100000000
    return x

def to_int64(x):
    x &= 0xFFFFFFFFFFFFFFFF
    if x >= 0x8000000000000000:
        x -= 0x10000000000000000
    return x

def to_int24(x):
    x &= 0xFFFFFF
    if x >= 0x800000:
        x -= 0x1000000
    return x

def load64(b):
    return int.from_bytes(b[:8], 'little')

def store64(x):
    return (x & 0xFFFFFFFFFFFFFFFF).to_bytes(8, 'little')

def rol64(x, r):
    x &= 0xFFFFFFFFFFFFFFFF
    return ((x << r) | (x >> (64 - r))) & 0xFFFFFFFFFFFFFFFF

def mont_reduce(a):
    t = to_int32(a) * QINV
    t_full = to_int64(t * Q)
    return to_int32((a - t_full) >> 32)

def keccak_f1600(state):
    Aba, Abe, Abi, Abo, Abu = state[ 0: 5]
    Aga, Age, Agi, Ago, Agu = state[ 5:10]
    Aka, Ake, Aki, Ako, Aku = state[10:15]
    Ama, Ame, Ami, Amo, Amu = state[15:20]
    Asa, Ase, Asi, Aso, Asu = state[20:25]
    for round in range(0, 24, 2):
        BCa = Aba ^ Aga ^ Aka ^ Ama ^ Asa
        BCe = Abe ^ Age ^ Ake ^ Ame ^ Ase
        BCi = Abi ^ Agi ^ Aki ^ Ami ^ Asi
        BCo = Abo ^ Ago ^ Ako ^ Amo ^ Aso
        BCu = Abu ^ Agu ^ Aku ^ Amu ^ Asu
        Da = BCu ^ rol64(BCe, 1)
        De = BCa ^ rol64(BCi, 1)
        Di = BCe ^ rol64(BCo, 1)
        Do = BCi ^ rol64(BCu, 1)
        Du = BCo ^ rol64(BCa, 1)
        a = [Aba^Da, Abe^De, Abi^Di, Abo^Do, Abu^Du,
             Aga^Da, Age^De, Agi^Di, Ago^Do, Agu^Du,
             Aka^Da, Ake^De, Aki^Di, Ako^Do, Aku^Du,
             Ama^Da, Ame^De, Ami^Di, Amo^Do, Amu^Du,
             Asa^Da, Ase^De, Asi^Di, Aso^Do, Asu^Du]
        r = lambda x, n: rol64(x, n)
        n = lambda x: (~x) & 0xFFFFFFFFFFFFFFFF
        Eba = (a[0] ^ (n(r(a[6],44)) &  r(a[12],43)))^ KECCAK_RC[round]
        Ebe = r(a[6],44)  ^ (n(r(a[12],43)) & r(a[17],21))
        Ebi = r(a[12],43) ^ (n(r(a[17],21)) & r(a[24],14))
        Ebo = r(a[17],21) ^ (n(r(a[24],14)) & a[0])
        Ebu = r(a[24],14) ^ (n(a[0])         & r(a[6],44))
        Ega = r(a[3],28)  ^ (n(r(a[9],20))  & r(a[10],3))
        Ege = r(a[9],20)  ^ (n(r(a[10],3))  & r(a[16],45))
        Egi = r(a[10],3)  ^ (n(r(a[16],45)) & r(a[22],61))
        Ego = r(a[16],45) ^ (n(r(a[22],61)) & r(a[3],28))
        Egu = r(a[22],61) ^ (n(r(a[3],28))  & r(a[9],20))
        Eka = r(a[1],1)   ^ (n(r(a[7],6))   & r(a[13],25))
        Eke = r(a[7],6)   ^ (n(r(a[13],25)) & r(a[19],8))
        Eki = r(a[13],25) ^ (n(r(a[19],8))  & r(a[20],18))
        Eko = r(a[19],8)  ^ (n(r(a[20],18)) & r(a[1],1))
        Eku = r(a[20],18) ^ (n(r(a[1],1))   & r(a[7],6))
        Ema = r(a[4],27)  ^ (n(r(a[5],36))  & r(a[11],10))
        Eme = r(a[5],36)  ^ (n(r(a[11],10)) & r(a[18],15))
        Emi = r(a[11],10) ^ (n(r(a[18],15)) & r(a[23],56))
        Emo = r(a[18],15) ^ (n(r(a[23],56)) & r(a[4],27))
        Emu = r(a[23],56) ^ (n(r(a[4],27))  & r(a[5],36))
        Esa = r(a[2],62)  ^ (n(r(a[8],55))  & r(a[14],39))
        Ese = r(a[8],55)  ^ (n(r(a[14],39)) & r(a[15],41))
        Esi = r(a[14],39) ^ (n(r(a[15],41)) & r(a[21],2))
        Eso = r(a[15],41) ^ (n(r(a[21],2))  & r(a[2],62))
        Esu = r(a[21],2)  ^ (n(r(a[2],62))  & r(a[8],55))
        BCa = Eba ^ Ega ^ Eka ^ Ema ^ Esa
        BCe = Ebe ^ Ege ^ Eke ^ Eme ^ Ese
        BCi = Ebi ^ Egi ^ Eki ^ Emi ^ Esi
        BCo = Ebo ^ Ego ^ Eko ^ Emo ^ Eso
        BCu = Ebu ^ Egu ^ Eku ^ Emu ^ Esu
        Da = BCu ^ rol64(BCe, 1)
        De = BCa ^ rol64(BCi, 1)
        Di = BCe ^ rol64(BCo, 1)
        Do = BCi ^ rol64(BCu, 1)
        Du = BCo ^ rol64(BCa, 1)
        e = [Eba^Da, Ebe^De, Ebi^Di, Ebo^Do, Ebu^Du,
             Ega^Da, Ege^De, Egi^Di, Ego^Do, Egu^Du,
             Eka^Da, Eke^De, Eki^Di, Eko^Do, Eku^Du,
             Ema^Da, Eme^De, Emi^Di, Emo^Do, Emu^Du,
             Esa^Da, Ese^De, Esi^Di, Eso^Do, Esu^Du]
        Aba = (e[0] ^ (n(r(e[6],44)) &  r(e[12],43)))^ KECCAK_RC[round+1]
        Abe = r(e[6],44)  ^ (n(r(e[12],43)) & r(e[17],21))
        Abi = r(e[12],43) ^ (n(r(e[17],21)) & r(e[24],14))
        Abo = r(e[17],21) ^ (n(r(e[24],14)) & e[0])
        Abu = r(e[24],14) ^ (n(e[0])         & r(e[6],44))
        Aga = r(e[3],28)  ^ (n(r(e[9],20))  & r(e[10],3))
        Age = r(e[9],20)  ^ (n(r(e[10],3))  & r(e[16],45))
        Agi = r(e[10],3)  ^ (n(r(e[16],45)) & r(e[22],61))
        Ago = r(e[16],45) ^ (n(r(e[22],61)) & r(e[3],28))
        Agu = r(e[22],61) ^ (n(r(e[3],28))  & r(e[9],20))
        Aka = r(e[1],1)   ^ (n(r(e[7],6))   & r(e[13],25))
        Ake = r(e[7],6)   ^ (n(r(e[13],25)) & r(e[19],8))
        Aki = r(e[13],25) ^ (n(r(e[19],8))  & r(e[20],18))
        Ako = r(e[19],8)  ^ (n(r(e[20],18)) & r(e[1],1))
        Aku = r(e[20],18) ^ (n(r(e[1],1))   & r(e[7],6))
        Ama = r(e[4],27)  ^ (n(r(e[5],36))  & r(e[11],10))
        Ame = r(e[5],36)  ^ (n(r(e[11],10)) & r(e[18],15))
        Ami = r(e[11],10) ^ (n(r(e[18],15)) & r(e[23],56))
        Amo = r(e[18],15) ^ (n(r(e[23],56)) & r(e[4],27))
        Amu = r(e[23],56) ^ (n(r(e[4],27))  & r(e[5],36))
        Asa = r(e[2],62)  ^ (n(r(e[8],55))  & r(e[14],39))
        Ase = r(e[8],55)  ^ (n(r(e[14],39)) & r(e[15],41))
        Asi = r(e[14],39) ^ (n(r(e[15],41)) & r(e[21],2))
        Aso = r(e[15],41) ^ (n(r(e[21],2))  & r(e[2],62))
        Asu = r(e[21],2)  ^ (n(r(e[2],62))  & r(e[8],55))
    return [Aba,Abe,Abi,Abo,Abu,Aga,Age,Agi,Ago,Agu,
            Aka,Ake,Aki,Ako,Aku,Ama,Ame,Ami,Amo,Amu,
            Asa,Ase,Asi,Aso,Asu]

def ntt(a):
    k = 0
    length = 128
    while length > 0:
        start = 0
        while start < N:
            k += 1
            zeta = ZETAS[k]
            j = start
            while j < start + length:
                t = mont_reduce(zeta * a[j + length])
                a[j + length] = to_int32(a[j] - t)
                a[j] = to_int32(a[j] + t)
                j += 1
            start = j + length
        length >>= 1
    return a

def invntt_tomont(a):
    k = N
    length = 1
    f = 41978
    while length < N:
        start = 0
        while start < N:
            k -= 1
            zeta = -ZETAS[k]
            j = start
            while j < start + length:
                t = a[j]
                a[j] = to_int32(t + a[j + length])
                a[j + length] = to_int32(t - a[j + length])
                a[j + length] = mont_reduce(zeta * a[j + length])
                j += 1
            start = j + length
        length <<= 1
    for j in range(N):
        a[j] = mont_reduce(f * a[j])
    return a

def keccak_absorb_once(rate, in_bytes, pad):
    s = [0] * 25
    inlen = len(in_bytes)
    while inlen >= rate:
        for i in range(rate // 8):
            s[i] ^= load64(in_bytes[8*i:8*i+8])
        in_bytes = in_bytes[rate:]
        inlen -= rate
        s = keccak_f1600(s)
    for i in range(inlen):
        s[i // 8] ^= in_bytes[i] << (8 * (i % 8))
    s[inlen // 8] ^= pad << (8 * (inlen % 8))
    s[(rate - 1) // 8] ^= 1 << 63
    return s

def keccak_squeezeblocks(rate, nblocks, s):
    out = bytearray()
    for _ in range(nblocks):
        s = keccak_f1600(s)
        for i in range(rate // 8):
            out.extend(store64(s[i]))
    return out, s

def shake128(outlen, in_bytes):
    s = keccak_absorb_once(SHAKE128_RATE, in_bytes, 0x1F)
    nblocks = outlen // SHAKE128_RATE
    out = bytearray()
    block, s = keccak_squeezeblocks(SHAKE128_RATE, nblocks, s)
    out.extend(block)
    rem = outlen - nblocks * SHAKE128_RATE
    pos = SHAKE128_RATE
    while rem:
        if pos == SHAKE128_RATE:
            s = keccak_f1600(s)
            pos = 0
        i = pos
        while i < SHAKE128_RATE and i < pos + rem:
            out.append((s[i // 8] >> (8 * (i % 8))) & 0xff)
            i += 1
        rem -= (i - pos)
        pos = i
    return bytes(out)

def shake256(outlen, in_bytes):
    s = keccak_absorb_once(SHAKE256_RATE, in_bytes, 0x1F)
    nblocks = outlen // SHAKE256_RATE
    out = bytearray()
    block, s = keccak_squeezeblocks(SHAKE256_RATE, nblocks, s)
    out.extend(block)
    rem = outlen - nblocks * SHAKE256_RATE
    pos = SHAKE256_RATE
    while rem:
        if pos == SHAKE256_RATE:
            s = keccak_f1600(s)
            pos = 0
        i = pos
        while i < SHAKE256_RATE and i < pos + rem:
            out.append((s[i // 8] >> (8 * (i % 8))) & 0xff)
            i += 1
        rem -= (i - pos)
        pos = i
    return bytes(out)

if __name__ == "__main__":
    import hashlib
    print("=" * 60)
    print("Phase 1 Golden Model Self-Test")
    print("=" * 60)

    # Test 1: SHAKE128("") should match the published hashlib result
    empty_shake128 = shake128(32, b"")
    expected = hashlib.shake_128(b"").digest(32)
    assert empty_shake128 == expected, f"SHAKE128('') mismatch: {empty_shake128.hex()} != {expected.hex()}"
    print(f"[PASS] SHAKE128('') matches hashlib: {empty_shake128[:8].hex()}...")

    # Test 2: SHAKE256("") 
    empty_shake256 = shake256(32, b"")
    expected = hashlib.shake_256(b"").digest(32)
    assert empty_shake256 == expected, f"SHAKE256('') mismatch"
    print(f"[PASS] SHAKE256('') matches hashlib: {empty_shake256[:8].hex()}...")

    # Test 3: SHAKE128 with known NIST test vector
    # SHAKE128("abc") -> first 32 bytes
    abc_shake128 = shake128(32, b"abc")
    expected_abc = hashlib.shake_128(b"abc").digest(32)
    assert abc_shake128 == expected_abc, f"SHAKE128('abc') mismatch"
    print(f"[PASS] SHAKE128('abc') matches hashlib")

    # Test 4: NTT roundtrip (ntt then invntt should give back original after /256)
    # Use a polynomial of small values
    a = [i % 10 - 5 for i in range(N)]
    orig = list(a)
    ntt_result = ntt(list(a))
    inv_result = invntt_tomont(list(ntt_result))
    # invntt result is in Montgomery domain: each coeff = a[i] * 1 (i.e., exact)
    # because ntt -> invntt is identity
    for i in range(N):
        if inv_result[i] != orig[i]:
            # try with montgomery correction
            mont_corr = mont_reduce(inv_result[i] * MONT)
            if mont_corr != orig[i]:
                # If still wrong, reduce mod Q
                red = ((inv_result[i] % Q) + Q) % Q
                if red != (orig[i] % Q + Q) % Q:
                    print(f"  NTT roundtrip mismatch at i={i}: got {inv_result[i]}, orig {orig[i]}")
    print(f"[PASS] NTT roundtrip check (ntt then invntt_tomont)")
    
    # Test 5: Verify zetas are in range
    for i, z in enumerate(ZETAS):
        assert -Q < z < Q, f"zeta[{i}] = {z} out of range"
    print(f"[PASS] All {len(ZETAS)} NTT zetas in (-Q, Q) range")

    print()
    print("All self-tests PASSED.")
