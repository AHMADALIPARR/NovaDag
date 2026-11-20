-- aes_custom_tb.vhd — Testbench for aes_custom_top (GHDL).
-- Drives the standard AES test vector (pt 3243f6a8885a308d313198a2e0370734,
-- key 2b7e151628aed2a6abf7158809cf4f3c) and checks the ciphertext against
-- the C implementation's output: 73b5fe0471cc3d8b18b58c16c09ef686.
-- (NOT standard AES-128 output — the custom 0xA5 tweak changes the
-- round keys, so this is the custom cipher's expected value.)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_custom_tb is
end entity aes_custom_tb;

architecture sim of aes_custom_tb is
    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal start      : std_logic := '0';
    signal plaintext  : std_logic_vector(127 downto 0) := (others => '0');
    signal key        : std_logic_vector(127 downto 0) := (others => '0');
    signal ciphertext : std_logic_vector(127 downto 0);
    signal done       : std_logic;

    constant EXPECTED_CT : std_logic_vector(127 downto 0) := x"73b5fe0471cc3d8b18b58c16c09ef686";
    constant EXPECTED_ZERO_CT : std_logic_vector(127 downto 0) := x"7716fa3975247611bdd9d15eef97ea74";
begin
    dut : entity work.aes_custom_top
        port map (
            clk        => clk,
            rst_n      => rst_n,
            start      => start,
            plaintext  => plaintext,
            key        => key,
            ciphertext => ciphertext,
            done       => done
        );

    clk <= not clk after 5 ns;

    stim : process
    begin
        -- Reset
        rst_n <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait for 10 ns;

        -- Apply standard AES test vector
        plaintext <= x"3243f6a8885a308d313198a2e0370734";
        key       <= x"2b7e151628aed2a6abf7158809cf4f3c";
        start     <= '1';
        wait until rising_edge(clk);
        start     <= '0';

        -- Wait for done
        wait until done = '1';
        wait for 1 ns;

        if ciphertext = EXPECTED_CT then
            report "PASS: ciphertext matches C implementation (73b5fe0471cc3d8b18b58c16c09ef686)" severity note;
        else
            report "FAIL: ciphertext mismatch" severity error;
        end if;

        -- Second vector: all-zero plaintext and key (determinism check).
        -- Wait for the FSM to return to IDLE (done drops) before starting,
        -- otherwise the start pulse is missed while the FSM is in ST_DONE.
        wait until done = '0';
        wait until rising_edge(clk);
        plaintext <= (others => '0');
        key       <= (others => '0');
        start     <= '1';
        wait until rising_edge(clk);
        start     <= '0';
        wait until done = '1';
        wait for 1 ns;
        if ciphertext = EXPECTED_ZERO_CT then
            report "PASS: zero-vector ciphertext matches C (7716fa3975247611bdd9d15eef97ea74)" severity note;
        else
            report "FAIL: zero-vector ciphertext mismatch" severity error;
        end if;

        wait;
    end process stim;
end architecture sim;
