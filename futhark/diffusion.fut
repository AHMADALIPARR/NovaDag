-- diffusion.fut — Futhark 512-bit ShiftRows and MixColumns diffusion reference
import "gf256"

let shift_perm_16: [16]i64 = [0,5,10,15, 4,9,14,3, 8,13,2,7, 12,1,6,11]

def shift_rows_512 (s: [64]u8) : [64]u8 =
  tabulate 64 (\i ->
    let lane = i / 16
    let pos  = i % 16
    in s[lane * 16 + shift_perm_16[pos]])

def mix_columns_512 (s: [64]u8) : [64]u8 =
  flatten (tabulate 16 (\c ->
    let a0 = s[c*4 + 0]
    let a1 = s[c*4 + 1]
    let a2 = s[c*4 + 2]
    let a3 = s[c*4 + 3]
    in [ gf_mul 0x02u8 a0 ^ gf_mul 0x03u8 a1 ^ a2 ^ a3
       , a0 ^ gf_mul 0x02u8 a1 ^ gf_mul 0x03u8 a2 ^ a3
       , a0 ^ a1 ^ gf_mul 0x02u8 a2 ^ gf_mul 0x03u8 a3
       , gf_mul 0x03u8 a0 ^ a1 ^ a2 ^ gf_mul 0x02u8 a3
       ]))
