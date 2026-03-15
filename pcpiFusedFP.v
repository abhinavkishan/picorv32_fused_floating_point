module picorv32_pcpi_fusedfp (

    input clk,
    input resetn,

    input pcpi_valid,
    input [31:0] pcpi_insn,
    input [31:0] pcpi_rs1,
    input [31:0] pcpi_rs2,

    // register file access (added from core)
    input [31:0] pcpi_rs3,

    output reg pcpi_wr,
    output reg [31:0] pcpi_rd,
    output reg pcpi_wait,
    output reg pcpi_ready
);

    // decode fields
    wire [6:0] opcode = pcpi_insn[6:0];
    wire [2:0] funct3 = pcpi_insn[14:12];

    wire [4:0] rs3 = pcpi_insn[31:27];

    // detect instruction
    wire instr_fusedfp;

    assign instr_fusedfp =
        pcpi_valid &&
        opcode == 7'b0110011 &&
        funct3 == 3'b001;

    // operands
    wire [31:0] a = pcpi_rs1;
    wire [31:0] b = pcpi_rs2;

    wire [31:0] fma_out;

    // user fused floating point module
    fused_fp fma_unit (
        .a(a),
        .b(b),
        .c(c),
        .result(fma_out)
    );

    always @(posedge clk) begin

        pcpi_wr <= 0;
        pcpi_ready <= 0;
        pcpi_wait <= 0;

        if (pcpi_valid && instr_fusedfp) begin

            pcpi_rd <= fma_out;

            pcpi_wr <= 1;
            pcpi_ready <= 1;

        end

    end

endmodule