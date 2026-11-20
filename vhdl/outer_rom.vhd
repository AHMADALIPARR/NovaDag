-- Auto-generated Outer ROM encapsulating inner RIJNDAEL-uROM
-- Embedded DAG Manifest SHA-256: 1376fd6bd243379655767a5ee22e260d373bb425ce4371562db3fa410d64449f
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity outer_rom is
  port (
    address : in  unsigned(7 downto 0);
    data    : out std_logic_vector(31 downto 0)
  );
end entity outer_rom;

architecture rtl of outer_rom is
  type rom_t is array (0 to 255) of std_logic_vector(31 downto 0);
  constant ROM : rom_t := (
      0 => x"1376FD6B", -- Manifest SHA-256 word 0
      1 => x"D2433796", -- Manifest SHA-256 word 1
      2 => x"55767A5E", -- Manifest SHA-256 word 2
      3 => x"E22E260D", -- Manifest SHA-256 word 3
      4 => x"373BB425", -- Manifest SHA-256 word 4
      5 => x"CE437156", -- Manifest SHA-256 word 5
      6 => x"2DB3FA41", -- Manifest SHA-256 word 6
      7 => x"0D64449F", -- Manifest SHA-256 word 7
      8 => x"20000000", -- OUTER VERIFY_MANIFEST
      9 => x"40000000", -- OUTER LOCK_IMMUTABLE
     10 => x"30040000", -- OUTER EXEC_INNER (inner_pc=0x040)
     11 => x"F0000000", -- OUTER HALT
    others => x"F0000000"
  );
begin
  data <= ROM(to_integer(address));
end architecture rtl;
