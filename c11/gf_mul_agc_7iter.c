/*
 * gf_mul_agc_7iter.c
 *
 * Control test: models the AGC file's ACTUAL CCS loop as written in
 * aes_custom_agc.agc, to check whether the simulation in
 * gf_mul_agc_equiv.c faithfully models the file's loop count.
 *
 * AGC CCS semantics (Block II): CCS decrements the operand toward zero,
 * places the result in A, and SKIPS the next instruction if the result
 * is zero. The file's loop is:
 *     CCS GFIDX
 *     TCF GFNEXT     ; executed when GFIDX (after decrement) != 0
 *     TCF GFDONE     ; executed when GFIDX (after decrement) == 0
 *   GFNEXT TS GFIDX ; store A back, loop
 * So with GFIDX starting at OCT7 (7), the body runs once for GFIDX =
 * 7,6,5,4,3,2,1 and exits when CCS decrements 1 -> 0. That is 7 body
 * executions, not 8. The gf_mul algorithm needs 8 (one per bit of b).
 *
 * This file models exactly that: same body as gf_mul_agc_equiv.c, but
 * the CCS check decrements first and exits when the result is 0.
 * If this 7-iteration model mismatches the reference, then the AGC
 * file as written does NOT compute gf_mul correctly, even though the
 * 8-iteration simulation in gf_mul_agc_equiv.c passes.
 */
#include <stdint.h>
#include <stdio.h>

static uint8_t gf_mul_ref(uint8_t a, uint8_t b)
{
    uint8_t result = 0;
    for (unsigned i = 0; i < 8u; ++i) {
        uint8_t mask = (uint8_t)(0u - (b & 1u));
        result ^= (uint8_t)(a & mask);
        uint8_t carry = (uint8_t)(a >> 7u);
        a = (uint8_t)((a << 1u) ^ (0x1Bu & (uint8_t)(0u - carry)));
        b >>= 1u;
    }
    return result;
}

#define AGC_MASK15 0x7FFFu

static inline uint16_t agc_ones_neg(uint16_t x) { return (~x) & AGC_MASK15; }

static inline uint16_t agc_ones_add(uint16_t x, uint16_t y)
{
    uint32_t s = (uint32_t)(x & AGC_MASK15) + (uint32_t)(y & AGC_MASK15);
    s = (s & AGC_MASK15) + (s >> 15);
    return (uint16_t)(s & AGC_MASK15);
}

static inline uint16_t agc_ones_sub(uint16_t x, uint16_t y)
{
    return agc_ones_add(x, agc_ones_neg(y));
}

static inline uint16_t agc_cyl(uint16_t x)
{
    x &= AGC_MASK15;
    return (uint16_t)(((x << 1) | (x >> 14)) & AGC_MASK15);
}

static inline uint16_t agc_sr(uint16_t x)
{
    x &= AGC_MASK15;
    uint16_t sign = x & 0x4000u;
    return (uint16_t)((x >> 1) | sign);
}

static inline uint16_t agc_edop(uint16_t x)
{
    return (uint16_t)((x & AGC_MASK15) >> 7);
}

/* Same body as gf_mul_agc_equiv.c, but CCS modeled as the AGC file does it:
 * decrement GFIDX, exit when the result is 0. GFIDX starts at OCT7 (7). */
static uint8_t gf_mul_agc_file(uint8_t a_in, uint8_t b_in)
{
    const uint16_t OCT0  = 000000u;
    const uint16_t OCT1  = 000001u;
    const uint16_t OCT7  = 000007u;
    const uint16_t OCT1B = 000033u;
    const uint16_t OCTFF = 000377u;

    uint16_t A = 0, L = 0;
    uint16_t GFA = a_in, GFB = b_in, GFRES = 0;
    uint16_t GFMASK = 0, GFCARRY = 0, GFIDX = 0;
    uint16_t TMP0 = 0, TMP1 = 0;
    uint16_t EDOP_REG = 0, CYL_REG = 0, SR_REG = 0;
    unsigned iters = 0;

    A = OCT0;
    GFRES = A;
    A = OCT7;
    GFIDX = A;

    for (;;) {
        ++iters;
        A = GFB & OCT1;
        TMP0 = A;

        A = OCTFF;
        A = agc_ones_add(A, OCT1);
        A = agc_ones_sub(A, TMP0);
        A &= OCTFF;
        GFMASK = A;

        A = GFA & GFMASK;
        L = A;
        A = GFRES ^ L;
        GFRES = A;

        EDOP_REG = agc_edop(GFA);
        A = EDOP_REG & OCT1;
        GFCARRY = A;

        A = OCTFF;
        A = agc_ones_add(A, OCT1);
        A = agc_ones_sub(A, GFCARRY);
        A &= OCTFF;
        A &= OCT1B;
        TMP1 = A;

        CYL_REG = agc_cyl(GFA);
        A = CYL_REG & OCTFF;
        L = A;
        A = TMP1 ^ L;
        GFA = A;

        SR_REG = agc_sr(GFB);
        A = SR_REG & OCTFF;
        GFB = A;

        /* CCS GFIDX, faithful to the file: decrement, exit if result is 0 */
        A = (uint16_t)(GFIDX - 1u);
        GFIDX = A;
        if (A == 0) break;
    }

    /* Report iteration count once (first call only, via static) */
    static int reported = 0;
    if (!reported) {
        reported = 1;
        printf("Body executions per call (AGC file as written): %u\n", iters);
    }

    A = GFRES & OCTFF;
    return (uint8_t)A;
}

int main(void)
{
    uint32_t tested = 0;
    uint32_t mismatches = 0;
    uint32_t mismatch_b_ge_128 = 0;

    for (unsigned a = 0; a < 256u; ++a) {
        for (unsigned b = 0; b < 256u; ++b) {
            uint8_t ref = gf_mul_ref((uint8_t)a, (uint8_t)b);
            uint8_t agc = gf_mul_agc_file((uint8_t)a, (uint8_t)b);
            ++tested;
            if (ref != agc) {
                if (mismatches < 5u) {
                    fprintf(stderr, "MISMATCH at (0x%02X, 0x%02X): ref=0x%02X agc=0x%02X\n",
                            a, b, ref, agc);
                }
                ++mismatches;
                if (b >= 128u) ++mismatch_b_ge_128;
            }
        }
    }

    printf("Tested %u / 65536 byte pairs; mismatches = %u (of which b >= 128: %u)\n",
           tested, mismatches, mismatch_b_ge_128);
    return (mismatches == 0u && tested == 65536u) ? 0 : 1;
}
