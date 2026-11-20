// ============================================================================
// aes_custom.sv
// SystemVerilog RTL implementation of the custom 10-round AES-derived cipher.
// Implements constant-time GF(2^8) multiplication, S-box, ShiftRows,
// MixColumns, and KeyExpansion directly as digital hardware circuits.
// ============================================================================

module aes_custom_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] plaintext,
    input  logic [127:0] key,
    output logic [127:0] ciphertext,
    output logic         done
);

    localparam logic [7:0] CUSTOM_TWEAK = 8'hA5;

    // Constant-time unrolled GF(2^8) multiplier (mod 0x11B)
    function automatic logic [7:0] gf_mul(input logic [7:0] a_in, input logic [7:0] b_in);
        logic [7:0] a, b, res, mask;
        logic       carry;
        begin
            a   = a_in;
            b   = b_in;
            res = 8'h00;
            for (int i = 0; i < 8; i++) begin
                mask  = {8{b[0]}};
                res   = res ^ (a & mask);
                carry = a[7];
                a     = {a[6:0], 1'b0} ^ (8'h1B & {8{carry}});
                b     = {1'b0, b[7:1]};
            end
            return res;
        end
    endfunction

    // AES S-box combinational LUT
    function automatic logic [7:0] sbox_lut(input logic [7:0] x);
        case (x)
            8'h00: return 8'h63; 8'h01: return 8'h7c; 8'h02: return 8'h77; 8'h03: return 8'h7b;
            8'h04: return 8'hf2; 8'h05: return 8'h6b; 8'h06: return 8'h6f; 8'h07: return 8'hc5;
            8'h08: return 8'h30; 8'h09: return 8'h01; 8'h0a: return 8'h67; 8'h0b: return 8'h2b;
            8'h0c: return 8'hfe; 8'h0d: return 8'hd7; 8'h0e: return 8'hab; 8'h0f: return 8'h76;
            8'h10: return 8'hca; 8'h11: return 8'h82; 8'h12: return 8'hc9; 8'h13: return 8'h7d;
            8'h14: return 8'hfa; 8'h15: return 8'h59; 8'h16: return 8'h47; 8'h17: return 8'hf0;
            8'h18: return 8'had; 8'h19: return 8'hd4; 8'h1a: return 8'ha2; 8'h1b: return 8'haf;
            8'h1c: return 8'h9c; 8'h1d: return 8'ha4; 8'h1e: return 8'h72; 8'h1f: return 8'hc0;
            8'h20: return 8'hb7; 8'h21: return 8'hfd; 8'h22: return 8'h93; 8'h23: return 8'h26;
            8'h24: return 8'h36; 8'h25: return 8'h3f; 8'h26: return 8'hf7; 8'h27: return 8'hcc;
            8'h28: return 8'h34; 8'h29: return 8'ha5; 8'h2a: return 8'he5; 8'h2b: return 8'hf1;
            8'h2c: return 8'h71; 8'h2d: return 8'hd8; 8'h2e: return 8'h31; 8'h2f: return 8'h15;
            8'h30: return 8'h04; 8'h31: return 8'hc7; 8'h32: return 8'h23; 8'h33: return 8'hc3;
            8'h34: return 8'h18; 8'h35: return 8'h96; 8'h36: return 8'h05; 8'h37: return 8'h9a;
            8'h38: return 8'h07; 8'h39: return 8'h12; 8'h3a: return 8'h80; 8'h3b: return 8'he2;
            8'h3c: return 8'heb; 8'h3d: return 8'h27; 8'h3e: return 8'hb2; 8'h3f: return 8'h75;
            8'h40: return 8'h09; 8'h41: return 8'h83; 8'h42: return 8'h2c; 8'h43: return 8'h1a;
            8'h44: return 8'h1b; 8'h45: return 8'h6e; 8'h46: return 8'h5a; 8'h47: return 8'ha0;
            8'h48: return 8'h52; 8'h49: return 8'h3b; 8'h4a: return 8'hd6; 8'h4b: return 8'hb3;
            8'h4c: return 8'h29; 8'h4d: return 8'he3; 8'h4e: return 8'h2f; 8'h4f: return 8'h84;
            8'h50: return 8'h53; 8'h51: return 8'hd1; 8'h52: return 8'h00; 8'h53: return 8'hed;
            8'h54: return 8'h20; 8'h55: return 8'hfc; 8'h56: return 8'hb1; 8'h57: return 8'h5b;
            8'h58: return 8'h6a; 8'h59: return 8'hcb; 8'h5a: return 8'hbe; 8'h5b: return 8'h39;
            8'h5c: return 8'h4a; 8'h5d: return 8'h4c; 8'h5e: return 8'h58; 8'h5f: return 8'hcf;
            8'h60: return 8'hd0; 8'h61: return 8'hef; 8'h62: return 8'haa; 8'h63: return 8'hfb;
            8'h64: return 8'h43; 8'h65: return 8'h4d; 8'h66: return 8'h33; 8'h67: return 8'h85;
            8'h68: return 8'h45; 8'h69: return 8'hf9; 8'h6a: return 8'h02; 8'h6b: return 8'h7f;
            8'h6c: return 8'h50; 8'h6d: return 8'h3c; 8'h6e: return 8'h9f; 8'h6f: return 8'ha8;
            8'h70: return 8'h51; 8'h71: return 8'ha3; 8'h72: return 8'h40; 8'h73: return 8'h8f;
            8'h74: return 8'h92; 8'h75: return 8'h9d; 8'h76: return 8'h38; 8'h77: return 8'hf5;
            8'h78: return 8'hbc; 8'h79: return 8'hb6; 8'h7a: return 8'hda; 8'h7b: return 8'h21;
            8'h7c: return 8'h10; 8'h7d: return 8'hff; 8'h7e: return 8'hf3; 8'h7f: return 8'hd2;
            8'h80: return 8'hcd; 8'h81: return 8'h0c; 8'h82: return 8'h13; 8'h83: return 8'hec;
            8'h84: return 8'h5f; 8'h85: return 8'h97; 8'h86: return 8'h44; 8'h87: return 8'h17;
            8'h88: return 8'hc4; 8'h89: return 8'ha7; 8'h8a: return 8'h7e; 8'h8b: return 8'h3d;
            8'h8c: return 8'h64; 8'h8d: return 8'h5d; 8'h8e: return 8'h19; 8'h8f: return 8'h73;
            8'h90: return 8'h60; 8'h91: return 8'h81; 8'h92: return 8'h4f; 8'h93: return 8'hdc;
            8'h94: return 8'h22; 8'h95: return 8'h2a; 8'h96: return 8'h90; 8'h97: return 8'h88;
            8'h98: return 8'h46; 8'h99: return 8'hee; 8'h9a: return 8'hb8; 8'h9b: return 8'h14;
            8'h9c: return 8'hde; 8'h9d: return 8'h5e; 8'h9e: return 8'h0b; 8'h9f: return 8'hdb;
            8'ha0: return 8'he0; 8'ha1: return 8'h32; 8'ha2: return 8'h3a; 8'ha3: return 8'h0a;
            8'ha4: return 8'h49; 8'ha5: return 8'h06; 8'ha6: return 8'h24; 8'ha7: return 8'h5c;
            8'ha8: return 8'hc2; 8'ha9: return 8'hd3; 8'haa: return 8'hac; 8'hab: return 8'h62;
            8'hac: return 8'h91; 8'had: return 8'h95; 8'hae: return 8'he4; 8'haf: return 8'h79;
            8'hb0: return 8'he7; 8'hb1: return 8'hc8; 8'hb2: return 8'h37; 8'hb3: return 8'h6d;
            8'hb4: return 8'h8d; 8'hb5: return 8'hd5; 8'hb6: return 8'h4e; 8'hb7: return 8'ha9;
            8'hb8: return 8'h6c; 8'hb9: return 8'h56; 8'hba: return 8'hf4; 8'hbb: return 8'hea;
            8'hbc: return 8'h65; 8'hbd: return 8'h7a; 8'hbe: return 8'hae; 8'hbf: return 8'h08;
            8'hc0: return 8'hba; 8'hc1: return 8'h78; 8'hc2: return 8'h25; 8'hc3: return 8'h2e;
            8'hc4: return 8'h1c; 8'hc5: return 8'ha6; 8'hc6: return 8'hb4; 8'hc7: return 8'hc6;
            8'hc8: return 8'he8; 8'hc9: return 8'hdd; 8'hca: return 8'h74; 8'hcb: return 8'h1f;
            8'hcc: return 8'h4b; 8'hcd: return 8'hbd; 8'hce: return 8'h8b; 8'hcf: return 8'h8a;
            8'hd0: return 8'h70; 8'hd1: return 8'h3e; 8'hd2: return 8'hb5; 8'hd3: return 8'h66;
            8'hd4: return 8'h48; 8'hd5: return 8'h03; 8'hd6: return 8'hf6; 8'hd7: return 8'h0e;
            8'hd8: return 8'h61; 8'hd9: return 8'h35; 8'hda: return 8'h57; 8'hdb: return 8'hb9;
            8'hdc: return 8'h86; 8'hdd: return 8'hc1; 8'hde: return 8'h1d; 8'hdf: return 8'h9e;
            8'he0: return 8'he1; 8'he1: return 8'hf8; 8'he2: return 8'h98; 8'he3: return 8'h11;
            8'he4: return 8'h69; 8'he5: return 8'hd9; 8'he6: return 8'h8e; 8'he7: return 8'h94;
            8'he8: return 8'h9b; 8'he9: return 8'h1e; 8'hea: return 8'h87; 8'heb: return 8'he9;
            8'hec: return 8'hce; 8'hed: return 8'h55; 8'hee: return 8'h28; 8'hef: return 8'hdf;
            8'hf0: return 8'h8c; 8'hf1: return 8'ha1; 8'hf2: return 8'h89; 8'hf3: return 8'h0d;
            8'hf4: return 8'hbf; 8'hf5: return 8'he6; 8'hf6: return 8'h42; 8'hf7: return 8'h68;
            8'hf8: return 8'h41; 8'hf9: return 8'h99; 8'hfa: return 8'h2d; 8'hfb: return 8'h0f;
            8'hfc: return 8'hb0; 8'hfd: return 8'h54; 8'hfe: return 8'hbb; 8'hff: return 8'h16;
            default: return 8'h00;
        endcase
    endfunction

    function automatic logic [7:0] rcon_val(input logic [3:0] rnd);
        case (rnd)
            4'd1: return 8'h01; 4'd2: return 8'h02; 4'd3: return 8'h04; 4'd4: return 8'h08;
            4'd5: return 8'h10; 4'd6: return 8'h20; 4'd7: return 8'h40; 4'd8: return 8'h80;
            4'd9: return 8'h1B; 4'd10: return 8'h36;
            default: return 8'h00;
        endcase
    endfunction

    // Byte indexing helper: byte 0 is MSB [127:120], byte 15 is LSB [7:0]
    function automatic logic [7:0] get_byte(input logic [127:0] v, input int idx);
        return v[127 - idx*8 -: 8];
    endfunction

    function automatic logic [127:0] sub_bytes_fn(input logic [127:0] s);
        logic [127:0] out;
        for (int i = 0; i < 16; i++) begin
            out[127 - i*8 -: 8] = sbox_lut(get_byte(s, i));
        end
        return out;
    endfunction

    function automatic logic [127:0] shift_rows_fn(input logic [127:0] s);
        logic [127:0] out;
        out[127 -: 8] = get_byte(s, 0);  out[119 -: 8] = get_byte(s, 5);
        out[111 -: 8] = get_byte(s, 10); out[103 -: 8] = get_byte(s, 15);
        out[95  -: 8] = get_byte(s, 4);  out[87  -: 8] = get_byte(s, 9);
        out[79  -: 8] = get_byte(s, 14); out[71  -: 8] = get_byte(s, 3);
        out[63  -: 8] = get_byte(s, 8);  out[55  -: 8] = get_byte(s, 13);
        out[47  -: 8] = get_byte(s, 2);  out[39  -: 8] = get_byte(s, 7);
        out[31  -: 8] = get_byte(s, 12); out[23  -: 8] = get_byte(s, 1);
        out[15  -: 8] = get_byte(s, 6);  out[7   -: 8] = get_byte(s, 11);
        return out;
    endfunction

    function automatic logic [127:0] mix_columns_fn(input logic [127:0] s);
        logic [127:0] out;
        logic [7:0] a0, a1, a2, a3;
        for (int c = 0; c < 4; c++) begin
            a0 = get_byte(s, c*4 + 0);
            a1 = get_byte(s, c*4 + 1);
            a2 = get_byte(s, c*4 + 2);
            a3 = get_byte(s, c*4 + 3);
            out[127 - (c*4+0)*8 -: 8] = gf_mul(8'h02, a0) ^ gf_mul(8'h03, a1) ^ a2 ^ a3;
            out[127 - (c*4+1)*8 -: 8] = a0 ^ gf_mul(8'h02, a1) ^ gf_mul(8'h03, a2) ^ a3;
            out[127 - (c*4+2)*8 -: 8] = a0 ^ a1 ^ gf_mul(8'h02, a2) ^ gf_mul(8'h03, a3);
            out[127 - (c*4+3)*8 -: 8] = gf_mul(8'h03, a0) ^ a1 ^ a2 ^ gf_mul(8'h02, a3);
        end
        return out;
    endfunction

    function automatic logic [127:0] next_round_key(input logic [127:0] prev_rk, input logic [3:0] rnd);
        logic [31:0] w0, w1, w2, w3, nw0, nw1, nw2, nw3;
        logic [31:0] rot_sub;
        w0 = prev_rk[127:96];
        w1 = prev_rk[95:64];
        w2 = prev_rk[63:32];
        w3 = prev_rk[31:0];
        rot_sub = {sbox_lut(w3[23:16]), sbox_lut(w3[15:8]), sbox_lut(w3[7:0]), sbox_lut(w3[31:24])};
        nw0 = w0 ^ rot_sub ^ {rcon_val(rnd) ^ CUSTOM_TWEAK, 24'h000000};
        nw1 = w1 ^ nw0;
        nw2 = w2 ^ nw1;
        nw3 = w3 ^ nw2;
        return {nw0, nw1, nw2, nw3};
    endfunction

    typedef enum logic [1:0] {
        ST_IDLE   = 2'd0,
        ST_ROUNDS = 2'd1,
        ST_DONE   = 2'd2
    } fsm_state_t;

    fsm_state_t  fsm_state;
    logic [3:0]  round_cnt;
    logic [127:0] state_reg, rk_reg;

    logic [127:0] sb_out, sr_out, mc_out, next_rk, round_in;
    assign sb_out  = sub_bytes_fn(state_reg);
    assign sr_out  = shift_rows_fn(sb_out);
    assign mc_out  = (round_cnt == 4'd10) ? sr_out : mix_columns_fn(sr_out);
    assign next_rk = next_round_key(rk_reg, round_cnt);
    assign round_in = mc_out ^ next_rk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state  <= ST_IDLE;
            round_cnt  <= 4'd0;
            state_reg  <= 128'd0;
            rk_reg     <= 128'd0;
            ciphertext <= 128'd0;
            done       <= 1'b0;
        end else begin
            case (fsm_state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state_reg <= plaintext ^ key;
                        rk_reg    <= key;
                        round_cnt <= 4'd1;
                        fsm_state <= ST_ROUNDS;
                    end
                end
                ST_ROUNDS: begin
                    state_reg <= round_in;
                    rk_reg    <= next_rk;
                    if (round_cnt == 4'd10) begin
                        ciphertext <= round_in;
                        done       <= 1'b1;
                        fsm_state  <= ST_DONE;
                    end else begin
                        round_cnt <= round_cnt + 4'd1;
                    end
                end
                ST_DONE: begin
                    done      <= 1'b0;
                    fsm_state <= ST_IDLE;
                end
                default: fsm_state <= ST_IDLE;
            endcase
        end
    end

endmodule
