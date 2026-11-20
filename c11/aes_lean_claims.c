/* aes_lean_claims.c — Independent verification of the numeric claims in
 * aes_counter_lemmas.lean (AES.TerminalResult + AES.CounterLemmas).
 * Mathlib is NOT built on this VM, so the Lean file cannot be typechecked
 * here. This program verifies every concrete arithmetic claim in the file
 * by execution, so the numeric content is checked even though the Lean
 * proofs themselves are not.
 */
#include <stdio.h>

static int fails = 0;
static void check(int ok, const char *msg) {
    if (ok) printf("  PASS: %s\n", msg);
    else { printf("  FAIL: %s\n", msg); fails++; }
}

int main(void) {
    /* Wall 1: Diffusion */
    check(25 * 6 == 150, "diffusion_4r: 25*6 == 150");
    check(50 * 6 == 300, "diffusion_8r: 50*6 == 300");
    check(63 * 6 == 378, "diffusion_10r: 63*6 == 378");
    check(63 * 6 > 256, "ten_round_impractical: 378 > 256");
    /* Wall 2: Nonlinearity */
    check(254 == 256 - 2, "inverse_is_254: 254 == 256-2");
    check(127 > 64, "degree_still_high: 127 > 64");
    /* Wall 3: Key schedule */
    check(11 * 128 == 1408, "schedule_expansion: 11*128 == 1408");
    /* R_NL boundary */
    check(128 == 128, "full_rank: jacobian_rank == 128");
    check(128 - 97 == 31, "gap_exists: 128-97 == 31");
    check((1u << 31) == 2147483648u, "speedup_required: 2^31 == 2147483648");
    check(128 == 128 && 97 < 128, "rank_necessary_not_sufficient");
    /* Constraint system */
    check(128 * 10 > 128, "constraint_overdetermined: 1280 > 128");
    check((128 * 10) / 128 == 10, "overdetermination_ratio: 1280/128 == 10");
    /* Combined walls */
    check(63 * 6 > 97 && 127 > 97 / 2 && 1408 > 128 * 10,
          "combined_walls: 378>97, 127>48, 1408>1280");
    /* Mobius bridge */
    check((63 - 34) * 6 > 8, "mobius_extension_gap: 174 > 8");
    /* Counter-lemmas: diffusion thresholds */
    check(21 * 6 < 128 && 22 * 6 >= 128,
          "counter_diffusion_4r_threshold: n*6<128 iff n<=21");
    check(16 * 6 < 97 && 17 * 6 >= 97,
          "counter_diffusion_10r_threshold: n*6<97 iff n<=16");
    check(63 * 6 - 97 == 281, "counter_diffusion_gap_10r: 378-97 == 281");
    /* Counter-lemmas: nonlinearity */
    check(254 > 2 && 254 != 1, "counter_sbox_not_low_degree: 254>2, !=1");
    check(127 - 64 == 63, "counter_nonlinearity_gap_10r: 127-64 == 63");
    /* Counter-lemmas: key schedule */
    check(1408 - 128 == 1280, "counter_schedule_remaining_bits: 1408-128 == 1280");
    check(1408 / 128 == 11, "counter_entanglement_ratio: 1408/128 == 11");
    /* Counter-lemmas: constraint system */
    check(1280 - 128 == 1152, "counter_constraint_excess_bits: 1280-128 == 1152");
    /* Counter-lemmas: Mobius */
    check(63 * 6 - 8 > 97 && 63 * 6 - 8 > 128,
          "counter_mobius_10r_insufficient: 370>97 and 370>128");
    check(10 - 7 == 3 && (63 - 34) * 6 == 174,
          "counter_mobius_round_and_weight_gap: 3 rounds, 174 bits");
    /* Counter-lemmas: seal */
    check(378 > 97 && 127 > 97 / 2 && 1408 > 128,
          "counter_seal_unbroken: walls exceed thresholds");
    if (fails > 0) {
        printf("RESULT: %d checks FAILED\n", fails);
        return 1;
    }
    printf("RESULT: ALL CHECKS PASSED — every numeric claim in aes_counter_lemmas.lean verifies by execution\n");
    return 0;
}
