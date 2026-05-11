module picorv32_pcpi_fmul (
    input clk,
    input resetn,

    input             pcpi_valid,
    input      [31:0] pcpi_insn,
    input      [31:0] pcpi_rs1,
    input      [31:0] pcpi_rs2,

    output reg        pcpi_wr,
    output reg [31:0] pcpi_rd,
    output reg        pcpi_wait,
    output reg        pcpi_ready
);

    // FMUL instruction encoding
    wire instr_fmul =
        pcpi_valid &&
        pcpi_insn[6:0]   == 7'b0110011 &&
        pcpi_insn[31:25] == 7'b0100001 &&
        pcpi_insn[14:12] == 3'b000;

    wire [31:0] fmul_out;

    fp_mul fmul_unit (
        .A(pcpi_rs1),
        .B(pcpi_rs2),
        .rnd_mode(2'b00),
        .out(fmul_out)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            pcpi_wr    <= 0;
            pcpi_ready <= 0;
            pcpi_wait  <= 0;
            pcpi_rd    <= 0;
        end else begin
            pcpi_wr    <= 0;
            pcpi_ready <= 0;
            pcpi_wait  <= 0;   // single-cycle ? no stall

            if (instr_fmul) begin
                pcpi_wr    <= 1;
                pcpi_ready <= 1;
                pcpi_rd    <= fmul_out;
            end
        end
    end
endmodule
