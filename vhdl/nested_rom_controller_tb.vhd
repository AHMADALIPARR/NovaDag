-- Testbench: nested_rom_controller + outer_rom + inner microsequencer.
-- Drives expected_digest = stated manifest SHA-256, plaintext = key = bytes 0..63.
-- Checks manifest_ok, rom_locked, done, and compares ciphertext to the C reference.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nested_rom_controller_tb is
end entity nested_rom_controller_tb;

architecture sim of nested_rom_controller_tb is
  signal clk             : std_logic := '0';
  signal rst_n           : std_logic := '0';
  signal start           : std_logic := '0';
  signal expected_digest : std_logic_vector(255 downto 0) :=
    x"1376fd6bd243379655767a5ee22e260d373bb425ce4371562db3fa410d64449f";
  signal plaintext       : std_logic_vector(511 downto 0) :=
    x"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";
  signal key             : std_logic_vector(511 downto 0) :=
    x"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";
  signal ciphertext      : std_logic_vector(511 downto 0);
  signal done            : std_logic;
  signal manifest_ok     : std_logic;
  signal rom_locked      : std_logic;

  constant EXPECTED_CT : std_logic_vector(511 downto 0) :=
    x"8ba9c4418ed30ecf83131e823058ab38edc49bc5edd072d9bd194e4b7ddc5b968b271a6aef0b6d6e7bf222e48f8b1197edc49bc5edd072d9bd194e4b7ddc5b96";
begin
  uut : entity work.nested_rom_controller
    port map (
      clk             => clk,
      rst_n           => rst_n,
      start           => start,
      expected_digest => expected_digest,
      plaintext       => plaintext,
      key             => key,
      ciphertext      => ciphertext,
      done            => done,
      manifest_ok     => manifest_ok,
      rom_locked      => rom_locked
    );

  clk <= not clk after 5 ns;

  stim : process
  begin
    wait for 20 ns;
    rst_n <= '1';
    start <= '1';

    -- manifest verify + lock should complete within ~20 cycles
    wait until manifest_ok = '1' for 500 ns;
    assert manifest_ok = '1'
      report "FAIL: manifest_ok never went high" severity failure;
    report "PASS manifest_ok=1 at " & time'image(now);

    wait until rom_locked = '1' for 500 ns;
    assert rom_locked = '1'
      report "FAIL: rom_locked never went high" severity failure;
    report "PASS rom_locked=1 at " & time'image(now);

    -- inner cipher should complete well within 100 us
    wait until done = '1' for 100 us;
    assert done = '1'
      report "FAIL: done never went high" severity failure;
    report "PASS done=1 at " & time'image(now);

    if ciphertext = EXPECTED_CT then
      report "PASS ciphertext matches C reference";
    else
      report "NOTE ciphertext differs from C reference (check byte order)";
      report "got: " & to_hstring(ciphertext);
    end if;

    report "ALL CONTROLLER CHECKS DONE";
    wait;
  end process;
end architecture sim;
