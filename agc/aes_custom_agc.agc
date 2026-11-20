#=============================================================================
# aes_custom_agc.agc
# Lowered target: Apollo Guidance Computer (AGC Block II / yaYUL Assembly)
# Source: Custom 10-round AES-derived block cipher & branchless gf_mul(a, b)
#
# Architecture notes (AGC Block II, 15-bit 1's-complement words, octal):
#   - Bytes (8-bit) are stored in the low 8 bits [7:0] of 15-bit words (00377 oct).
#   - Erasable memory (0000-3777 oct) holds state[16], rk[16], and temps.
#   - Fixed memory (core rope) holds SBOX[256], RCON[10], and code.
#   - Bitwise XOR(A, B) uses Block II extracode `EXTEND; RXOR L` (L = channel 001).
#   - Shifts use AGC editing registers: SR (0021), CYL (0022), CYR (0020).
#   - Branchless mask: `(0 - bit)` in 8-bit is `CS bit; AD ONE; MASK 00377`
#     or `CCS` / `MASK` with `00377` (octal 0xFF) and `00033` (octal 0x1B).
# ==============================================================================

                SETLOC  00100           # Erasable memory (RAM) allocation
                BANK

# --- Central & Editing Register Equates (AGC Block II) ---
A               EQUALS  00000
L               EQUALS  00001
Q               EQUALS  00002
CYR             EQUALS  00020           # Cycle right 1 bit on write
SR              EQUALS  00021           # Shift right 1 bit on write
CYL             EQUALS  00022           # Cycle left 1 bit on write
EDOP            EQUALS  00023           # Shift right 7 bits on write

# --- Erasable Temporaries for GFMUL & Round Engine ---
GFA             ERASE                   # Current multiplicand a (8-bit in 15-bit word)
GFB             ERASE                   # Current multiplier b
GFRES           ERASE                   # Accumulated product result
GFMASK          ERASE                   # Branchless 8-bit mask (00000 or 00377)
GFCARRY         ERASE                   # Carry bit (a >> 7)
GFIDX           ERASE                   # Loop counter (8 iterations: 7 down to 0)
GFRET           ERASE                   # Saved return address (Q)

TMP0            ERASE
TMP1            ERASE
TMP2            ERASE
TMP3            ERASE
ROUND           ERASE                   # Round counter (1..10)
PTR             ERASE                   # Indexing temporary

STATE           ERASE   +16D            # 16-byte cipher state (1 byte/word)
RKEY            ERASE   +16D            # 16-byte current round key
TMPST           ERASE   +16D            # 16-byte scratch for ShiftRows

# ==============================================================================
# FIXED MEMORY (CORE ROPE) — CONSTANTS & LOWERED ROUTINES
# ==============================================================================
                BANK    02
                SETLOC  04000

# --- Octal Constants ---
OCT0            OCT     00000
OCT1            OCT     00001
OCT2            OCT     00002
OCT3            OCT     00003
OCT7            OCT     00007
OCT10           OCT     00010           # 8 decimal
OCT16           OCT     00020           # 16 decimal
OCT1B           OCT     00033           # 0x1B irreducible polynomial
OCT80           OCT     00200           # 0x80 MSB of byte
OCTFF           OCT     00377           # 0xFF 8-bit byte mask
OCTA5           OCT     00245           # 0xA5 custom AES-derived tweak
DEC9            DEC     9

# --- RCON[0..9] in octal ---
RCON            OCT     00001           # 0x01
                OCT     00002           # 0x02
                OCT     00004           # 0x04
                OCT     00010           # 0x08
                OCT     00020           # 0x10
                OCT     00040           # 0x20
                OCT     00100           # 0x40
                OCT     00200           # 0x80
                OCT     00033           # 0x1B
                OCT     00066           # 0x36

# ==============================================================================
# SUBROUTINE: GFMUL
# Lowered from C:
#   uint8_t gf_mul(uint8_t a, uint8_t b)
# Inputs:  GFA = a (low 8 bits), GFB = b (low 8 bits)
# Output:  A   = gf_mul(a, b) (low 8 bits)
# ==============================================================================
GFMUL           XCH     Q               # Save return address
                TS      GFRET
                CA      OCT0            # result = 0
                TS      GFRES
                CA      OCT10           # 8 decimal (GFIDX counts 8 down to 1, 8 iterations)
                TS      GFIDX

