# RIJNDAEL-SUBLEQ OISC

A one-instruction-set computer (OISC) with a cryptographic microcode layer,
built on the NovaDag nested ROM design.

## Reference

Goldcrest-VP, Johannes Kepler University Linz (Lucas Klemmer, Sonja Gurtner,
Daniel Grosse). Goldcrest-VP implements the RISC-V RV32I instruction set
using a single underlying instruction, SUBLEQ. Its verification framework is
written in Racket with Rosette and SMT solvers. Goldcrest proves the core
architecture works: a full ISA synthesized from SUBLEQ microcode, with
formal verification of the microcode procedures.

Goldcrest is an independently researched reference. NovaDag keeps its own
Racket/Cryptol/SAW transformation contracts.

## Architecture

| Layer | Role |
|---|---|
| Cryptol + SAW | Mathematical specifications and verification |
| Racket + Rosette | SUBLEQ lowering, symbolic semantics, DAG transformations |
| Outer ROM — Microprogram Dispatch | Cipher operations become sequences of SUBLEQ instructions |
| Inner ROM — SUBLEQ Microcode | One instruction: subtract and branch |
| VHDL SUBLEQ Core | Memory, subtraction, comparison, program counter |
| Futhark Array Oracle | Reference mathematical results and differential testing |

## The physical instruction set

SUBLEQ. One instruction, three operands.

  Mb <- Mb - Ma
  PC <- c  if Mb <= 0
  PC <- PC + 3  if Mb > 0

## Cipher operations as SUBLEQ microprograms

| Cipher operation | SUBLEQ implementation |
|---|---|
| XOR | Construct from arithmetic and bitwise decomposition |
| GF(2^8) multiplication | Repeated shift, conditional reduction, XOR |
| SubBytes | Table addressing or arithmetic S-box |
| ShiftRows | Memory permutations |
| MixColumns | GF multiplication and XOR |
| Key expansion | SUBLEQ arithmetic and memory operations |
| 512-bit state | 64 byte-valued memory cells |

## Architectural decision

The physical instruction set stays strictly SUBLEQ. A hardware AES
accelerator or a special GF multiplication instruction would make it an
extended machine rather than a pure one-instruction computer.

## Milestone

A Racket lowering pass that takes a Cryptol-defined GF multiplication
function, produces SUBLEQ microcode, and proves its equivalence to the
reference for all 65,536 input pairs.

That gives the nested ROM a concrete purpose: a cryptographic virtual
machine constructed entirely over one physical instruction, with every
transformation recorded in the verification DAG.
