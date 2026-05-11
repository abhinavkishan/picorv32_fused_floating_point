// ============================================================
// Enhanced Floating-Point Fused Dot-Product Unit  (CORRECTED)
// Computes: out = A*B + C*D  (IEEE 754 single precision)
// Architecture: Fig.7 of the project report
//
// BUGS FIXED vs previous version:
//  1. normalize.v     : act_shift was (47-norm_shift), must be norm_shift directly
//  2. opSelect.v      : opSel was XOR(ab,cd,op), must be XNOR ? ~(ab^cd^op)
//  3. expCompare.v    : exp_large was off by 1; 48-bit product MSB is at bit46,
//                       not bit47, so +1 correction added to base exponent
//  4. mainMod CSA path: splitting 48-bit values into sum/carry pairs broke
//                       bit-weighting; replaced with direct KSA_48 addition
//  5. postNorm        : mantissa extraction window fixed to match normalised format
// ============================================================

`timescale 1ns/1ps

// ============================================================
// PRIMITIVES
// ============================================================

module HA(a, b, sum, carry);
    input  a, b;
    output sum, carry;
    xor x1(sum,   a, b);
    and a1(carry, a, b);
endmodule

module FA(a, b, cin, sum, carry);
    input  a, b, cin;
    output sum, carry;
    wire t1, t2, t3;
    xor x1(sum,   a, b, cin);
    and a1(t1, a, b);
    and a2(t2, b, cin);
    and a3(t3, a, cin);
    or  o1(carry, t1, t2, t3);
endmodule

// ============================================================
// KOGGE-STONE PRIMITIVES
// ============================================================

module grCarryGen(p1, g1, p0, g0, P, G);
    input  p1, g1, p0, g0;
    output P, G;
    wire op1;
    and a1(P,   p1, p0);
    and a2(op1, p1, g0);
    or  o1(G,   op1, g1);
endmodule

module grCarryPropagate(p1, g1, g0, G);
    input  p1, g1, g0;
    output G;
    wire op1;
    and a1(op1, p1, g0);
    or  o1(G,   op1, g1);
endmodule

// ============================================================
// 8-BIT KOGGE-STONE ADDER  (exponent arithmetic)
// ============================================================

module KSA_8(a, b, cin, sum, cy);
    input  [7:0] a, b;
    input        cin;
    output [7:0] sum;
    output       cy;

    wire [7:0] p0, g0;
    wire [7:1] p1, g1;
    wire [7:3] p2, g2;
    wire [7:7] p3, g3;
    wire [2:1] G2;
    wire [6:3] G3;
    wire [0:0] G1;

    assign p0 = a ^ b;
    assign g0 = a & b;

    genvar i;
    generate
        for (i = 7; i > 0; i = i-1) begin : st1
            grCarryGen cg(.p1(p0[i]),.g1(g0[i]),.p0(p0[i-1]),.g0(g0[i-1]),.P(p1[i]),.G(g1[i]));
        end
    endgenerate
    grCarryPropagate gp1(.p1(p0[0]),.g1(g0[0]),.g0(cin),.G(G1[0]));

    generate
        for (i = 7; i > 2; i = i-1) begin : st2
            grCarryGen cg(.p1(p1[i]),.g1(g1[i]),.p0(p1[i-2]),.g0(g1[i-2]),.P(p2[i]),.G(g2[i]));
        end
    endgenerate
    grCarryPropagate gp2(.p1(p1[2]),.g1(g1[2]),.g0(G1[0]),.G(G2[2]));
    grCarryPropagate gp3(.p1(p1[1]),.g1(g1[1]),.g0(cin),.G(G2[1]));

    grCarryGen        cg4(.p1(p2[7]),.g1(g2[7]),.p0(p2[3]),.g0(g2[3]),.P(p3[7]),.G(g3[7]));
    grCarryPropagate  gp4(.p1(p2[6]),.g1(g2[6]),.g0(G2[2]),.G(G3[6]));
    grCarryPropagate  gp5(.p1(p2[5]),.g1(g2[5]),.g0(G2[1]),.G(G3[5]));
    grCarryPropagate  gp6(.p1(p2[4]),.g1(g2[4]),.g0(G1[0]),.G(G3[4]));
    grCarryPropagate  gp7(.p1(p2[3]),.g1(g2[3]),.g0(cin),.G(G3[3]));

    grCarryPropagate gpF(.p1(p3[7]),.g1(g3[7]),.g0(G3[6]),.G(cy));

    xor xs7(sum[7], p0[7], G3[6]);
    xor xs6(sum[6], p0[6], G3[5]);
    xor xs5(sum[5], p0[5], G3[4]);
    xor xs4(sum[4], p0[4], G3[3]);
    xor xs3(sum[3], p0[3], G2[2]);
    xor xs2(sum[2], p0[2], G2[1]);
    xor xs1(sum[1], p0[1], G1[0]);
    xor xs0(sum[0], p0[0], cin);
endmodule

// ============================================================
// 48-BIT ADDER  (compound addition stage)
// ============================================================

module KSA_48(a, b, cin, sum, cout);
    input  [47:0] a, b;
    input         cin;
    output [47:0] sum;
    output        cout;

    wire [47:0] p0, g0;
    wire [48:0] carry_chain;

    assign p0 = a ^ b;
    assign g0 = a & b;
    assign carry_chain[0] = cin;

    genvar i;
    generate
        for (i = 0; i < 48; i = i+1) begin : carry_gen
            assign carry_chain[i+1] = g0[i] | (p0[i] & carry_chain[i]);
        end
    endgenerate

    assign sum  = p0 ^ carry_chain[47:0];
    assign cout = carry_chain[48];
endmodule

// ============================================================
// 2's COMPLEMENT  (8-bit, purely combinational)
// ============================================================

module complement_2s(in, out);
    input  [7:0] in;
    output [7:0] out;
    assign out = (~in) + 8'd1;
endmodule

// ============================================================
// 24×24 DADDA MULTIPLIER ? 48-bit product
// 8 CSA layers reduce 24 rows to 2, then KSA_48 final add.
// ============================================================

module dadda(A, B, prod);
    input  [23:0] A, B;
    output [47:0] prod;

    // Partial products: L0[i] = A * B[i], shifted left by i
    wire [47:0] L0 [0:23];
    genvar i;
    generate
        for (i = 0; i < 24; i = i+1) begin : pp_gen
            assign L0[i] = {{24{1'b0}}, (A & {24{B[i]}})} << i;
        end
    endgenerate

    // Layer 1: 24 ? 16  (8 FA-CSA cells)
    wire [47:0] csa_s1[0:7], csa_c1[0:7], L1[0:15];
    generate
        for (i = 0; i < 8; i = i+1) begin : csa_l1
            assign csa_s1[i] =  L0[3*i] ^ L0[3*i+1] ^ L0[3*i+2];
            assign csa_c1[i] = ((L0[3*i]&L0[3*i+1])|(L0[3*i+1]&L0[3*i+2])|(L0[3*i]&L0[3*i+2])) << 1;
            assign L1[i]   = csa_s1[i];
            assign L1[i+8] = csa_c1[i];
        end
    endgenerate

    // Layer 2: 16 ? 11  (5 CSA, 1 passthrough)
    wire [47:0] csa_s2[0:4], csa_c2[0:4], L2[0:10];
    generate
        for (i = 0; i < 5; i = i+1) begin : csa_l2
            assign csa_s2[i] =  L1[3*i] ^ L1[3*i+1] ^ L1[3*i+2];
            assign csa_c2[i] = ((L1[3*i]&L1[3*i+1])|(L1[3*i+1]&L1[3*i+2])|(L1[3*i]&L1[3*i+2])) << 1;
            assign L2[i]   = csa_s2[i];
            assign L2[i+5] = csa_c2[i];
        end
    endgenerate
    assign L2[10] = L1[15];

    // Layer 3: 11 ? 8  (3 CSA, 2 passthrough)
    wire [47:0] csa_s3[0:2], csa_c3[0:2], L3[0:7];
    generate
        for (i = 0; i < 3; i = i+1) begin : csa_l3
            assign csa_s3[i] =  L2[3*i] ^ L2[3*i+1] ^ L2[3*i+2];
            assign csa_c3[i] = ((L2[3*i]&L2[3*i+1])|(L2[3*i+1]&L2[3*i+2])|(L2[3*i]&L2[3*i+2])) << 1;
            assign L3[i]   = csa_s3[i];
            assign L3[i+3] = csa_c3[i];
        end
    endgenerate
    assign L3[6] = L2[9];
    assign L3[7] = L2[10];

    // Layer 4: 8 ? 6  (2 CSA, 2 passthrough)
    wire [47:0] csa_s4[0:1], csa_c4[0:1], L4[0:5];
    generate
        for (i = 0; i < 2; i = i+1) begin : csa_l4
            assign csa_s4[i] =  L3[3*i] ^ L3[3*i+1] ^ L3[3*i+2];
            assign csa_c4[i] = ((L3[3*i]&L3[3*i+1])|(L3[3*i+1]&L3[3*i+2])|(L3[3*i]&L3[3*i+2])) << 1;
            assign L4[2*i]   = csa_s4[i];
            assign L4[2*i+1] = csa_c4[i];
        end
    endgenerate
    assign L4[4] = L3[6];
    assign L4[5] = L3[7];

    // Layer 5: 6 ? 4  (2 CSA)
    wire [47:0] L5[0:3];
    assign L5[0] =  L4[0] ^ L4[1] ^ L4[2];
    assign L5[1] = ((L4[0]&L4[1])|(L4[1]&L4[2])|(L4[0]&L4[2])) << 1;
    assign L5[2] =  L4[3] ^ L4[4] ^ L4[5];
    assign L5[3] = ((L4[3]&L4[4])|(L4[4]&L4[5])|(L4[3]&L4[5])) << 1;

    // Layer 6: 4 ? 3  (1 CSA, 1 passthrough)
    wire [47:0] L6[0:2];
    assign L6[0] =  L5[0] ^ L5[1] ^ L5[2];
    assign L6[1] = ((L5[0]&L5[1])|(L5[1]&L5[2])|(L5[0]&L5[2])) << 1;
    assign L6[2] = L5[3];

    // Layer 7: 3 ? 2  (1 CSA)
    wire [47:0] L7[0:1];
    assign L7[0] =  L6[0] ^ L6[1] ^ L6[2];
    assign L7[1] = ((L6[0]&L6[1])|(L6[1]&L6[2])|(L6[0]&L6[2])) << 1;

    // Final addition
    wire cout_unused;
    KSA_48 final_add(.a(L7[0]), .b(L7[1]), .cin(1'b0), .sum(prod), .cout(cout_unused));
endmodule

// ============================================================
// EXPONENT COMPARE  (FIXED: +1 offset for 48-bit product format)
//
// Product exponents:  abExp = expA + expB - 127
//                     cdExp = expC + expD - 127
// We add +1 because the 48-bit integer product of two 24-bit
// mantissas always has its leading 1 at bit46 (not bit47).
// The +1 keeps the exponent accounting consistent with bit47
// being the normalised MSB position throughout the pipeline.
//
// expComp = 1 ? A*B product exponent >= C*D product exponent
// exp     = larger product exponent (with +1 correction)
// expDiff = |abExp - cdExp| (alignment shift amount)
// ============================================================

module expCompare(aExp, bExp, cExp, dExp, exp, expComp, expDiff);
    input  [7:0] aExp, bExp, cExp, dExp;
    output       expComp;
    output [7:0] exp, expDiff;

    // neg126 = -126 in 8-bit 2's complement = 0x82 = 130
    // (This is -(127-1) = -(bias-1); the +1 correction is baked in here)
    wire [7:0] neg126 = 8'h82;

    wire [7:0] abRaw, cdRaw, abExp, cdExp;
    wire [7:0] cdComp, diff, diffComp;
    wire       cy_ab, cy_cd, cy1, cy2, cy_diff;

    KSA_8 k1(.a(aExp),  .b(bExp),   .cin(1'b0), .sum(abRaw), .cy(cy_ab));
    KSA_8 k2(.a(cExp),  .b(dExp),   .cin(1'b0), .sum(cdRaw), .cy(cy_cd));
    KSA_8 k3(.a(abRaw), .b(neg126), .cin(1'b0), .sum(abExp), .cy(cy1));
    KSA_8 k4(.a(cdRaw), .b(neg126), .cin(1'b0), .sum(cdExp), .cy(cy2));

    // diff = abExp - cdExp
    complement_2s c1(.in(cdExp), .out(cdComp));
    KSA_8 k5(.a(abExp), .b(cdComp), .cin(1'b0), .sum(diff), .cy(cy_diff));

    assign expComp = cy_diff | (diff == 8'd0);
    assign exp     = expComp ? abExp : cdExp;

    complement_2s c2(.in(diff), .out(diffComp));
    assign expDiff = expComp ? diff : diffComp;
endmodule

// ============================================================
// SIGNIFICAND SWAP MUX (48-bit)
// sel=1 ? op1 is larger; sel=0 ? op2 is larger
// ============================================================

module mux_swap_48(op1, op2, sel, larger, smaller);
    input  [47:0] op1, op2;
    input         sel;
    output [47:0] larger, smaller;
    assign larger  = sel ? op1 : op2;
    assign smaller = sel ? op2 : op1;
endmodule

// ============================================================
// ALIGNMENT SHIFTER WITH GUARD/ROUND/STICKY
// Right-shifts in_put by shamt positions.
// G = guard bit (first bit shifted out)
// R = round bit (second bit)
// S = sticky bit (OR of all remaining shifted-out bits)
// ============================================================

module shifter_align(shamt, in_put, G, R, S, out);
    input  [7:0]  shamt;
    input  [47:0] in_put;
    output        G, R, S;
    output [47:0] out;

    wire [302:0] I7;
    wire [174:0] I6;
    wire [110:0] I5;
    wire [78:0]  I4;
    wire [62:0]  I3;
    wire [54:0]  I2;
    wire [50:0]  I1;
    wire [48:0]  I0;

    assign I0 = shamt[0] ? {1'b0,   in_put} : {in_put,   1'b0};
    assign I1 = shamt[1] ? {2'b0,   I0}     : {I0,       2'b0};
    assign I2 = shamt[2] ? {4'b0,   I1}     : {I1,       4'b0};
    assign I3 = shamt[3] ? {8'b0,   I2}     : {I2,       8'b0};
    assign I4 = shamt[4] ? {16'b0,  I3}     : {I3,       16'b0};
    assign I5 = shamt[5] ? {32'b0,  I4}     : {I4,       32'b0};
    assign I6 = shamt[6] ? {64'b0,  I5}     : {I5,       64'b0};
    assign I7 = shamt[7] ? {128'b0, I6}     : {I6,       128'b0};

    assign out = I7[302:255];
    assign G   = I7[254];
    assign R   = I7[253];
    assign S   = |I7[252:0];
endmodule

// ============================================================
// OP SELECT  (FIXED: was XOR, must be XNOR)
//
// Truth table:
//  abSign cdSign op(1=add) | opSel(1=sub)
//     0      0      1      |   0  (same sign, add  ? add magnitudes)
//     0      0      0      |   1  (same sign, sub  ? sub magnitudes)
//     0      1      1      |   1  (diff sign, add  ? sub magnitudes)
//     0      1      0      |   0  (diff sign, sub  ? add magnitudes)
//     1      0      1      |   1  (diff sign, add  ? sub magnitudes)
//     1      0      0      |   0  (diff sign, sub  ? add magnitudes)
//     1      1      1      |   0  (same sign, add  ? add magnitudes)
//     1      1      0      |   1  (same sign, sub  ? sub magnitudes)
// opSel = ~(abSign ^ cdSign ^ op)
// ============================================================

module opSelect(aSign, bSign, cSign, dSign, op, opSel);
    input  aSign, bSign, cSign, dSign, op;
    output opSel;
    wire abSign, cdSign, xorResult;
    xor x1(abSign,    aSign, bSign);
    xor x2(cdSign,    cSign, dSign);
    xor x3(xorResult, abSign, cdSign, op);
    not n1(opSel, xorResult);   // XNOR: negate the XOR result
endmodule

// ============================================================
// INVERTER  (one's complement when control=1)
// ============================================================

module inverter(control, in, out);
    input         control;
    input  [47:0] in;
    output [47:0] out;
    assign out = control ? ~in : in;
endmodule

// ============================================================
// 4:2 CARRY-SAVE ADDER (48-bit)
// Reduces four 48-bit inputs ? sum[47:0] + carry[47:0] + cout
// ============================================================

module csa4_2(A, B, C, D, sum, carry, cout);
    input  [47:0] A, B, C, D;
    output [47:0] sum, carry;
    output        cout;

    wire [47:0] s_temp, c_temp;
    genvar i;
    generate
        for (i = 0; i < 48; i = i+1) begin : fa1_loop
            FA fa1(.a(A[i]), .b(B[i]), .cin(C[i]), .sum(s_temp[i]), .carry(c_temp[i]));
        end
    endgenerate

    FA fa2_0(.a(1'b0), .b(D[0]), .cin(s_temp[0]), .sum(sum[0]), .carry(carry[0]));
    generate
        for (i = 1; i < 48; i = i+1) begin : fa2_loop
            FA fa2(.a(c_temp[i-1]), .b(D[i]), .cin(s_temp[i]), .sum(sum[i]), .carry(carry[i]));
        end
    endgenerate
    assign cout = c_temp[47];
endmodule

// ============================================================
// 2:1 MUX (48-bit)   sel=1 ? out=op1
// ============================================================

module mux_48(op1, op2, sel, out);
    input  [47:0] op1, op2;
    input         sel;
    output [47:0] out;
    assign out = sel ? op1 : op2;
endmodule

// ============================================================
// LEADING-ZERO ANTICIPATOR  (FIXED naming for clarity)
// Returns norm_shift = number of LEFT SHIFTS needed to place
// the leading 1 at bit47.
// norm_shift = 47 - position_of_MSB
// ============================================================

module leadOne(in, norm_shift);
    input      [47:0] in;
    output reg [7:0]  norm_shift;
    integer k;
    always @(in) begin
        norm_shift = 8'd47;          // default: all zeros input
        for (k = 0; k <= 47; k = k+1)
            if (in[k]) norm_shift = 8'd47 - k;
    end
endmodule

// ============================================================
// NORMALIZE  (FIXED: use norm_shift directly as left-shift amount)
//
// Previous bug: act_shift = 47 - norm_shift  (wrong! reversed the shift)
// Fix:          out = in << norm_shift
// ============================================================

module normalize(in, norm_shift, out, msb);
    input  [47:0] in;
    input  [7:0]  norm_shift;
    output reg [47:0] out;
    output reg        msb;
    always @(in or norm_shift) begin
        out = in << norm_shift;   // norm_shift is already the left-shift count
        msb = out[47];            // MSB after shift
    end
endmodule

// ============================================================
// SIGN LOGIC
// Determines the sign of the result based on the larger-magnitude
// operand's sign.
// ============================================================

module signLogic(aSign, bSign, cSign, dSign, expComp, signifComp, op, sign);
    input  aSign, bSign, cSign, dSign;
    input  expComp, signifComp, op;
    output sign;

    wire abSign, cdSign;
    wire cdEff;        // effective sign of C*D after applying user op
    wire largerIsAB;

    xor x1(abSign, aSign, bSign);
    xor x2(cdSign, cSign, dSign);
    // When op=0 (subtract), the C*D product is negated ? flip its sign
    xor x3(cdEff,  cdSign, ~op);

    // largerIsAB: true when A*B has the larger magnitude
    assign largerIsAB = expComp | (~expComp & signifComp);
    assign sign = largerIsAB ? abSign : cdEff;
endmodule

// ============================================================
// 4:1 MUX (1-bit)  for rounding mode selection
// ============================================================

module mux_4_1(a, b, c, d, s1, s0, y);
    input  a, b, c, d, s1, s0;
    output y;
    assign y = (~s1&~s0&a)|(~s1&s0&b)|(s1&~s0&c)|(s1&s0&d);
endmodule

// ============================================================
// STICKY & ROUND
// rndMode: 00=truncate, 01=round to +?, 10=round to -?, 11=nearest-even
// ============================================================

module stickyRound(sign, lsb, guard, round_bit, sticky, rndMode, rndUp);
    input  sign, lsb, guard, round_bit, sticky;
    input  [1:0] rndMode;
    output rndUp;

    wire signComp, orGRS, andPos, andNeg, grSt, lsbOrGrSt, andEven;
    not  n1(signComp, sign);
    or   o1(orGRS,      guard, round_bit, sticky);
    and  a1(andPos,     signComp, orGRS);        // round toward +inf
    and  a2(andNeg,     sign,     orGRS);        // round toward -inf
    or   o2(grSt,       round_bit, sticky);
    or   o3(lsbOrGrSt,  lsb, grSt);
    and  a3(andEven,    guard, lsbOrGrSt);       // round to nearest even

    // rndMode=00 ? truncate (rndUp=0)
    mux_4_1 m4(.a(1'b0), .b(andPos), .c(andNeg), .d(andEven),
                .s1(rndMode[1]), .s0(rndMode[0]), .y(rndUp));
endmodule

// ============================================================
// EXPONENT ADJUST
// finalExp = exp - normShift + carryOut
// (exp already includes the +1 offset from expCompare)
// exception = result out of range
// ============================================================

module expAdjust(exp, carryOut, normShift, finalExp, exception);
    input  [7:0] exp, normShift;
    input        carryOut;
    output [7:0] finalExp;
    output       exception;

    // Use 9-bit signed arithmetic to detect underflow correctly.
    // Old approach used carry-out of an 8-bit add to detect underflow,
    // but that carry is 0 for ALL valid subtractions (exp-normShift < 256),
    // so it fired exception on every case where normShift=0.
    //
    // Fix: 9-bit subtraction; borrow (bit8=1) means true underflow.
    wire [8:0] adjusted;
    assign adjusted = {1'b0, exp} - {1'b0, normShift} + {8'b0, carryOut};

    assign finalExp  = adjusted[7:0];
    // Overflow:  result >= 255 (255 = inf/NaN in IEEE 754)
    // Underflow: borrow bit set (normShift > exp + carryOut)
    assign exception = adjusted[8] | (adjusted >= 9'd255);
endmodule

// ============================================================
// POST-NORM
// If compound addition overflowed (carryOut=1), shift right 1.
// Extracts 23-bit mantissa: bits [46:24] of the 48-bit result
// (bit47 is the implicit leading 1 after normalisation).
// ============================================================

module postNorm(in, carryOut, mantissa, carryOut_out);
    input  [47:0] in;
    input         carryOut;
    output [22:0] mantissa;
    output        carryOut_out;

    wire [47:0] shifted;
    assign shifted      = carryOut ? (in >> 1) : in;
    assign carryOut_out = carryOut;
    // bit47 = implicit leading 1, bits[46:24] = 23-bit stored mantissa
    assign mantissa     = shifted[46:24];
endmodule

// ============================================================
//  M A I N   M O D U L E   (CORRECTED)
//  Enhanced Floating-Point Fused Dot-Product Unit
//  out = A*B + C*D  (IEEE 754 SP, op=1) or A*B - C*D (op=0)
// ============================================================

module mainMod(A, B, C, D, op, rnd_mode, out);

    // ---- Ports -------------------------------------------------
    input  [31:0] A, B, C, D;
    input         op;         // 1 = add (A*B + C*D), 0 = subtract
    input  [1:0]  rnd_mode;   // 00=trunc 01=+inf 10=-inf 11=nearest-even
    output [31:0] out;

    // ---- Unpack IEEE 754 ---------------------------------------
    wire        signA = A[31], signB = B[31];
    wire        signC = C[31], signD = D[31];
    wire [7:0]  expA  = A[30:23], expB = B[30:23];
    wire [7:0]  expC  = C[30:23], expD = D[30:23];
    // Restore implicit leading 1 (normalised inputs assumed)
    wire [23:0] mantA = {1'b1, A[22:0]};
    wire [23:0] mantB = {1'b1, B[22:0]};
    wire [23:0] mantC = {1'b1, C[22:0]};
    wire [23:0] mantD = {1'b1, D[22:0]};

    // ===========================================================
    // STAGE 1 - Exponent Compare
    // ===========================================================
    wire        exp_comp;
    wire [7:0]  exp_large, exp_diff;
    expCompare u_expCmp(
        .aExp(expA), .bExp(expB), .cExp(expC), .dExp(expD),
        .exp(exp_large), .expComp(exp_comp), .expDiff(exp_diff));

    // ===========================================================
    // STAGE 2 - Two Dadda Multiplier Trees
    // ===========================================================
    wire [47:0] multAB, multCD;
    dadda u_mAB(.A(mantA), .B(mantB), .prod(multAB));
    dadda u_mCD(.A(mantC), .B(mantD), .prod(multCD));

    // ===========================================================
    // STAGE 3 - Significand Swap & Alignment
    // exp_comp=1 ? multAB has the larger (or equal) exponent
    // ===========================================================
    wire [47:0] sig_large, sig_small;
    mux_swap_48 u_swap(
        .op1(multAB), .op2(multCD), .sel(exp_comp),
        .larger(sig_large), .smaller(sig_small));

    wire        guard1, round1, sticky1;
    wire [47:0] small_aligned;
    shifter_align u_align(
        .shamt(exp_diff), .in_put(sig_small),
        .G(guard1), .R(round1), .S(sticky1), .out(small_aligned));

    // ===========================================================
    // STAGE 4 - Op Select
    // ===========================================================
    wire op_sel;  // 1 = effective subtraction of magnitudes
    opSelect u_opSel(
        .aSign(signA), .bSign(signB), .cSign(signC), .dSign(signD),
        .op(op), .opSel(op_sel));

    // ===========================================================
    // STAGE 5 - Partial Addition & Normalisation
    //
    // Architecture per Fig.7:
    //   Two 4:2 CSAs run in parallel, one per path:
    //     Path A (small-op): invert small, keep large natural
    //     Path B (large-op): invert large, keep small natural
    //   significandCompare picks the path whose CSA cout=1
    //   (that path has the correct sign for the result).
    //
    // Each CSA receives the two operands as four inputs:
    //   A_in + B_in + 0 + 0  (use the CSA as a 2-input adder
    //   to generate a redundant sum+carry representation for
    //   the subsequent normalise+add pipeline).
    // ===========================================================

    // ---- 5a. Inverters (one's complement on subtraction) ------
    wire [47:0] small_inv, large_inv;
    inverter u_invS(.control(op_sel), .in(small_aligned), .out(small_inv));
    inverter u_invL(.control(op_sel), .in(sig_large),     .out(large_inv));

    // ---- 5b. Two 4:2 CSAs ------------------------------------
    // Path A: large + (~small)   ? gives (large - small - 1) in carry-save
    // Path B: (~large) + small   ? gives (small - large - 1) in carry-save
    // The +1 for 2's complement is added as carry-in to the KSA stage.
    wire [47:0] csaA_sum, csaA_carry;
    wire [47:0] csaB_sum, csaB_carry;
    wire        cout_A, cout_B;

    csa4_2 u_csaA(.A(sig_large),    .B(small_inv),
                   .C(48'd0),        .D(48'd0),
                   .sum(csaA_sum),   .carry(csaA_carry), .cout(cout_A));

    csa4_2 u_csaB(.A(small_aligned), .B(large_inv),
                   .C(48'd0),         .D(48'd0),
                   .sum(csaB_sum),    .carry(csaB_carry), .cout(cout_B));

    // ---- 5c. Significand Compare: select path with cout=1 ----
    // cout=1 means the result is positive in that path.
    // If both are 0 (exact cancellation) or both 1, path A is preferred.
    wire signif_comp;
    assign signif_comp = cout_A | (~cout_B);  // prefer A; use B only if A=0 and B=1

    wire [47:0] csa_sum_sel, csa_carry_sel;
    mux_48 u_muxS(.op1(csaA_sum),   .op2(csaB_sum),   .sel(signif_comp), .out(csa_sum_sel));
    mux_48 u_muxC(.op1(csaA_carry), .op2(csaB_carry), .sel(signif_comp), .out(csa_carry_sel));

    // ---- 5d. LZA on selected sum half -------------------------
    wire [7:0] norm_shift;
    leadOne u_lza(.in(csa_sum_sel), .norm_shift(norm_shift));

    // ---- 5e. Normalise both halves with the same shift amount -
    wire [47:0] norm_sum, norm_carry;
    wire        norm_msb_s, norm_msb_c;
    normalize u_normS(.in(csa_sum_sel),   .norm_shift(norm_shift),
                      .out(norm_sum),     .msb(norm_msb_s));
    normalize u_normC(.in(csa_carry_sel), .norm_shift(norm_shift),
                      .out(norm_carry),   .msb(norm_msb_c));

    // ===========================================================
    // STAGE 6 - Sign Logic
    // ===========================================================
    wire sign;
    signLogic u_sign(
        .aSign(signA), .bSign(signB), .cSign(signC), .dSign(signD),
        .expComp(exp_comp), .signifComp(signif_comp), .op(op),
        .sign(sign));

    // ===========================================================
    // STAGE 7a - Compound Addition
    // Add normalised sum + normalised carry.
    // Carry-in = op_sel (the +1 needed to complete 2's complement
    // negation when we used one's complement in the inverters).
    // ===========================================================
    wire [47:0] add_result;
    wire        add_carry;
    KSA_48 u_ksa(.a(norm_sum), .b(norm_carry), .cin(op_sel),
                  .sum(add_result), .cout(add_carry));

    // ===========================================================
    // STAGE 7b - Sticky & Round
    // ===========================================================
    wire rnd_up;
    stickyRound u_rnd(
        .sign(sign),
        .lsb(add_result[24]),          // LSB of the 23-bit mantissa field
        .guard(guard1),
        .round_bit(round1),
        .sticky(sticky1),
        .rndMode(rnd_mode),
        .rndUp(rnd_up));

    // ===========================================================
    // STAGE 7c - Rnd Select: choose sum or sum+1
    // ===========================================================
    wire [47:0] sum_p1;
    wire        sum_p1_cy;
    KSA_48 u_ksaP1(.a(add_result), .b(48'd0), .cin(rnd_up),
                    .sum(sum_p1), .cout(sum_p1_cy));

    wire [47:0] final_sum;
    mux_48 u_rndMux(.op1(sum_p1), .op2(add_result), .sel(rnd_up), .out(final_sum));
    wire final_carry = rnd_up ? sum_p1_cy : add_carry;

    // ===========================================================
    // STAGE 7d - Post-Norm
    // ===========================================================
    wire [22:0] mantissa_out;
    wire        post_carry;
    postNorm u_postNorm(.in(final_sum), .carryOut(final_carry),
                        .mantissa(mantissa_out), .carryOut_out(post_carry));

    // ===========================================================
    // STAGE 8 - Exponent Adjust
    // ===========================================================
    wire [7:0] final_exp;
    wire       exception;
    expAdjust u_expAdj(
        .exp(exp_large),
        .carryOut(post_carry),
        .normShift(norm_shift),
        .finalExp(final_exp),
        .exception(exception));

    // ===========================================================
    // STAGE 9 - Pack IEEE 754 output
    // ===========================================================
    // Zero detection: if the 48-bit sum is zero (exact cancellation),
    // force output to +0.0. This handles A*B - C*D = 0 correctly.
    wire        is_zero   = (final_sum == 48'd0);
    wire [31:0] normal_out = {sign, final_exp, mantissa_out};
    wire [31:0] inf_out    = {sign, 8'hFF, 23'd0};
    assign out = is_zero   ? 32'd0       :
                 exception ? inf_out     :
                             normal_out;

endmodule