GFLOOP          CA      GFB             # mask = (0 - (b & 1)) & 0xFF
                MASK    OCT1            # A = b & 1 (0 or 1)
                CS      A               # A = -A (1's comp: -0 or -1 = 77776)
                AD      OCT1            # A = 1 - (b & 1)? Wait: 0 - bit in 2's comp:
                MASK    OCT1            # Recompute cleanly via (0 - bit) & 0xFF:
                CA      GFB
                MASK    OCT1
                TS      TMP0            # TMP0 = b & 1 (0 or 1)
                CA      OCT0
                SU      TMP0            # A = -(b & 1) in 1's complement (77777 or 77776)
                MASK    OCTFF           # If bit=0 -> 00000; if bit=1 -> 00376?
                # Exact branchless 8-bit mask: (00377 + 1 - bit) & 00377 -> 00000 or 00377
                CA      OCTFF
                AD      OCT1            # A = 00400
                SU      TMP0            # A = 00400 (if bit=0) or 00377 (if bit=1)
                MASK    OCTFF           # A = 00000 (if bit=0) or 00377 (if bit=1)
                TS      GFMASK

                CA      GFA             # result ^= (a & mask)
                MASK    GFMASK
                TS      L               # L = a & mask
                CA      GFRES
                EXTEND
                RXOR    L               # A = GFRES XOR (a & mask)
                TS      GFRES

                CA      GFA             # carry = (a >> 7) & 1
                TS      EDOP            # EDOP shifts right by 7 bits
                CA      EDOP
                MASK    OCT1
                TS      GFCARRY         # GFCARRY = 0 or 1

                CA      OCTFF           # carry_mask = 0xFF if carry=1 else 0x00
                AD      OCT1
                SU      GFCARRY
                MASK    OCTFF
                MASK    OCT1B           # A = 0x1B & carry_mask
                TS      TMP1

                CA      GFA             # a = ((a << 1) & 0xFF) ^ TMP1
                TS      CYL             # Cycle left 1 bit
                CA      CYL
                MASK    OCTFF           # Mask to low 8 bits
                TS      L
                CA      TMP1
                EXTEND
                RXOR    L               # A = ((a << 1) & 0xFF) ^ (0x1B & carry_mask)
                TS      GFA

                CA      GFB             # b >>= 1
                TS      SR              # Arithmetic shift right 1 (GFB >= 0, so logical)
                CA      SR
                MASK    OCTFF
                TS      GFB

                CCS     GFIDX           # Decrement loop counter; loop if > 0
                TCF     GFNEXT
                TCF     GFDONE          # GFIDX == 0 -> finished 8th iteration
GFNEXT          TS      GFIDX           # CCS already stored (GFIDX - 1) in A
                TCF     GFLOOP

GFDONE          CA      GFRES           # Return result in A
                MASK    OCTFF
                INDEX   GFRET
                TC      00000           # Return to caller

# ==============================================================================
# SUBROUTINE: ADDROUNDKEY (16 bytes: STATE[i] ^= RKEY[i])
# ==============================================================================
ADDKEY          XCH     Q
                TS      TMP3
                CA      OCT16
                SU      OCT1
                TS      PTR             # PTR = 15 down to 0
AKLOOP          INDEX   PTR
                CA      RKEY
                TS      L
                INDEX   PTR
                CA      STATE
                EXTEND
                RXOR    L
                INDEX   PTR
                TS      STATE
                CCS     PTR
                TCF     AKNEXT
                INDEX   TMP3
                TC      00000
AKNEXT          TS      PTR
                TCF     AKLOOP

# ==============================================================================
# SUBROUTINE: SUBBYTES (16 bytes: STATE[i] = SBOX[STATE[i]])
# ==============================================================================
SUBBYTES        XCH     Q
                TS      TMP3
                CA      OCT16
                SU      OCT1
                TS      PTR
SBLOOP          INDEX   PTR
                CA      STATE
                TS      TMP0            # Byte index 0..255
                INDEX   TMP0
                CA      SBOX
                INDEX   PTR
                TS      STATE
                CCS     PTR
                TCF     SBNEXT
                INDEX   TMP3
                TC      00000
SBNEXT          TS      PTR
                TCF     SBLOOP

# ==============================================================================
# SUBROUTINE: AES_CUSTOM_10R (Top-level 10-round encryption loop)
# Assumes STATE[0..15] = plaintext, RKEY[0..15] = initial 128-bit key
# ==============================================================================
AESENC          TC      ADDKEY          # Initial AddRoundKey (Round 0)
                CA      DEC9            # Rounds 1..9 (with MixColumns)
                TS      ROUND
RNDLOOP         TC      SUBBYTES
                TC      SHIFTROWS
                TC      MIXCOLS
                TC      KEYSTEP
                TC      ADDKEY
                CCS     ROUND
                TCF     RNDNEXT
                TCF     RNDFIN
RNDNEXT         TS      ROUND
                TCF     RNDLOOP

RNDFIN          TC      SUBBYTES        # Final Round 10 (no MixColumns)
                TC      SHIFTROWS
                TC      KEYSTEP
                TC      ADDKEY
                TC      00000           # Halt / return to executive

# --- Stubs for ShiftRows, MixColumns (calls GFMUL), KeyStep (uses OCTA5), SBOX ---
SHIFTROWS       TC      Q               # Byte permutation on STATE[0..15]
MIXCOLS         TC      Q               # 4 columns x 4 rows calling GFMUL(0x02/0x03, a)
KEYSTEP         TC      Q               # Advances RKEY using SBOX, RCON, and OCTA5

SBOX            OCT     00143           # 0x63 (first entry of 256-word core-rope LUT)
                OCT     00174           # 0x7C
                OCT     00167           # 0x77
                OCT     00173           # 0x7B
                # ... (remaining 252 S-box words in core rope)
