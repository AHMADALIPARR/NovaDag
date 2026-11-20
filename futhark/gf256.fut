-- gf256.fut — Futhark mathematical reference for GF(2^8) multiplication

def gf_mul (a: u8) (b: u8) : u8 =
  let (result, _, _) =
    loop (r, x, y) = (0u8, a, b)
    for _i < 8 do
      let mask = 0u8 - (y & 1u8)
      let r_next = r ^ (x & mask)
      let carry = x >> 7
      let x_next = (x << 1) ^ (0x1bu8 * carry)
      let y_next = y >> 1
      in (r_next, x_next, y_next)
  in result

entry gf_pairs (a: []u8) (b: []u8) : []u8 =
  map2 gf_mul a b
