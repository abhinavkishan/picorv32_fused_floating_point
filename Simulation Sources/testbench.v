// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.

`timescale 1 ns / 1 ps

module testbench;
	reg clk = 1;
	reg resetn = 0;
	wire trap;

	always #5 clk = ~clk;

	initial begin
		if ($test$plusargs("vcd")) begin
			$dumpfile("testbench.vcd");
			$dumpvars(0, testbench);
		end
		repeat (100) @(posedge clk);
		resetn <= 1;
		repeat (1000) @(posedge clk);
		$finish;
	end

	wire mem_valid;
	wire mem_instr;
	reg mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0] mem_wstrb;
	reg  [31:0] mem_rdata;

	always @(posedge clk) begin
		if (mem_valid && mem_ready) begin
			if (mem_instr)
				$display("ifetch 0x%08x: 0x%08x", mem_addr, mem_rdata);
			else if (mem_wstrb)
				$display("write  0x%08x: 0x%08x (wstrb=%b)", mem_addr, mem_wdata, mem_wstrb);
			else
				$display("read   0x%08x: 0x%08x", mem_addr, mem_rdata);
		end
	end

	picorv32 #(
	) uut (
		.clk         (clk        ),
		.resetn      (resetn     ),
		.trap        (trap       ),
		.mem_valid   (mem_valid  ),
		.mem_instr   (mem_instr  ),
		.mem_ready   (mem_ready  ),
		.mem_addr    (mem_addr   ),
		.mem_wdata   (mem_wdata  ),
		.mem_wstrb   (mem_wstrb  ),
		.mem_rdata   (mem_rdata  )
	);

	reg [31:0] memory [0:255];

initial begin
    // --- Load A[0]=1.5 into x1 (0x3FC00000) ---
    memory[0]  = 32'h3FC000B7; // lui x1, 0x3FC00
    memory[1]  = 32'h00008093; // addi x1, x1, 0

    // --- Load A[1]=2.5 into x2 (0x40200000) ---
    memory[2]  = 32'h40200137; // lui x2, 0x40200
    memory[3]  = 32'h00010113; // addi x2, x2, 0

    // --- Load A[2]=3.0 into x3 (0x40400000) ---
    memory[4]  = 32'h404001B7; // lui x3, 0x40400
    memory[5]  = 32'h00018193; // addi x3, x3, 0

    // --- Load A[3]=4.0 into x4 (0x40800000) ---
    memory[6]  = 32'h40800237; // lui x4, 0x40800
    memory[7]  = 32'h00020213; // addi x4, x4, 0

    // --- Load B[0]=1.0 into x10 (0x3F800000) ---
    memory[8]  = 32'h3F800537; // lui x10, 0x3F800
    memory[9]  = 32'h00050513; // addi x10, x10, 0

    // --- Load B[1]=2.0 into x11 (0x40000000) ---
    memory[10] = 32'h400005B7; // lui x11, 0x40000
    memory[11] = 32'h00058593; // addi x11, x11, 0

    // --- Load B[2]=3.0 into x12 (0x40400000) ---
    memory[12] = 32'h40400637; // lui x12, 0x40400
    memory[13] = 32'h00060613; // addi x12, x12, 0

    // --- Load B[3]=4.0 into x13 (0x40800000) ---
    memory[14] = 32'h408006B7; // lui x13, 0x40800
    memory[15] = 32'h00068693; // addi x13, x13, 0

    // --- Vector MAC instruction ---
    // opcode = 0b0001011  funct3 = 3'b111
    // insn[31:27] = N = 4  ? 5'b00100
    // insn[26:25] = 2'b00  (unused funct7 low bits)
    // rs2 [24:20] = x10 = 5'b01010  (base of B[])
    // rs1 [19:15] = x1  = 5'b00001  (base of A[])
    // funct3      = 3'b111
    // rd  [11:7]  = x20 = 5'b10100  (result destination)
    // opcode      = 7'b0001011
    //
    //  31-27   26-25  24-20   19-15   14-12  11-7    6-0
    //  00100 | 00 | 01010 | 00001 | 111 | 10100 | 0001011
    memory[16] = 32'b00100_00_01010_00001_111_10100_0001011;

    // --- Store result (x20) to address 0x200 ---
    //memory[17] = 32'h20000A13; // addi x20, x0, 0x200  (reuse x20 as addr - save result first)
    // Better: use a separate address register x21
    memory[17] = 32'h20000AB7; // lui x21, 0x200        ? x21 = 0x200000, too big
    // Use addi for small address:
    //memory[17] = 32'h10000A93; // addi x21, x0, 256     ? x21 = 0x100
    memory[18] = 32'h014AAA23; // sw x20, 0(x21)        ? mem[0x100] = result

    // --- Stop ---
    memory[19] = 32'h00100073; // ecall
end



	always @(posedge clk) begin
		mem_ready <= 0;
		if (mem_valid && !mem_ready) begin
			if (mem_addr < 1024) begin
				mem_ready <= 1;
				mem_rdata <= memory[mem_addr >> 2];
				if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
				if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
				if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
				if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
			end
			/* add memory-mapped IO here */
		end
	end
endmodule