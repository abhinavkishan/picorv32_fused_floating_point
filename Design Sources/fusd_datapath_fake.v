`timescale 1ns / 1ps

module fused_fp_datapath(

    input  [31:0] a,
    input  [31:0] b,
    input  [31:0] c,

    output [31:0] result
);

    // ------------------------------------------------
    // Extract fields
    // ------------------------------------------------

    wire sign_a = a[31];
    wire sign_b = b[31];
    wire sign_c = c[31];

    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [7:0] exp_c = c[30:23];

    wire [23:0] man_a = {1'b1, a[22:0]};
    wire [23:0] man_b = {1'b1, b[22:0]};
    wire [23:0] man_c = {1'b1, c[22:0]};

    // ------------------------------------------------
    // Multiply stage
    // ------------------------------------------------

    wire sign_mul = sign_a ^ sign_b;

    wire [7:0] exp_mul = exp_a + exp_b - 8'd127;

    wire [47:0] man_mul = man_a * man_b;

    // ------------------------------------------------
    // Normalize multiply result
    // ------------------------------------------------

    wire mul_norm = man_mul[47];

    wire [47:0] man_mul_norm =
        mul_norm ? man_mul :
                   (man_mul << 1);

    wire [7:0] exp_mul_norm =
        mul_norm ? exp_mul + 1 :
                   exp_mul;

    // ------------------------------------------------
    // Extend C mantissa to match 48-bit precision
    // ------------------------------------------------

    wire [47:0] man_c_ext = {man_c, 23'b0};

    // ------------------------------------------------
    // Exponent alignment
    // ------------------------------------------------

    wire exp_cmp = (exp_mul_norm >= exp_c);

    wire [7:0] exp_big =
        exp_cmp ? exp_mul_norm : exp_c;

    wire [47:0] man_mul_shift =
        exp_cmp ? man_mul_norm :
                  (man_mul_norm >> (exp_c - exp_mul_norm));

    wire [47:0] man_c_shift =
        exp_cmp ? (man_c_ext >> (exp_mul_norm - exp_c)) :
                  man_c_ext;

    // ------------------------------------------------
    // Add mantissas
    // ------------------------------------------------

    wire [48:0] man_add =
        man_mul_shift + man_c_shift;

    wire sign_out =
        exp_cmp ? sign_mul : sign_c;

    // ------------------------------------------------
    // Normalize result
    // ------------------------------------------------

    wire norm = man_add[48];

    wire [7:0] exp_out =
        norm ? exp_big + 1 :
               exp_big;

    wire [22:0] man_out =
        norm ? man_add[47:25] :
               man_add[46:24];

    // ------------------------------------------------
    // Pack result
    // ------------------------------------------------

    assign result = {sign_out, exp_out, man_out};

endmodule