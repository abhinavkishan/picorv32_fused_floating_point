module picorv32_regs (
    input clk,
    input wen,

    input [5:0] waddr,

    input [5:0] raddr1,
    input [5:0] raddr2,
    input [5:0] raddr3,   // NEW third read port
    input [5:0] raddr4,   // NEW third read port

    input [31:0] wdata,

    output [31:0] rdata1,
    output [31:0] rdata2,
    output [31:0] rdata3,   // NEW third read data
    output [31:0] rdata4   // NEW third read data
);

    reg [31:0] regs [0:30];

    // write port
    always @(posedge clk)
        if (wen)
            regs[~waddr[4:0]] <= wdata;

    // read ports
    assign rdata1 = regs[~raddr1[4:0]];
    assign rdata2 = regs[~raddr2[4:0]];
    assign rdata3 = regs[~raddr3[4:0]];   // NEW read
    assign rdata4 = regs[~raddr4[4:0]];   // NEW read
    
endmodule