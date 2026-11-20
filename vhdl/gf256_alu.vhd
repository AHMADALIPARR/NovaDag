-- ============================================================================
-- gf256_alu.vhd
-- Combinational GF(2^8) ALU and 512-bit (64-byte) AES-derived datapath.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gf256_alu is
  port (
    a_byte      : in  std_logic_vector(7 downto 0);
    b_byte      : in  std_logic_vector(7 downto 0);
    mul_out     : out std_logic_vector(7 downto 0);
    state_in    : in  std_logic_vector(511 downto 0);
    key_in      : in  std_logic_vector(511 downto 0);
    round_idx   : in  unsigned(3 downto 0);
    tweak_byte  : in  std_logic_vector(7 downto 0);
    sub_out     : out std_logic_vector(511 downto 0);
    shift_out   : out std_logic_vector(511 downto 0);
    mix_out     : out std_logic_vector(511 downto 0);
    keystep_out : out std_logic_vector(511 downto 0)
  );
end entity gf256_alu;

architecture rtl of gf256_alu is

  type sbox_rom_t is array (0 to 255) of std_logic_vector(7 downto 0);
  constant SBOX : sbox_rom_t := (
    x"63",x"7c",x"77",x"7b",x"f2",x"6b",x"6f",x"c5",x"30",x"01",x"67",x"2b",x"fe",x"d7",x"ab",x"76",
    x"ca",x"82",x"c9",x"7d",x"fa",x"59",x"47",x"f0",x"ad",x"d4",x"a2",x"af",x"9c",x"a4",x"72",x"c0",
    x"b7",x"fd",x"93",x"26",x"36",x"3f",x"f7",x"cc",x"34",x"a5",x"e5",x"f1",x"71",x"d8",x"31",x"15",
    x"04",x"c7",x"23",x"c3",x"18",x"96",x"05",x"9a",x"07",x"12",x"80",x"e2",x"eb",x"27",x"b2",x"75",
    x"09",x"83",x"2c",x"1a",x"1b",x"6e",x"5a",x"a0",x"52",x"3b",x"d6",x"b3",x"29",x"e3",x"2f",x"84",
    x"53",x"d1",x"00",x"ed",x"20",x"fc",x"b1",x"5b",x"6a",x"cb",x"be",x"39",x"4a",x"4c",x"58",x"cf",
    x"d0",x"ef",x"aa",x"fb",x"43",x"4d",x"33",x"85",x"45",x"f9",x"02",x"7f",x"50",x"3c",x"9f",x"a8",
    x"51",x"a3",x"40",x"8f",x"92",x"9d",x"38",x"f5",x"bc",x"b6",x"da",x"21",x"10",x"ff",x"f3",x"d2",
    x"cd",x"0c",x"13",x"ec",x"5f",x"97",x"44",x"17",x"c4",x"a7",x"7e",x"3d",x"64",x"5d",x"19",x"73",
    x"60",x"81",x"4f",x"dc",x"22",x"2a",x"90",x"88",x"46",x"ee",x"b8",x"14",x"de",x"5e",x"0b",x"db",
    x"e0",x"32",x"3a",x"0a",x"49",x"06",x"24",x"5c",x"c2",x"d3",x"ac",x"62",x"91",x"95",x"e4",x"79",
    x"e7",x"c8",x"37",x"6d",x"8d",x"d5",x"4e",x"a9",x"6c",x"56",x"f4",x"ea",x"65",x"7a",x"ae",x"08",
    x"ba",x"78",x"25",x"2e",x"1c",x"a6",x"b4",x"c6",x"e8",x"dd",x"74",x"1f",x"4b",x"bd",x"8b",x"8a",
    x"70",x"3e",x"b5",x"66",x"48",x"03",x"f6",x"0e",x"61",x"35",x"57",x"b9",x"86",x"c1",x"1d",x"9e",
    x"e1",x"f8",x"98",x"11",x"69",x"d9",x"8e",x"94",x"9b",x"1e",x"87",x"e9",x"ce",x"55",x"28",x"df",
    x"8c",x"a1",x"89",x"0d",x"bf",x"e6",x"42",x"68",x"41",x"99",x"2d",x"0f",x"b0",x"54",x"bb",x"16"
  );

  type rcon_rom_t is array (0 to 15) of std_logic_vector(7 downto 0);
  constant RCON : rcon_rom_t := (
    x"01",x"02",x"04",x"08",x"10",x"20",x"40",x"80",
    x"1b",x"36",x"6c",x"d8",x"ab",x"4d",x"9a",x"2f"
  );

  function gf_mul(a_in, b_in : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable a, b, res, mask, carry_mask : std_logic_vector(7 downto 0);
  begin
    a   := a_in;
    b   := b_in;
    res := (others => '0');
    for i in 0 to 7 loop
      mask       := (others => b(0));
      res        := res xor (a and mask);
      carry_mask := (others => a(7));
      a          := (a(6 downto 0) & '0') xor (x"1B" and carry_mask);
      b          := '0' & b(7 downto 1);
    end loop;
    return res;
  end function gf_mul;

begin

  mul_out <= gf_mul(a_byte, b_byte);

  -- 64-byte SubBytes
  gen_sub: for i in 0 to 63 generate
    sub_out(511 - i*8 downto 504 - i*8) <= SBOX(to_integer(unsigned(state_in(511 - i*8 downto 504 - i*8))));
  end generate;

  -- 64-byte ShiftRows (4x128-bit lanes, each lane shifted by AES ShiftRows)
  gen_shift_lane: for lane in 0 to 3 generate
    constant BASE : integer := 511 - lane * 128;
  begin
    shift_out(BASE - 0*8   downto BASE - 0*8   - 7) <= state_in(BASE - 0*8   downto BASE - 0*8   - 7);
    shift_out(BASE - 1*8   downto BASE - 1*8   - 7) <= state_in(BASE - 5*8   downto BASE - 5*8   - 7);
    shift_out(BASE - 2*8   downto BASE - 2*8   - 7) <= state_in(BASE - 10*8  downto BASE - 10*8  - 7);
    shift_out(BASE - 3*8   downto BASE - 3*8   - 7) <= state_in(BASE - 15*8  downto BASE - 15*8  - 7);
    shift_out(BASE - 4*8   downto BASE - 4*8   - 7) <= state_in(BASE - 4*8   downto BASE - 4*8   - 7);
    shift_out(BASE - 5*8   downto BASE - 5*8   - 7) <= state_in(BASE - 9*8   downto BASE - 9*8   - 7);
    shift_out(BASE - 6*8   downto BASE - 6*8   - 7) <= state_in(BASE - 14*8  downto BASE - 14*8  - 7);
    shift_out(BASE - 7*8   downto BASE - 7*8   - 7) <= state_in(BASE - 3*8   downto BASE - 3*8   - 7);
    shift_out(BASE - 8*8   downto BASE - 8*8   - 7) <= state_in(BASE - 8*8   downto BASE - 8*8   - 7);
    shift_out(BASE - 9*8   downto BASE - 9*8   - 7) <= state_in(BASE - 13*8  downto BASE - 13*8  - 7);
    shift_out(BASE - 10*8  downto BASE - 10*8  - 7) <= state_in(BASE - 2*8   downto BASE - 2*8   - 7);
    shift_out(BASE - 11*8  downto BASE - 11*8  - 7) <= state_in(BASE - 7*8   downto BASE - 7*8   - 7);
    shift_out(BASE - 12*8  downto BASE - 12*8  - 7) <= state_in(BASE - 12*8  downto BASE - 12*8  - 7);
    shift_out(BASE - 13*8  downto BASE - 13*8  - 7) <= state_in(BASE - 1*8   downto BASE - 1*8   - 7);
    shift_out(BASE - 14*8  downto BASE - 14*8  - 7) <= state_in(BASE - 6*8   downto BASE - 6*8   - 7);
    shift_out(BASE - 15*8  downto BASE - 15*8  - 7) <= state_in(BASE - 11*8  downto BASE - 11*8  - 7);
  end generate;

  -- 64-byte MixColumns (16 x 4-byte MDS columns)
  gen_mix_col: for c in 0 to 15 generate
    signal a0, a1, a2, a3 : std_logic_vector(7 downto 0);
  begin
    a0 <= state_in(511 - (c*4+0)*8 downto 504 - (c*4+0)*8);
    a1 <= state_in(511 - (c*4+1)*8 downto 504 - (c*4+1)*8);
    a2 <= state_in(511 - (c*4+2)*8 downto 504 - (c*4+2)*8);
    a3 <= state_in(511 - (c*4+3)*8 downto 504 - (c*4+3)*8);

    mix_out(511 - (c*4+0)*8 downto 504 - (c*4+0)*8) <= gf_mul(x"02", a0) xor gf_mul(x"03", a1) xor a2 xor a3;
    mix_out(511 - (c*4+1)*8 downto 504 - (c*4+1)*8) <= a0 xor gf_mul(x"02", a1) xor gf_mul(x"03", a2) xor a3;
    mix_out(511 - (c*4+2)*8 downto 504 - (c*4+2)*8) <= a0 xor a1 xor gf_mul(x"02", a2) xor gf_mul(x"03", a3);
    mix_out(511 - (c*4+3)*8 downto 504 - (c*4+3)*8) <= gf_mul(x"03", a0) xor a1 xor a2 xor gf_mul(x"02", a3);
  end generate;

  -- 512-bit KeyStep: RotWord + SubWord + RCON xor custom tweak
  process(key_in, round_idx, tweak_byte)
    variable rc : std_logic_vector(7 downto 0);
  begin
    rc := RCON(to_integer(round_idx)) xor tweak_byte;
    for i in 0 to 63 loop
      if i = 0 then
        keystep_out(511 downto 504) <= key_in(511 downto 504) xor SBOX(to_integer(unsigned(key_in(7 downto 0)))) xor rc;
      else
        keystep_out(511 - i*8 downto 504 - i*8) <= key_in(511 - i*8 downto 504 - i*8) xor key_in(511 - ((i+63) mod 64)*8 downto 504 - ((i+63) mod 64)*8);
      end if;
    end loop;
  end process;

end architecture rtl;
