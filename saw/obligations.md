# SAW Proof Obligations

For each transformation, SAW verifies the semantics of the supported
implementation against the Cryptol specification.

Core property:

  forall a, b in 0..255: C11GF(a, b) == CryptolGF(a, b)

SAW verifies C functions through LLVM bitcode and compares their symbolic
results with a Cryptol model. AGC and VHDL require their own faithful
semantic models or validated lowering paths before equivalent claims can
be established.

## Registered obligations

| DAG transformation | Required evidence |
|---|---|
| Cryptol -> C11 | SAW symbolic equivalence |
| Cryptol -> Futhark | Array equivalence and differential tests |
| Cryptol -> AGC | Instruction-semantic refinement proof |
| Cryptol -> VHDL | RTL equivalence or model-checking result |
| VHDL -> uROM image | Instruction decoding and sequencer equivalence |
| Any -> Racket IR | Semantics preservation and provenance checks |

## Admission rule

The Racket admission engine accepts a proof artifact only when its source
hash, target hash, specification hash, tool version, assumptions, and
verification result match the registered transformation.

A node can exist before proof completion, but it cannot claim verified
equivalence without evidence.
