module picorv32_pcpi_nfp #(
    parameter MUL_LATENCY = 3,
    parameter ADD_LATENCY = 3
)(
    input  wire        clk,
    input  wire        resetn,

    input  wire        pcpi_valid,
    input  wire [31:0] pcpi_insn,

    // rs1/rs2 are LIVE - CPU mux changes them when pcpi_read is pulsed
    input  wire [31:0] pcpi_rs1,
    input  wire [31:0] pcpi_rs2,

    output reg         pcpi_wr,
    output reg  [31:0] pcpi_rd,
    output reg         pcpi_wait,
    output reg         pcpi_ready,

    // Back to CPU: pulse to advance register index by 1
    output reg         pcpi_read
);
    // ------------------------------------------------------------------
    // Instruction encoding
    //
    //  31      25 24   20 19   15 14  12 11    7 6      0
    //  [funct7  ] [rs2  ] [rs1  ] [f3 ] [rd   ] [opcode]
    //
    //  opcode  = 7'b000_1011   (custom-0)
    //  funct3  = 3'b010
    //  funct7  = { N[4:0], 2'b00 }    bits [31:27] = N (1..31 elements)
    //  rs1     = base register for A[]  (A[0] in r_rs1, A[1] in r_rs1+1 ...)
    //  rs2     = base register for B[]
    //  rd      = destination register for the scalar result
    // ------------------------------------------------------------------
    wire [6:0] opcode  = pcpi_insn[6:0];
    wire [2:0] funct3  = pcpi_insn[14:12];
    wire [4:0] vec_N   = pcpi_insn[31:27];   // N, number of elements (1-based)

    wire instr_dotp = pcpi_valid
                   && opcode == 7'b000_1011
                   && funct3 == 3'b111
                   && vec_N  != 0;           // N=0 is a NOP

    // ------------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------------
    localparam S_IDLE = 3'd0;
    localparam S_READ = 3'd1;   // rs1/rs2 are valid - latch and start MAC
    localparam S_MUL  = 3'd2;   // waiting for FP multiplier
    localparam S_ADD  = 3'd3;   // waiting for FP adder
    localparam S_DONE = 3'd4;   // write result, release CPU

    reg [2:0]  state;
    reg [31:0] accumulator;
    reg [4:0]  elem_cnt;        // how many elements processed so far
    reg [4:0]  total_N;         // N latched from instruction

    // ------------------------------------------------------------------
    // FP unit instantiation
    // Replace fp_mul_stub / fp_add_stub with your real modules.
    // They must have:  .start (1-cycle pulse) .done (1-cycle pulse) .result
    // ------------------------------------------------------------------
    reg  [31:0] mul_a, mul_b;
    reg         mul_start;
    wire [31:0] mul_result;
    wire        mul_done;

    reg  [31:0] add_a, add_b;
    reg         add_start;
    wire [31:0] add_result;
    wire        add_done;

    fp_mul_stub #(.LATENCY(MUL_LATENCY)) u_mul (
        .clk(clk), .resetn(resetn),
        .a(mul_a), .b(mul_b), .start(mul_start),
        .result(mul_result), .done(mul_done)
    );
    fp_add_stub #(.LATENCY(ADD_LATENCY)) u_add (
        .clk(clk), .resetn(resetn),
        .a(add_a), .b(add_b), .start(add_start),
        .result(add_result), .done(add_done)
    );

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            state       <= S_IDLE;
            accumulator <= 32'h0000_0000;
            elem_cnt    <= 0;
            total_N     <= 0;
            pcpi_wr     <= 0;
            pcpi_rd     <= 0;
            pcpi_wait   <= 0;
            pcpi_ready  <= 0;
            pcpi_read   <= 0;
            mul_start   <= 0;
            add_start   <= 0;
        end
        else begin
            // Default: de-assert all strobes
            pcpi_wr    <= 0;
            pcpi_ready <= 0;
            pcpi_read  <= 0;
            mul_start  <= 0;
            add_start  <= 0;

            case (state)

                // -------------------------------------------------------
                // S_IDLE: wait for a valid dotp instruction
                // -------------------------------------------------------
                S_IDLE: begin
                    pcpi_wait <= 0;
                    if (instr_dotp) begin
                        total_N     <= vec_N;
                        elem_cnt    <= 0;
                        accumulator <= 32'h0000_0000;
                        pcpi_wait   <= 1;
                        // rs1/rs2 are already A[0]/B[0] (base address)
                        // because pcpi_rs1_idx was set to decoded_rs1
                        // in the CPU when this instruction was decoded.
                        state <= S_READ;
                    end
                end

                // -------------------------------------------------------
                // S_READ: rs1 and rs2 are the current element pair.
                //         Latch them, start the multiplier.
                //         If more elements remain, pulse pcpi_read so the
                //         CPU increments its register index - by the time
                //         MUL+ADD finishes, rs1/rs2 will have settled on
                //         the next pair.
                // -------------------------------------------------------
                S_READ: begin
                    pcpi_wait <= 1;

                    // Start multiplier with current element pair
                    mul_a     <= pcpi_rs1;     // A[elem_cnt]
                    mul_b     <= pcpi_rs2;     // B[elem_cnt]
                    mul_start <= 1;

                    // Advance register index ONLY if there is a next element.
                    // The CPU will increment pcpi_rs1_idx and pcpi_rs2_idx
                    // on the very next clock edge.
                    if (elem_cnt < total_N - 1)
                        pcpi_read <= 1;

                    state <= S_MUL;
                end

                // -------------------------------------------------------
                // S_MUL: waiting for FP multiplier to finish
                // -------------------------------------------------------
                S_MUL: begin
                    pcpi_wait <= 1;
                    if (mul_done) begin
                        // Feed product and current accumulator into adder
                        add_a     <= mul_result;
                        add_b     <= accumulator;
                        add_start <= 1;
                        state     <= S_ADD;
                    end
                end

                // -------------------------------------------------------
                // S_ADD: waiting for FP adder to finish
                // -------------------------------------------------------
                S_ADD: begin
                    pcpi_wait <= 1;
                    if (add_done) begin
                        accumulator <= add_result;
                        elem_cnt    <= elem_cnt + 1;

                        if (elem_cnt == total_N - 1) begin
                            // All N elements done
                            state <= S_DONE;
                        end
                        else begin
                            // More elements.  rs1/rs2 already advanced -
                            // pcpi_read was pulsed back in S_READ, and
                            // MUL+ADD latency gives the CPU plenty of time
                            // to settle the new register values.
                            state <= S_READ;
                        end
                    end
                end

                // -------------------------------------------------------
                // S_DONE: write result back to CPU register file
                // -------------------------------------------------------
                S_DONE: begin
                    pcpi_rd    <= accumulator;
                    pcpi_wr    <= 1;
                    pcpi_ready <= 1;
                    pcpi_wait  <= 0;
                    state      <= S_IDLE;
                end

            endcase
        end
    end

endmodule