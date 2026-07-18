// =============================================================================
// File:        gen_golden.c
// Project:     Dilithium Post-Quantum Signature Hardware Implementation
// Description: Generate golden output vectors for hardware verification.
//
//              This program produces known SHAKE128/256 outputs, NTT
//              transformations, and Montgomery reduction results for
//              specific inputs. The output is in a hex format suitable
//              for direct comparison with SystemVerilog simulation
//              results.
//
// Build:       cc -O2 -Iref -DDILITHIUM_MODE=2 -o gen_golden gen_golden.c \
//                   ref/fips202.c ref/ntt.c ref/reduce.c
//              (Run from project root, where ref/ directory exists)
//
// Usage:       ./gen_golden > golden_output.txt
// =============================================================================

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "fips202.h"
#include "params.h"
#include "ntt.h"
#include "reduce.h"

static void print_hex(const uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; i++) printf("%02x", buf[i]);
}

int main(void) {
    printf("# Dilithium Hardware Verification Golden Vectors\n");
    printf("# Mode: DILITHIUM_MODE=%d, N=%d, Q=%d\n", DILITHIUM_MODE, N, Q);
    printf("#\n");

    {
        uint8_t out[32];
        shake128(out, sizeof(out), (const uint8_t *)"", 0);
        printf("TEST SHAKE128_EMPTY  : ");
        print_hex(out, sizeof(out));
        printf("\n");
    }

    {
        uint8_t out[64];
        shake128(out, sizeof(out), (const uint8_t *)"abc", 3);
        printf("TEST SHAKE128_ABC    : ");
        print_hex(out, sizeof(out));
        printf("\n");
    }

    {
        uint8_t out[32];
        shake256(out, sizeof(out), (const uint8_t *)"", 0);
        printf("TEST SHAKE256_EMPTY  : ");
        print_hex(out, sizeof(out));
        printf("\n");
    }

    {
        uint8_t out[64];
        shake256(out, sizeof(out), (const uint8_t *)"abc", 3);
        printf("TEST SHAKE256_ABC    : ");
        print_hex(out, sizeof(out));
        printf("\n");
    }

    {
        int32_t a[N];
        for (int i = 0; i < N; i++) a[i] = (int32_t)(i % 10 - 5);
        ntt(a);
        printf("TEST NTT_SMALL       :");
        for (int i = 0; i < N; i++) printf(" %d", a[i]);
        printf("\n");
    }

    {
        int32_t a[N];
        for (int i = 0; i < N; i++) a[i] = (int32_t)(i % 13 - 6);
        int32_t orig[N];
        memcpy(orig, a, sizeof(a));
        ntt(a);
        invntt_tomont(a);
        printf("TEST INTT_ROUNDTRIP  :");
        for (int i = 0; i < N; i++) printf(" %d", a[i]);
        printf("\n");
        printf("TEST INTT_ORIGINAL   :");
        for (int i = 0; i < N; i++) printf(" %d", orig[i]);
        printf("\n");
    }

    {
        int64_t test_vals[] = {0, 1, -1, Q, -Q, 1000000LL, -1000000LL,
                               0x7FFFFFFFLL, -0x80000000LL, 0x123456789ABLL};
        for (size_t i = 0; i < sizeof(test_vals)/sizeof(test_vals[0]); i++) {
            int32_t r = montgomery_reduce(test_vals[i]);
            printf("TEST MONT_REDUCE[%lld]  : %d\n", (long long)test_vals[i], r);
        }
    }

    printf("# End of golden vectors\n");
    return 0;
}
