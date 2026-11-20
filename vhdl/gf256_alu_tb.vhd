-- gf256_alu_tb.vhd — testbench for the microrom gf256_alu mul_out port.
-- Drives (a_byte, b_byte) and checks mul_out against known GF(2^8) values.
-- The 512-bit datapath ports are tied to zero; only mul_out is checked.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gf256_alu_tb is
end entity gf256_alu_tb;

architecture sim of gf256_alu_tb is
  signal a_byte, b_byte, mul_out : std_logic_vector(7 downto 0);
  signal state_in, key_in : std_logic_vector(511 downto 0) := (others => '0');
  signal round_idx : unsigned(3 downto 0) := (others => '0');
  signal tweak_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal sub_out, shift_out, mix_out, keystep_out : std_logic_vector(511 downto 0);
begin
  dut : entity work.gf256_alu
    port map (
      a_byte => a_byte, b_byte => b_byte, mul_out => mul_out,
      state_in => state_in, key_in => key_in, round_idx => round_idx,
      tweak_byte => tweak_byte,
      sub_out => sub_out, shift_out => shift_out,
      mix_out => mix_out, keystep_out => keystep_out
    );

  process
    procedure check_mul(a, b, expected : std_logic_vector(7 downto 0)) is
    begin
      a_byte <= a;
      b_byte <= b;
      wait for 10 ns;
      assert mul_out = expected
        report "gf_mul mismatch"
        severity failure;
    end procedure;
  begin
    -- Standard AES GF test values
    check_mul(x"57", x"83", x"C1");
    check_mul(x"57", x"13", x"FE");
    check_mul(x"02", x"8D", x"01");
    check_mul(x"00", x"00", x"00");
    check_mul(x"01", x"80", x"80");
    check_mul(x"01", x"FF", x"FF");
    check_mul(x"FF", x"FF", x"13");
    check_mul(x"02", x"02", x"04");
    check_mul(x"03", x"03", x"05");
    check_mul(x"80", x"02", x"1B");
    report "GF256_ALU_TB PASS";
    wait;
  end process;
end architecture sim;
