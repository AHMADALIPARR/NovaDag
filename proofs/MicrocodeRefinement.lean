import Mathlib.Data.Fin.Basic
import Mathlib.Tactic

/-!
# MicrocodeRefinement.lean
Formalizes the 32-bit RIJNDAEL-uROM instruction decoding, bootloader entry
(`0x000 -> 0x040`), and 10-round firmware loop refinement contract.
-/

namespace RijndaelMicroROM

def bootEntryAddr : Nat := 0x000
def fwEntryAddr   : Nat := 0x040
def loopCountInit : Nat := 9

/-- 32-bit instruction field extractors matching `isa.toml` and `microsequencer.vhd`. -/
def decodeOpcode (w : Nat) : Nat := (w >>> 28) &&& 0xF
def decodeDest   (w : Nat) : Nat := (w >>> 22) &&& 0x3F
def decodeSrc    (w : Nat) : Nat := (w >>> 16) &&& 0x3F
def decodeCtrl   (w : Nat) : Nat := (w >>> 12) &&& 0xF
def decodeImm12  (w : Nat) : Nat := w &&& 0xFFF

/-- Bootloader handoff instruction at 0x007: BRANCH STATUS, 0x00, 0x4, 0x040 -> 0x91804040. -/
def instrBootBranch : Nat := 0x91804040

/-- Firmware loop-count load at 0x043: LOAD LC0, RCON, 0x0, 0x009 -> 0x11140009. -/
def instrLoadLC0 : Nat := 0x11140009

/-- Firmware HALT at 0x04F -> 0xF0000000. -/
def instrHalt : Nat := 0xF0000000

theorem boot_branch_decodes_to_fw_entry :
    decodeOpcode instrBootBranch = 0x9
    ∧ decodeCtrl instrBootBranch = 0x4
    ∧ decodeImm12 instrBootBranch = fwEntryAddr := by
  refine ⟨?_, ?_, ?_⟩ <;> native_decide

theorem fw_rounds_equal_ten :
    loopCountInit + 1 = 10 := by
  native_decide

theorem load_lc0_decodes_nine :
    decodeOpcode instrLoadLC0 = 0x1
    ∧ decodeDest instrLoadLC0 = 0x04
    ∧ decodeImm12 instrLoadLC0 = loopCountInit := by
  refine ⟨?_, ?_, ?_⟩ <;> native_decide

theorem halt_opcode_is_0xF :
    decodeOpcode instrHalt = 0xF := by
  native_decide

end RijndaelMicroROM
