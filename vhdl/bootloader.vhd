-- ============================================================================
-- bootloader.vhd
-- Hardware Bootloader Controller for RIJNDAEL-uROM.
-- Supports Writable Control Store (WCS) firmware streaming on boot_we='1',
-- holds reset vector at 0x000, and asserts boot_valid once ready.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bootloader is
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;
    boot_we    : in  std_logic;
    boot_addr  : in  unsigned(11 downto 0);
    boot_wdata : in  std_logic_vector(31 downto 0);
    boot_done  : in  std_logic;
    urom_we    : out std_logic;
    urom_waddr : out unsigned(11 downto 0);
    urom_wdata : out std_logic_vector(31 downto 0);
    boot_valid : out std_logic
  );
end entity bootloader;

architecture rtl of bootloader is
  signal valid_reg : std_logic;
begin
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      valid_reg <= '0';
    elsif rising_edge(clk) then
      if boot_we = '1' then
        valid_reg <= '0';
      elsif boot_done = '1' then
        valid_reg <= '1';
      end if;
    end if;
  end process;

  urom_we    <= boot_we;
  urom_waddr <= boot_addr;
  urom_wdata <= boot_wdata;
  boot_valid <= valid_reg;
end architecture rtl;
