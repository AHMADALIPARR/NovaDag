/*
 * gf_mul_agc_equiv.c
 *
 * Exhaustive bit-exact equivalence test (all 65,536 byte pairs) between:
 *   1. Reference C constant-time gf_mul(uint8_t a, uint8_t b)
 *   2. Exact Block II AGC 15-bit 1's-complement machine-level simulation
 *      of the lowered GFMUL routine in aes_custom_agc.agc
 */

#include <stdint.h>
#include <stdio.h>

/* 1. Reference C implementation */
static uint8_t gf_mul_ref(uint8_t a, uint8_t b)
{
    uint8_t result = 0;

    for (unsigned i = 0; i < 8u; ++i) {
        uint8_t mask = (uint8_t)(0u - (b & 1u));
        result ^= (uint8_t)(a & mask);

        uint8_t carry = (uint8_t)(a >> 7u);
        a = (uint8_t)((a << 1u) ^
             (0x1Bu & (uint8_t)(0u - carry)));
        b >>= 1u;
    }

    return result;
}

/* 2. AGC Block II 15-bit 1's-complement primitives */
#define AGC_MASK15 0x7FFFu

static inline uint16_t agc_ones_neg(uint16_t x)
{
    return (~x) & AGC_MASK15;
}

static inline uint16_t agc_ones_add(uint16_t x, uint16_t y)
{
    uint32_t s = (uint32_t)(x & AGC_MASK15) + (uint32_t)(y & AGC_MASK15);
    /* End-around carry for 15-bit 1's-complement addition */
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

/* Exact simulation of the lowered GFMUL routine from aes_custom_agc.agc */
static uint8_t gf_mul_agc(uint8_t a_in, uint8_t b_in)
{
    /* Octal constants in 15-bit AGC words */
    const uint16_t OCT0  = 000000u;
    const uint16_t OCT1  = 000001u;
    const uint16_t OCT7  = 000007u;
    const uint16_t OCT1B = 000033u; /* 0x1B */
    const uint16_t OCTFF = 000377u; /* 0xFF */

    /* Central & erasable registers */
    uint16_t A = 0, L = 0;
    uint16_t GFA = a_in, GFB = b_in, GFRES = 0;
    uint16_t GFMASK = 0, GFCARRY = 0, GFIDX = 0;
    uint16_t TMP0 = 0, TMP1 = 0;
    uint16_t EDOP_REG = 0, CYL_REG = 0, SR_REG = 0;

    A = OCT0;
    GFRES = A;
    A = OCT7;
    GFIDX = A;

    for (;;) {
        /* CA GFB; MASK OCT1; TS TMP0 */
        A = GFB & OCT1;
        TMP0 = A;

        /* CA OCTFF; AD OCT1; SU TMP0; MASK OCTFF; TS GFMASK */
        A = OCTFF;
        A = agc_ones_add(A, OCT1);
        A = agc_ones_sub(A, TMP0);
        A &= OCTFF;
        GFMASK = A;

        /* CA GFA; MASK GFMASK; TS L; CA GFRES; EXTEND; RXOR L; TS GFRES */
        A = GFA & GFMASK;
        L = A;
        A = GFRES ^ L;
        GFRES = A;

        /* CA GFA; TS EDOP; CA EDOP; MASK OCT1; TS GFCARRY */
        EDOP_REG = agc_edop(GFA);
        A = EDOP_REG & OCT1;
        GFCARRY = A;

        /* CA OCTFF; AD OCT1; SU GFCARRY; MASK OCTFF; MASK OCT1B; TS TMP1 */
        A = OCTFF;
        A = agc_ones_add(A, OCT1);
        A = agc_ones_sub(A, GFCARRY);
        A &= OCTFF;
        A &= OCT1B;
        TMP1 = A;

        /* CA GFA; TS CYL; CA CYL; MASK OCTFF; TS L; CA TMP1; EXTEND; RXOR L; TS GFA */
        CYL_REG = agc_cyl(GFA);
        A = CYL_REG & OCTFF;
        L = A;
        A = TMP1 ^ L;
        GFA = A;

        /* CA GFB; TS SR; CA SR; MASK OCTFF; TS GFB */
        SR_REG = agc_sr(GFB);
        A = SR_REG & OCTFF;
        GFB = A;

        /* CCS GFIDX */
        if (GFIDX > 0 && GFIDX < 0x4000u) {
            A = (uint16_t)(GFIDX - 1u);
            GFIDX = A;
        } else {
            break;
        }
    }

    A = GFRES & OCTFF;
    return (uint8_t)A;
}

int main(void)
{
    uint32_t tested = 0;
    uint32_t mismatches = 0;

    for (unsigned a = 0; a < 256u; ++a) {
        for (unsigned b = 0; b < 256u; ++b) {
            uint8_t ref = gf_mul_ref((uint8_t)a, (uint8_t)b);
            uint8_t agc = gf_mul_agc((uint8_t)a, (uint8_t)b);
            ++tested;
            if (ref != agc) {
                if (mismatches < 10u) {
                    fprintf(stderr, "MISMATCH at (0x%02X, 0x%02X): ref=0x%02X agc=0x%02X\n",
                            a, b, ref, agc);
                }
                ++mismatches;
            }
        }
    }

    printf("Tested %u / 65536 byte pairs; mismatches = %u\n", tested, mismatches);
    return (mismatches == 0u && tested == 65536u) ? 0 : 1;
}
