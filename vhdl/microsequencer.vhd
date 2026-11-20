-- ============================================================================
-- microsequencer.vhd
-- Top-level 32-bit RIJNDAEL-uROM Microsequencer (Bootloader + 512-bit Core).
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity microsequencer is
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;
    start      : in  std_logic;
    boot_we    : in  std_logic;
    boot_addr  : in  unsigned(11 downto 0);
    boot_wdata : in  std_logic_vector(31 downto 0);
    plaintext  : in  std_logic_vector(511 downto 0);
    key        : in  std_logic_vector(511 downto 0);
    ciphertext : out std_logic_vector(511 downto 0);
    done       : out std_logic;
    boot_valid : out std_logic
  );
end entity microsequencer;

architecture rtl of microsequencer is

  signal pc          : unsigned(11 downto 0);
  signal instr       : std_logic_vector(31 downto 0);
  signal opcode      : std_logic_vector(3 downto 0);
  signal dest        : std_logic_vector(5 downto 0);
  signal src         : std_logic_vector(5 downto 0);
  signal ctrl        : std_logic_vector(3 downto 0);
  signal imm12       : unsigned(11 downto 0);

  signal urom_we     : std_logic;
  signal urom_waddr  : unsigned(11 downto 0);
  signal urom_wdata  : std_logic_vector(31 downto 0);
  signal boot_done_s : std_logic;

  signal state_reg   : std_logic_vector(511 downto 0);
  signal rkey_reg    : std_logic_vector(511 downto 0);
  signal boot_reg    : std_logic_vector(7 downto 0);
  signal crc_reg     : std_logic_vector(7 downto 0);
  signal lc0, lc1    : unsigned(11 downto 0);
  signal round_idx   : unsigned(3 downto 0);

  signal mul_out     : std_logic_vector(7 downto 0);
  signal sub_out     : std_logic_vector(511 downto 0);
  signal shift_out   : std_logic_vector(511 downto 0);
  signal mix_out     : std_logic_vector(511 downto 0);
  signal keystep_out : std_logic_vector(511 downto 0);

begin

  opcode <= instr(31 downto 28);
  dest   <= instr(27 downto 22);
  src    <= instr(21 downto 16);
  ctrl   <= instr(15 downto 12);
  imm12  <= unsigned(instr(11 downto 0));

  u_boot : entity work.bootloader
    port map (
      clk => clk, rst_n => rst_n,
      boot_we => boot_we, boot_addr => boot_addr, boot_wdata => boot_wdata,
      boot_done => boot_done_s,
      urom_we => urom_we, urom_waddr => urom_waddr, urom_wdata => urom_wdata,
      boot_valid => boot_valid
    );

  u_urom : entity work.rijndael_urom
    port map (
      clk => clk, we => urom_we, waddr => urom_waddr, wdata => urom_wdata,
      address => pc, data => instr
    );

  u_alu : entity work.gf256_alu
    port map (
      a_byte => boot_reg,
      b_byte => instr(7 downto 0),
      mul_out => mul_out,
      state_in => state_reg,
      key_in => rkey_reg,
      round_idx => round_idx,
      tweak_byte => instr(7 downto 0),
      sub_out => sub_out,
      shift_out => shift_out,
      mix_out => mix_out,
      keystep_out => keystep_out
    );

  process(clk, rst_n)
  begin
    if rst_n = '0' then
      pc          <= (others => '0');
      state_reg   <= (others => '0');
      rkey_reg    <= (others => '0');
      boot_reg    <= (others => '0');
      crc_reg     <= (others => '0');
      lc0         <= (others => '0');
      lc1         <= (others => '0');
      round_idx   <= (others => '0');
      ciphertext  <= (others => '0');
      done        <= '0';
      boot_done_s <= '0';
    elsif rising_edge(clk) then
      if boot_we = '1' then
        pc <= (others => '0');
      else
        case opcode is
          when x"0" => -- NOP
            pc <= pc + 1;

          when x"1" => -- LOAD
            if dest = "000000" then
              state_reg <= plaintext;
              round_idx <= (others => '0');
            elsif dest = "000001" then
              rkey_reg <= key;
            elsif dest = "000010" then
              boot_reg <= instr(7 downto 0);
            elsif dest = "000011" then
              crc_reg <= instr(7 downto 0);
            elsif dest = "000100" then
              lc0 <= imm12;
            elsif dest = "000101" then
              lc1 <= imm12;
            end if;
            pc <= pc + 1;

          when x"2" => -- STORE
            ciphertext <= state_reg;
            pc <= pc + 1;

          when x"3" => -- XOR
            if dest = "000000" then
              state_reg <= state_reg xor rkey_reg;
            elsif dest = "000011" then
              crc_reg <= crc_reg xor boot_reg;
            end if;
            pc <= pc + 1;

          when x"4" => -- GF_MUL
            boot_reg <= mul_out;
            pc <= pc + 1;

          when x"5" => -- SUBBYTE
            state_reg <= sub_out;
            pc <= pc + 1;

          when x"6" => -- SHIFTROW
            state_reg <= shift_out;
            pc <= pc + 1;

          when x"7" => -- MIXCOLUMN
            state_reg <= mix_out;
            pc <= pc + 1;

          when x"8" => -- KEYSTEP
            rkey_reg  <= keystep_out;
            round_idx <= round_idx + 1;
            pc <= pc + 1;

          when x"9" => -- BRANCH
            if ctrl(2 downto 0) = "000" then
              pc <= imm12;
            elsif ctrl(2 downto 0) = "100" and start = '1' then
              boot_done_s <= '1';
              done        <= '0';
              pc          <= imm12;
            else
              boot_done_s <= '1';
              pc <= pc + 1;
            end if;

          when x"A" => -- LOOP
            if ctrl(1 downto 0) = "00" then
              if lc0 > 1 then
                lc0 <= lc0 - 1;
                pc  <= imm12;
              else
                lc0 <= (others => '0');
                pc  <= pc + 1;
              end if;
            else
              if lc1 > 1 then
                lc1 <= lc1 - 1;
                pc  <= imm12;
              else
                lc1 <= (others => '0');
                pc  <= pc + 1;
              end if;
            end if;

          when x"F" => -- HALT
            done <= '1';
            pc   <= pc + 1;

          when others =>
            pc <= pc + 1;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
