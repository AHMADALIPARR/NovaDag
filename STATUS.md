# NovaDag STATUS

Running status of the RIJNDAEL-uROM verified transformation DAG.
Verification scope and open items, as plain facts.

## What is verified by execution

- C reference (`c11/aes_custom_lowered.c`) compiles clean and runs.
  gf_mul(0x57, 0x83) = 0xC1. Ciphertext for the standard AES test vector
  (pt 3243f6a8885a308d313198a2e0370734, key 2b7e151628aed2a6abf7158809cf4f3c)
  is 73b5fe0471cc3d8b18b58c16c09ef686. Zero-vector ciphertext is
  7716fa3975247611bdd9d15eef97ea74. These differ from standard AES-128
  output because the 0xA5 tweak changes the round keys. This is a custom
  cipher, not AES-128.
- VHDL 128-bit cipher (`vhdl/aes_custom.vhd`) passes GHDL simulation.
  The testbench passes at 136 ns (standard vector matches C) and 266 ns
  (zero vector matches C). First hardware/software cross-verification in
  the stack.
- AGC gf_mul equivalence (`c11/gf_mul_agc_equiv.c`) passes 65,536/65,536
  pairs, 0 mismatches.
- AGC GFMUL loop bound: the AGC file in this repo carries CA OCT10 (8
  iterations). A 7-iteration control test (`c11/gf_mul_agc_7iter.c`) shows
  32,640 of 65,536 pairs mismatch, all with b >= 128. The 8-iteration
  model matches on all pairs.
- uROM generator (`microcode/urom_gen.py`) reproduces the shipped ROM
  byte-identically, both `microcode/encryption.mem` and
  `vhdl/rijndael_urom.vhd`.
- `verification/gf256_vectors.bin` is the full gf_mul truth table:
  0 mismatches / 65,536.
- Lean proof's three claimed instruction words match the generated ROM
  exactly: 0x91804040 at 0x007, 0x11140009 at 0x043, 0xF0000000 at 0x04F.
  ROM: 4096 words, 25 non-default.
- All VHDL files analyze and elaborate clean in dependency order.
- VHDL `gf256_alu` mul_out passes GHDL simulation (10 vectors).
- Futhark gf_mul equals the C reference gf_mul, 0 mismatches / 65,536.
- Futhark S-box equals the C S-box (256 entries). Futhark ShiftRows
  permutation equals the VHDL permutation. VHDL RCON matches the doubling
  sequence mod 0x11B.
- Full 512-bit cipher C reference (`c11/cipher512_ref.c`) runs. Ciphertext
  for pt = key = bytes 0..63 begins 8ba9c4418ed30ecf83131e823058ab38. Full
  per-round states are in `verification/cipher512_ref_output.txt`. This is
  a computed reference; no golden output exists in the package to compare
  against.
- Loop counts traced through microsequencer semantics: LC0=9 gives the
  round body 9 times plus the final round, 10 rounds. BIST LC1=8 gives
  8 iterations. KEYSTEP round_idx starts at 0 and increments per KEYSTEP,
  using RCON[0..9].
- Outer ROM digest words 0..7 concatenate to exactly
  1376fd6bd243379655767a5ee22e260d373bb425ce4371562db3fa410d64449f.
  Instruction words decode correctly: 0x20000000 VERIFY_MANIFEST,
  0x40000000 LOCK_IMMUTABLE, 0x30040000 EXEC_INNER inner_pc=0x040,
  0xF0000000 HALT.
- Outer ROM controller simulation passes: manifest_ok=1 at 105 ns,
  rom_locked=1 at 115 ns, done=1 at 945 ns, and the 512-bit ciphertext
  matches the C reference exactly. Testbench:
  `vhdl/nested_rom_controller_tb.vhd`.
- Lean numeric claims verified independently by execution:
  `c11/aes_lean_claims.c`, all 26 checks passed;
  `c11/aes_recursive_claims.c`, all 20 checks passed.
- Racket DAG module (`racket/dag.rkt`) passes 8/8 in-memory checks:
  add-node, ancestors including transitive, verified?, duplicate /
  missing-parent / self-reference rejections. Test:
  `racket/dag_test.rkt`.

## Not verified here

- Lean proofs are not typechecked here. Mathlib is not built anywhere on
  this VM. Every concrete numeric claim in the Lean files was verified
  independently by execution instead (see above).
- Cryptol (`cryptol/GF256.cry`) is not typechecked here. Cryptol is not
  installed on this VM. The module is a proposed specification.
- SAW proofs are not run here. SAW is not installed on this VM. The
  obligations in `saw/obligations.md` are registered, not discharged.
- The AGC SHIFTROWS, MIXCOLS, and KEYSTEP routines are stubs in the AGC
  file. The SBOX rope holds only 4 of 256 entries.
- No SystemVerilog simulator is on this VM. `vhdl/aes_custom.sv` is
  verified by inspection against the C reference, not by simulation.

## Open items

- The two Lean files disagree on the 10-round active S-box count:
  `proofs/aes_counter_lemmas.lean` says 63 (diffusion 378),
  `proofs/aes_recursive_lemmas.lean` says 55 (trail weight 330). Both
  exceed the 97-bit inversion target, so the terminal result (NO BREAK)
  holds under either number. The 4-round and 8-round counts agree (25
  and 50). The degree (127) agrees. Only the 10-round S-box count
  differs. Owner to resolve: 55 or 63.
- `dag/manifest.json` is not in this repo. The outer ROM embeds its
  SHA-256 digest (1376fd6b...449f) in words 0..7, but the manifest file
  itself was not in any received package, so the digest cannot be
  verified against the file here. The example node record is at
  `dag/nodes/agc.gf256.mul.v2.json`.
- `racket/dag.rkt` save/load has a string/symbol key mismatch: `write-json`
  requires symbol keys, so `save-dag` fails on the string-ID graph, and
  `read-json` returns symbol keys, so a loaded graph cannot be traversed
  by string ID. A fix was tested in scratch (all 12 checks pass including
  the round-trip) and is offered, not installed.
- `verification/round_vectors.bin` holds 11 identical blocks, each bytes
  0..63. No distinct per-round states, no expected ciphertext. It is an
  input pattern, not round test vectors with expected outputs.
- KeyStep has no Futhark/C reference. The Futhark files contain no key
  schedule. KeyStep is a definition, not a verified equivalence.
- The bootloader BIST comment says gf_mul(0x57, imm=0x57) but the first
  call is gf_mul(0x51, 0x57). Comment only.
- The microsequencer LOAD ignores the src field. The src operands in the
  .uasm are decorative for LOAD.
- On a manifest mismatch the nested ROM controller fail-stops:
  VERIFY_MANIFEST does not advance the outer PC and there is no error
  output. manifest_ok stays 0. This is a design choice.
- The AGC file in the original microrom package still carries CA OCT7
  (7 iterations). The copy in this repo (`agc/aes_custom_agc.agc`) carries
  the owner-ordered OCT10 fix (8 iterations). The packaged copy predates
  the fix.

## License

SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See `LICENSE`.
