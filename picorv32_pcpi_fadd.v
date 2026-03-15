module picorv32_pcpi_fadd (
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

    // ---------------------------------------------------------
    // FADD instruction encoding (custom R-type style)
    // opcode  = 0110011
    // funct7  = 0100000  (chosen for FADD)
    // funct3  = 000
    // ---------------------------------------------------------

    wire instr_fadd =
        pcpi_valid &&
        pcpi_insn[6:0]   == 7'b0110011 &&
        pcpi_insn[31:25] == 7'b0100000 &&   // different from FMUL
        pcpi_insn[14:12] == 3'b000;

    wire [31:0] fadd_out;

    // Floating-point adder instance
    fp_add fadd_unit (
        .A(pcpi_rs1),
        .B(pcpi_rs2),
        .rnd_mode(2'b00),      // round to nearest-even
        .out(fadd_out)
    );

    // ---------------------------------------------------------
    // PCPI handshake (single-cycle like your multiplier)
    // ---------------------------------------------------------

    always @(posedge clk) begin
        if (!resetn) begin
            pcpi_wr    <= 0;
            pcpi_ready <= 0;
            pcpi_wait  <= 0;
            pcpi_rd    <= 0;
        end else begin
            pcpi_wr    <= 0;
            pcpi_ready <= 0;
            pcpi_wait  <= 0;   // no stall (single-cycle)

            if (instr_fadd) begin
                pcpi_wr    <= 1;
                pcpi_ready <= 1;
                pcpi_rd    <= fadd_out;
            end
        end
    end

endmodule
