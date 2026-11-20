/*
 * cipher512_ref.c
 *
 * C11 reference for the 512-bit custom cipher, built from:
 *   - Futhark gf256.fut (gf_mul), diffusion.fut (shift_rows_512,
 *     mix_columns_512), state512.fut (sub_bytes_512, add_round_key_512)
 *   - VHDL gf256_alu.vhd KeyStep (64-byte chain: byte 0 = key[0] ^
 *     SBOX(key[63]) ^ (RCON[round] ^ 0xA5); byte i = key[i] ^ key[i-1])
 *   - microcode/encryption.uasm round structure (10 rounds, LC0=9 loop
 *     + final round, RCON[0..9], tweak 0xA5)
 *
 * Checks:
 *   1. Futhark gf_mul (0x1b * carry form) == C reference gf_mul
 *      (0x1B & (0 - carry) form) on all 65536 pairs.
 *   2. Full 512-bit cipher on plaintext = key = bytes 0..63
 *      (the round_vectors.bin counting pattern). Prints the ciphertext
 *      and the state after each round, as a reference test vector.
 *      There is no golden output in the microrom to compare against;
 *      this output IS the reference, computed from the spec.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const uint8_t SBOX[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static const uint8_t RCON[16] = {
    0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,
    0x1b,0x36,0x6c,0xd8,0xab,0x4d,0x9a,0x2f
};

#define TWEAK 0xA5u

/* C reference gf_mul (mask form) */
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

/* Futhark gf256.fut gf_mul (0x1b * carry form) */
static uint8_t gf_mul_fut(uint8_t a, uint8_t b)
{
    uint8_t r = 0, x = a, y = b;
    for (unsigned i = 0; i < 8u; ++i) {
        uint8_t mask = (uint8_t)(0u - (y & 1u));
        r ^= (uint8_t)(x & mask);
        uint8_t carry = (uint8_t)(x >> 7u);
        x = (uint8_t)((x << 1u) ^ (uint8_t)(0x1bu * carry));
        y >>= 1u;
    }
    return r;
}

static const int SHIFT_PERM[16] = {0,5,10,15, 4,9,14,3, 8,13,2,7, 12,1,6,11};

static void sub_bytes_512(uint8_t s[64])
{
    for (unsigned i = 0; i < 64u; ++i) s[i] = SBOX[s[i]];
}

static void shift_rows_512(uint8_t s[64])
{
    uint8_t t[64];
    for (unsigned lane = 0; lane < 4u; ++lane)
        for (unsigned pos = 0; pos < 16u; ++pos)
            t[lane * 16u + pos] = s[lane * 16u + (unsigned)SHIFT_PERM[pos]];
    memcpy(s, t, 64);
}

static void mix_columns_512(uint8_t s[64])
{
    for (unsigned c = 0; c < 16u; ++c) {
        unsigned idx = c * 4u;
        uint8_t a0 = s[idx], a1 = s[idx+1], a2 = s[idx+2], a3 = s[idx+3];
        s[idx+0] = (uint8_t)(gf_mul_ref(0x02, a0) ^ gf_mul_ref(0x03, a1) ^ a2 ^ a3);
        s[idx+1] = (uint8_t)(a0 ^ gf_mul_ref(0x02, a1) ^ gf_mul_ref(0x03, a2) ^ a3);
        s[idx+2] = (uint8_t)(a0 ^ a1 ^ gf_mul_ref(0x02, a2) ^ gf_mul_ref(0x03, a3));
        s[idx+3] = (uint8_t)(gf_mul_ref(0x03, a0) ^ a1 ^ a2 ^ gf_mul_ref(0x02, a3));
    }
}

static void add_round_key_512(uint8_t s[64], const uint8_t rk[64])
{
    for (unsigned i = 0; i < 64u; ++i) s[i] ^= rk[i];
}

/* VHDL gf256_alu.vhd KeyStep: byte 0 = key[0] ^ SBOX(key[63]) ^ (RCON[round] ^ tweak);
 * byte i = key[i] ^ key[i-1]. round is 0-based (0..9). */
static void keystep_512(uint8_t rk[64], unsigned round)
{
    uint8_t old[64];
    memcpy(old, rk, 64);
    uint8_t rc = (uint8_t)(RCON[round] ^ TWEAK);
    rk[0] = (uint8_t)(old[0] ^ SBOX[old[63]] ^ rc);
    for (unsigned i = 1; i < 64u; ++i)
        rk[i] = (uint8_t)(old[i] ^ old[i - 1]);
}

static void print_state(const char *label, const uint8_t s[64])
{
    printf("%s: ", label);
    for (unsigned i = 0; i < 64u; ++i) printf("%02x", s[i]);
    printf("\n");
}

int main(void)
{
    /* Check 1: Futhark gf_mul == C reference gf_mul on all pairs */
    uint32_t mism = 0;
    for (unsigned a = 0; a < 256u; ++a)
        for (unsigned b = 0; b < 256u; ++b)
            if (gf_mul_fut((uint8_t)a, (uint8_t)b) != gf_mul_ref((uint8_t)a, (uint8_t)b))
                ++mism;
    printf("Futhark gf_mul vs C reference: mismatches = %u / 65536\n", mism);

    /* Check 2: full 512-bit cipher, pt = key = bytes 0..63 */
    uint8_t state[64], rkey[64];
    for (unsigned i = 0; i < 64u; ++i) { state[i] = (uint8_t)i; rkey[i] = (uint8_t)i; }

    add_round_key_512(state, rkey);           /* Round 0 */
    print_state("round 0 (after AddRoundKey)", state);
    for (unsigned r = 0; r < 9u; ++r) {       /* Rounds 1..9 */
        sub_bytes_512(state);
        shift_rows_512(state);
        mix_columns_512(state);
        keystep_512(rkey, r);
        add_round_key_512(state, rkey);
        char label[48];
        snprintf(label, sizeof label, "round %u", r + 1u);
        print_state(label, state);
    }
    sub_bytes_512(state);                     /* Round 10 (no MixColumns) */
    shift_rows_512(state);
    keystep_512(rkey, 9u);
    add_round_key_512(state, rkey);
    print_state("round 10 (ciphertext)", state);
    return (mism == 0u) ? 0 : 1;
}
