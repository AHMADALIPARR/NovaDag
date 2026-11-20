# NovaDag

NovaDag is the RIJNDAEL-uROM verified transformation DAG. It carries a
custom cipher from mathematics to hardware through a versioned,
proof-carrying transformation graph, in which every new language, hardware
target, and mathematical refinement retains its lineage.

The critical rule: a transformation creates a new node. It never silently
rewrites its source. A node can exist before proof completion, but it cannot
claim verified equivalence without evidence.

## The cipher

NovaDag carries two cipher specifications. The 128-bit prototype is the
Apollo Guidance Computer (AGC) implementation of a custom AES-like cipher
with a 0xA5 tweak in the key schedule. The 512-bit cipher is the production
specification: a 64-byte state in four lanes of 16 bytes, ten rounds of
SubBytes, ShiftRows, MixColumns, and a 64-byte chained KeyStep. Both are
custom ciphers, not AES-128. The 0xA5 tweak changes the round keys, so the
output differs from standard AES-128.

The 512-bit cipher uses the permutation [0,5,10,15, 4,9,14,3, 8,13,2,7,
12,1,6,11] per lane for ShiftRows, the standard 4x4 GF(2^8) matrix for
MixColumns, and a chained key schedule: byte 0 is key[0] XOR SBOX(key[63])
XOR (RCON[round] XOR 0xA5), byte i is key[i] XOR key[i-1].

## Layers

Cryptol owns what a primitive means. `cryptol/GF256.cry` specifies
GF(2^8) multiplication mathematically, with the identity and commutativity
properties SAW proves.

SAW is the proof gate. `saw/obligations.md` registers the proof obligation
for each transformation: symbolic equivalence for C11, array equivalence
and differential tests for Futhark, instruction-semantic refinement for
AGC, RTL equivalence or model-checking for VHDL, instruction decoding and
sequencer equivalence for the uROM image, and semantics preservation and
provenance checks for the Racket IR.

Racket owns transformations and provenance. `racket/dag.rkt` loads and
saves the DAG, rejects duplicate identifiers, checks parent existence, and
prevents cycles. Every artifact gets a structured record under schema
`rijndael.dag.v1`, with its cryptographic parameters and its proof status.

The AGC layer holds the Apollo assembly of the 128-bit prototype. The C11
layer holds the CompCert-friendly reference implementations. The VHDL layer
holds the RTL: the GF(2^8) ALU, the bootloader, the microsequencer, the
uROM, and the nested outer ROM. The Futhark layer holds the array kernels.
The microcode layer holds the uROM assembler, the instruction set, and the
generated ROM image. Lean holds the formal invariants.

## The nested outer ROM

The outer ROM encapsulates the inner RIJNDAEL-uROM. Its first eight words
hold the 256-bit content-addressed SHA-256 digest of `dag/manifest.json`.
The nested ROM controller reads those words, verifies the digest against
the expected value, locks the inner microsequencer immutable, and dispatches
execution to inner address 0x040. On a digest mismatch the controller
fail-stops: the manifest flag stays low and the inner machine never starts.

## Verification

Every numeric claim in the stack is verified by execution. The C reference
compiles clean and runs. The VHDL analyzes and elaborates clean under GHDL
and passes simulation, including a hardware/software cross-verification of
the 128-bit cipher and of the full outer ROM controller driving the inner
microsequencer against the 512-bit C reference. The Futhark GF(2^8)
multiplication agrees with the C reference on all 65,536 input pairs. The
uROM generator reproduces the shipped ROM byte-identically. The Racket DAG
module passes its in-memory checks.

`STATUS.md` records the verification scope and the open items.

## Layout

```
NovaDag/
  agc/          Apollo assembly, 128-bit prototype
  c11/          CompCert-friendly C references and claim checks
  vhdl/         RTL: ALU, bootloader, microsequencer, uROM, outer ROM
  futhark/      Array kernels
  microcode/    uROM assembler, ISA, generated ROM image
  verification/ Test vectors and reference outputs
  proofs/       Lean 4 invariants and AES lemmas
  cryptol/      Mathematical specifications
  saw/          Proof obligations
  racket/       DAG transformation engine and tests
  dag/          DAG node records
  docs/         Architecture notes
```

## License

SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See `LICENSE`.
