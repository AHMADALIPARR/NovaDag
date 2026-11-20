-- ============================================================================
-- nested_rom_controller.vhd
-- Outer ROM Controller encapsulating the inner RIJNDAEL-uROM microsequencer.
--
-- Outer 32-bit Instruction Format (encapsulates inner 12-bit uROM addresses):
--   31..28 : OUTER_OP (0x1=READ_DIGEST, 0x2=VERIFY_MANIFEST,
--                      0x3=EXEC_INNER, 0x4=LOCK_IMMUTABLE, 0xF=OUTER_HALT)
--   27..24 : FLAGS    (bit 0 = allow_wcs_override)
--   23..12 : INNER_PC (12-bit inner uROM target address, e.g. 0x000 or 0x040)
--   11..0  : OUTER_IMM / next outer PC
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nested_rom_controller is
  port (
    clk             : in  std_logic;
    rst_n           : in  std_logic;
    start           : in  std_logic;
    expected_digest : in  std_logic_vector(255 downto 0);
    plaintext       : in  std_logic_vector(511 downto 0);
    key             : in  std_logic_vector(511 downto 0);
    ciphertext      : out std_logic_vector(511 downto 0);
    done            : out std_logic;
    manifest_ok     : out std_logic;
    rom_locked      : out std_logic
  );
end entity nested_rom_controller;

architecture rtl of nested_rom_controller is

  signal outer_pc     : unsigned(7 downto 0);
  signal outer_word   : std_logic_vector(31 downto 0);
  signal outer_op     : std_logic_vector(3 downto 0);
  signal digest_acc   : std_logic_vector(255 downto 0);
  signal digest_idx   : integer range 0 to 7;

  signal inner_start  : std_logic;
  signal inner_done   : std_logic;
  signal inner_bootok : std_logic;
  signal locked_reg   : std_logic;
  signal ok_reg       : std_logic;

begin

  outer_op <= outer_word(31 downto 28);

  u_outer_rom : entity work.outer_rom
    port map (
      address => outer_pc,
      data    => outer_word
    );

  -- Encapsulated inner RIJNDAEL-uROM microsequencer (immutable when locked_reg='1')
  u_inner_seq : entity work.microsequencer
    port map (
      clk        => clk,
      rst_n      => rst_n,
      start      => inner_start,
      boot_we    => '0', -- Locked immutable by outer ROM encapsulation
      boot_addr  => (others => '0'),
      boot_wdata => (others => '0'),
      plaintext  => plaintext,
      key        => key,
      ciphertext => ciphertext,
      done       => inner_done,
      boot_valid => inner_bootok
    );

  manifest_ok <= ok_reg;
  rom_locked  <= locked_reg;
  done        <= inner_done and ok_reg;

  process(clk, rst_n)
  begin
    if rst_n = '0' then
      outer_pc    <= (others => '0');
      digest_acc  <= (others => '0');
      digest_idx  <= 0;
      inner_start <= '0';
      locked_reg  <= '0';
      ok_reg      <= '0';
    elsif rising_edge(clk) then
      if outer_pc < 8 then
        -- Words 0..7 of Outer ROM hold the 256-bit content-addressed manifest SHA-256
        digest_acc(255 - digest_idx*32 downto 224 - digest_idx*32) <= outer_word;
        if digest_idx = 7 then
          outer_pc <= to_unsigned(8, 8);
        else
          digest_idx <= digest_idx + 1;
          outer_pc   <= outer_pc + 1;
        end if;
      else
        case outer_op is
          when x"2" => -- VERIFY_MANIFEST
            if digest_acc = expected_digest then
              ok_reg   <= '1';
              outer_pc <= outer_pc + 1;
            else
              ok_reg   <= '0';
            end if;

          when x"4" => -- LOCK_IMMUTABLE
            locked_reg <= '1';
            outer_pc   <= outer_pc + 1;

          when x"3" => -- EXEC_INNER (wait for start, trigger inner uROM)
            if ok_reg = '1' and start = '1' then
              inner_start <= '1';
            elsif inner_done = '1' then
              inner_start <= '0';
              outer_pc    <= outer_pc + 1;
            end if;

          when x"F" => -- OUTER_HALT
            inner_start <= '0';

          when others =>
            outer_pc <= outer_pc + 1;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
