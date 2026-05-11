module fp_mul_stub #(
    parameter LATENCY = 0
)(
    input  wire        clk,
    input  wire        resetn,

    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        start,

    output wire [31:0] result,
    output wire        done
);

    // IEEE754 fields
    wire        a_sign = a[31];
    wire [7:0]  a_exp  = a[30:23];
    wire [23:0] a_mant = (a_exp == 0) ? 24'd0 : {1'b1, a[22:0]};

    wire        b_sign = b[31];
    wire [7:0]  b_exp  = b[30:23];
    wire [23:0] b_mant = (b_exp == 0) ? 24'd0 : {1'b1, b[22:0]};

    // Multiply mantissas
    wire [47:0] mant_mul = a_mant * b_mant;

    // Exponent
    wire [8:0] exp_sum = a_exp + b_exp - 8'd127;

    // Normalize
    wire norm = mant_mul[47];

    wire [22:0] final_mant =
        norm ? mant_mul[46:24] :
               mant_mul[45:23];

    wire [7:0] final_exp =
        norm ? (exp_sum + 1'b1) :
               exp_sum[7:0];

    wire final_sign = a_sign ^ b_sign;

    wire is_zero = (a_exp == 0) || (b_exp == 0);

    assign result =
        is_zero ? 32'h00000000 :
                  {final_sign, final_exp, final_mant};

    assign done = start;

endmodule

module fp_add_stub #(
    parameter LATENCY = 0
)(
    input  wire        clk,
    input  wire        resetn,

    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        start,

    output wire [31:0] result,
    output wire        done
);

    // Extract fields
    wire sign_a = a[31];
    wire sign_b = b[31];

    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];

    wire [23:0] mant_a =
        (exp_a == 0) ? 24'd0 : {1'b1, a[22:0]};

    wire [23:0] mant_b =
        (exp_b == 0) ? 24'd0 : {1'b1, b[22:0]};

    // Align exponents
    wire exp_a_gt_b = (exp_a >= exp_b);

    wire [7:0] exp_large =
        exp_a_gt_b ? exp_a : exp_b;

    wire [23:0] mant_large =
        exp_a_gt_b ? mant_a : mant_b;

    wire [23:0] mant_small =
        exp_a_gt_b ? (mant_b >> (exp_a - exp_b)) :
                     (mant_a >> (exp_b - exp_a));

    wire sign_large =
        exp_a_gt_b ? sign_a : sign_b;

    wire sign_small =
        exp_a_gt_b ? sign_b : sign_a;

    // Add/Sub
    wire same_sign = (sign_large == sign_small);

    wire [24:0] mant_add =
        same_sign ?
            ({1'b0, mant_large} + {1'b0, mant_small}) :
            ({1'b0, mant_large} - {1'b0, mant_small});

    reg [22:0] final_mant;
    reg [7:0]  final_exp;

    always @(*) begin
        if (mant_add[24]) begin
            final_mant = mant_add[23:1];
            final_exp  = exp_large + 1'b1;
        end
        else if (mant_add[23]) begin
            final_mant = mant_add[22:0];
            final_exp  = exp_large;
        end
        else if (mant_add[22]) begin
            final_mant = mant_add[21:0] << 1;
            final_exp  = exp_large - 1;
        end
        else if (mant_add[21]) begin
            final_mant = mant_add[20:0] << 2;
            final_exp  = exp_large - 2;
        end
        else begin
            final_mant = 23'd0;
            final_exp  = 8'd0;
        end
    end

    assign result =
        (mant_add == 0) ? 32'd0 :
        {sign_large, final_exp, final_mant};

    assign done = start;

endmodule