/* aes_recursive_claims.c — Independent verification of the numeric claims
 * in aes_recursive_lemmas.lean (AES.CustomRecursive).
 * Mathlib is NOT built on this VM, so the Lean file cannot be typechecked
 * here. This program implements the Lean recursive definitions EXACTLY as
 * written (bitMask8, gf_mul_step, gf_mul_rec, rcon_rec, active_sboxes_rec,
 * trail_weight_rec, degree_rec) and verifies every concrete claim by
 * execution.
 *
 * NOTE: this also cross-checks the recursive gf_mul_rec against the
 * iterative gf_mul in aes_custom_lowered.c — both must agree.
 */
#include <stdio.h>
#include <stdint.h>

static int fails = 0;
static void check(int ok, const char *msg) {
    if (ok) printf("  PASS: %s\n", msg);
    else { printf("  FAIL: %s\n", msg); fails++; }
}

/* Lean: bitMask8 bit = if bit % 2 = 1 then 0xFF else 0x00 */
static unsigned bitMask8(unsigned bit) {
    return (bit % 2 == 1) ? 0xFFu : 0x00u;
}

/* Lean: gf_mul_step (a b acc) = (a', b', acc') */
typedef struct { unsigned a, b, acc; } triple;
static triple gf_mul_step(unsigned a, unsigned b, unsigned acc) {
    unsigned mask = bitMask8(b & 1u);
    unsigned acc2 = acc ^ (a & mask);
    unsigned carry = (a >> 7) & 1u;
    unsigned a2 = ((a << 1) & 0xFFu) ^ (0x1Bu & bitMask8(carry));
    unsigned b2 = b >> 1;
    triple t = { a2, b2, acc2 };
    return t;
}

/* Lean: gf_mul_rec 0 a b acc = acc; gf_mul_rec (n+1) a b acc = step then recurse */
static unsigned gf_mul_rec(unsigned n, unsigned a, unsigned b, unsigned acc) {
    if (n == 0) return acc;
    triple t = gf_mul_step(a, b, acc);
    return gf_mul_rec(n - 1, t.a, t.b, t.acc);
}

/* Lean: gf_mul a b = gf_mul_rec 8 (a & 0xFF) (b & 0xFF) 0 */
static unsigned gf_mul(unsigned a, unsigned b) {
    return gf_mul_rec(8, a & 0xFFu, b & 0xFFu, 0);
}

/* Iterative gf_mul from aes_custom_lowered.c (cross-check target) */
static uint8_t gf_mul_iter(uint8_t a, uint8_t b) {
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

/* Lean: rcon_rec 0 = 0x01; rcon_rec (n+1) = gf_mul 0x02 (rcon_rec n) */
static unsigned rcon_rec(unsigned n) {
    if (n == 0) return 0x01u;
    return gf_mul(0x02u, rcon_rec(n - 1));
}

/* Lean: active_sboxes_rec 0=0, 1=1, 2=5, 3=9, n+4 = rec n + 25 */
static unsigned active_sboxes_rec(unsigned n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    if (n == 2) return 5;
    if (n == 3) return 9;
    return active_sboxes_rec(n - 4) + 25;
}

/* Lean: trail_weight_rec r = active_sboxes_rec r * 6 */
static unsigned trail_weight_rec(unsigned r) {
    return active_sboxes_rec(r) * 6;
}

/* Lean: degree_rec 0=1, 1=7, n+2 = min 127 (degree_rec (n+1) + 15) */
static unsigned degree_rec(unsigned n) {
    if (n == 0) return 1;
    if (n == 1) return 7;
    unsigned v = degree_rec(n - 1) + 15;
    return v < 127 ? v : 127;
}

int main(void) {
    /* gf_mul tests */
    check(gf_mul(0x57, 0x83) == 0xC1, "gf_mul_test_0x57_0x83: 0x57*0x83 == 0xC1");
    check(gf_mul(0x57, 0x13) == 0xFE, "gf_mul_test_0x57_0x13: 0x57*0x13 == 0xFE");
    check(gf_mul(0x02, 0x8D) == 0x01, "gf_mul_test_inv_0x02_0x8D: 0x02*0x8D == 0x01");
    check(gf_mul(0x57, 0) == 0, "gf_mul_zero_right: 0x57*0 == 0");
    check(gf_mul(0xFF, 0) == 0, "gf_mul_zero_right: 0xFF*0 == 0");
    /* Recursive gf_mul_rec agrees with iterative gf_mul (cross-check) */
    {
        int agree = 1;
        for (unsigned a = 0; a < 256; a += 17)
            for (unsigned b = 0; b < 256; b += 13)
                if (gf_mul(a, b) != gf_mul_iter((uint8_t)a, (uint8_t)b)) agree = 0;
        check(agree, "gf_mul_rec (Lean) agrees with gf_mul_iter (C) on sampled inputs");
    }
    /* rcon_rec */
    check(rcon_rec(0) == 0x01, "rcon_1: rcon_rec 0 == 0x01");
    check(rcon_rec(1) == 0x02, "rcon_2: rcon_rec 1 == 0x02");
    check(rcon_rec(7) == 0x80, "rcon_8: rcon_rec 7 == 0x80");
    check(rcon_rec(8) == 0x1B, "rcon_9: rcon_rec 8 == 0x1B");
    check(rcon_rec(9) == 0x36, "rcon_10: rcon_rec 9 == 0x36");
    /* active_sboxes_rec */
    check(active_sboxes_rec(4) == 25, "active_sboxes_4r_eq: rec 4 == 25");
    check(active_sboxes_rec(8) == 50, "active_sboxes_8r_eq: rec 8 == 50");
    check(active_sboxes_rec(10) == 55, "active_sboxes_10r_eq: rec 10 == 55");
    /* trail_weight_rec */
    check(trail_weight_rec(4) == 150, "trail_weight_4r: 150");
    check(trail_weight_rec(8) == 300, "trail_weight_8r: 300");
    check(trail_weight_rec(10) == 330, "trail_weight_rec 10 == 330 (55*6)");
    check(trail_weight_rec(10) > 97, "trail_weight_10r_exceeds_target: 330 > 97");
    /* degree_rec */
    check(degree_rec(10) == 127, "degree_rec 10 == 127");
    check(degree_rec(10) > 64, "degree_10r_high: 127 > 64");
    if (fails > 0) {
        printf("RESULT: %d checks FAILED\n", fails);
        return 1;
    }
    printf("RESULT: ALL CHECKS PASSED — every numeric claim in aes_recursive_lemmas.lean verifies by execution\n");
    return 0;
}
