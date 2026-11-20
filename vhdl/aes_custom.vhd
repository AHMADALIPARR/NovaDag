-- ============================================================================
-- aes_custom.vhd
-- VHDL RTL implementation for FPGA and ASIC targets of the custom 10-round
-- AES-derived block cipher using constant-time GF(2^8) multiplication.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_custom_top is
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        start      : in  std_logic;
        plaintext  : in  std_logic_vector(127 downto 0);
        key        : in  std_logic_vector(127 downto 0);
        ciphertext : out std_logic_vector(127 downto 0);
        done       : out std_logic
    );
end entity aes_custom_top;

architecture rtl of aes_custom_top is

    constant CUSTOM_TWEAK : std_logic_vector(7 downto 0) := x"A5";

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

    type rcon_rom_t is array (1 to 10) of std_logic_vector(7 downto 0);
    constant RCON : rcon_rom_t := (
        x"01", x"02", x"04", x"08", x"10", x"20", x"40", x"80", x"1B", x"36"
    );

    -- Constant-time 8-step GF(2^8) multiplier (mod 0x11B)
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

    function get_byte(v : std_logic_vector(127 downto 0); idx : integer) return std_logic_vector is
    begin
        return v(127 - idx*8 downto 120 - idx*8);
    end function get_byte;

    function sub_bytes_fn(s : std_logic_vector(127 downto 0)) return std_logic_vector is
        variable out_v : std_logic_vector(127 downto 0);
    begin
        for i in 0 to 15 loop
            out_v(127 - i*8 downto 120 - i*8) := SBOX(to_integer(unsigned(get_byte(s, i))));
        end loop;
        return out_v;
    end function sub_bytes_fn;

    function shift_rows_fn(s : std_logic_vector(127 downto 0)) return std_logic_vector is
        variable out_v : std_logic_vector(127 downto 0);
    begin
        out_v(127 downto 120) := get_byte(s, 0);  out_v(119 downto 112) := get_byte(s, 5);
        out_v(111 downto 104) := get_byte(s, 10); out_v(103 downto 96)  := get_byte(s, 15);
        out_v(95  downto 88)  := get_byte(s, 4);  out_v(87  downto 80)  := get_byte(s, 9);
        out_v(79  downto 72)  := get_byte(s, 14); out_v(71  downto 64)  := get_byte(s, 3);
        out_v(63  downto 56)  := get_byte(s, 8);  out_v(55  downto 48)  := get_byte(s, 13);
        out_v(47  downto 40)  := get_byte(s, 2);  out_v(39  downto 32)  := get_byte(s, 7);
        out_v(31  downto 24)  := get_byte(s, 12); out_v(23  downto 16)  := get_byte(s, 1);
        out_v(15  downto 8)   := get_byte(s, 6);  out_v(7   downto 0)   := get_byte(s, 11);
        return out_v;
    end function shift_rows_fn;

    function mix_columns_fn(s : std_logic_vector(127 downto 0)) return std_logic_vector is
        variable out_v : std_logic_vector(127 downto 0);
        variable a0, a1, a2, a3 : std_logic_vector(7 downto 0);
    begin
        for c in 0 to 3 loop
            a0 := get_byte(s, c*4 + 0);
            a1 := get_byte(s, c*4 + 1);
            a2 := get_byte(s, c*4 + 2);
            a3 := get_byte(s, c*4 + 3);
            out_v(127 - (c*4+0)*8 downto 120 - (c*4+0)*8) := gf_mul(x"02", a0) xor gf_mul(x"03", a1) xor a2 xor a3;
            out_v(127 - (c*4+1)*8 downto 120 - (c*4+1)*8) := a0 xor gf_mul(x"02", a1) xor gf_mul(x"03", a2) xor a3;
            out_v(127 - (c*4+2)*8 downto 120 - (c*4+2)*8) := a0 xor a1 xor gf_mul(x"02", a2) xor gf_mul(x"03", a3);
            out_v(127 - (c*4+3)*8 downto 120 - (c*4+3)*8) := gf_mul(x"03", a0) xor a1 xor a2 xor gf_mul(x"02", a3);
        end loop;
        return out_v;
    end function mix_columns_fn;

    function next_round_key(prev_rk : std_logic_vector(127 downto 0); rnd : integer) return std_logic_vector is
        variable w0, w1, w2, w3, nw0, nw1, nw2, nw3, rot_sub : std_logic_vector(31 downto 0);
    begin
        w0 := prev_rk(127 downto 96);
        w1 := prev_rk(95  downto 64);
        w2 := prev_rk(63  downto 32);
        w3 := prev_rk(31  downto 0);
        rot_sub := SBOX(to_integer(unsigned(w3(23 downto 16)))) &
                   SBOX(to_integer(unsigned(w3(15 downto 8))))  &
                   SBOX(to_integer(unsigned(w3(7  downto 0))))  &
                   SBOX(to_integer(unsigned(w3(31 downto 24))));
        nw0 := w0 xor rot_sub xor ((RCON(rnd) xor CUSTOM_TWEAK) & x"000000");
        nw1 := w1 xor nw0;
        nw2 := w2 xor nw1;
        nw3 := w3 xor nw2;
        return nw0 & nw1 & nw2 & nw3;
    end function next_round_key;

    type fsm_t is (ST_IDLE, ST_ROUNDS, ST_DONE);
    signal fsm_state : fsm_t;
    signal round_cnt : integer range 0 to 10;
    signal state_reg : std_logic_vector(127 downto 0);
    signal rk_reg    : std_logic_vector(127 downto 0);

begin

    process(clk, rst_n)
        variable sb_v, sr_v, mc_v, nrk_v, nxt_v : std_logic_vector(127 downto 0);
    begin
        if rst_n = '0' then
            fsm_state  <= ST_IDLE;
            round_cnt  <= 0;
            state_reg  <= (others => '0');
            rk_reg     <= (others => '0');
            ciphertext <= (others => '0');
            done       <= '0';
        elsif rising_edge(clk) then
            case fsm_state is
                when ST_IDLE =>
                    done <= '0';
                    if start = '1' then
                        state_reg <= plaintext xor key;
                        rk_reg    <= key;
                        round_cnt <= 1;
                        fsm_state <= ST_ROUNDS;
                    end if;

                when ST_ROUNDS =>
                    sb_v := sub_bytes_fn(state_reg);
                    sr_v := shift_rows_fn(sb_v);
                    if round_cnt = 10 then
                        mc_v := sr_v;
                    else
                        mc_v := mix_columns_fn(sr_v);
                    end if;
                    nrk_v := next_round_key(rk_reg, round_cnt);
                    nxt_v := mc_v xor nrk_v;

                    state_reg <= nxt_v;
                    rk_reg    <= nrk_v;

                    if round_cnt = 10 then
                        ciphertext <= nxt_v;
                        done       <= '1';
                        fsm_state  <= ST_DONE;
                    else
                        round_cnt <= round_cnt + 1;
                    end if;

                when ST_DONE =>
                    done      <= '0';
                    fsm_state <= ST_IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
