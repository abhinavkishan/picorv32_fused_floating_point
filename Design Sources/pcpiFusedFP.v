module picorv32_pcpi_fusedfp (

    input clk,
    input resetn,

    input pcpi_valid,
    input [31:0] pcpi_insn,
    input [31:0] pcpi_rs1,
    input [31:0] pcpi_rs2,
    input [31:0] pcpi_rs3,

    output reg pcpi_wr,
    output reg [31:0] pcpi_rd,
    output reg pcpi_wait,
    output reg pcpi_ready
);

    // -------------------------------------------------
    // instruction decode
    // -------------------------------------------------

    wire [6:0] opcode = pcpi_insn[6:0];
    wire [2:0] funct3 = pcpi_insn[14:12];

    wire instr_fusedfp;

    assign instr_fusedfp =
        pcpi_valid          &&
        opcode == 7'b0110011 &&   // custom-0: reserved, no standard meaning
        funct3 == 3'b001; 

    // -------------------------------------------------
    // FMA unit
    // -------------------------------------------------

    wire [31:0] fma_out;
    wire fma_done;

    mainMod fma_unit (
        .A       (pcpi_rs1),
        .B       (pcpi_rs2),
        .C       (pcpi_rs3),
        .D(),      // was duplicate .b - fixed to .D
        .op      (1'b1),            // hardwired: add
        .rnd_mode(2'b00),           // hardwired: truncate
        .out     (fma_out),         // was .result - fixed to .out
        .done    (fma_done)
    );

    // -------------------------------------------------
    // FSM
    // -------------------------------------------------

    reg busy;

    always @(posedge clk) begin

        if (!resetn) begin
            pcpi_wr <= 0;
            pcpi_ready <= 0;
            pcpi_wait <= 0;
            pcpi_rd <= 0;
            busy <= 0;
        end

        else begin

            pcpi_wr <= 0;
            pcpi_ready <= 0;

            // start instruction
            if (pcpi_valid && instr_fusedfp && !busy) begin
                busy <= 1;
                pcpi_wait <= 1;
            end

            // computation running
            else if (busy) begin

                pcpi_wait <= 1;

                if (fma_done) begin
                    pcpi_rd <= fma_out;
                    pcpi_wr <= 1;
                    pcpi_ready <= 1;
                    pcpi_wait <= 0;
                    busy <= 0;
                end
            end

            else begin
                pcpi_wait <= 0;
            end
        end

    end

endmodule