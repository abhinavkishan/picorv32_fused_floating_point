`timescale 1ns/1ps

module mainMod_tb;

reg [31:0] A;
reg [31:0] B;
reg [31:0] C;
reg op;
reg [1:0] rnd_mode;

wire [31:0] out;

mainMod uut (
    .A(A),
    .B(B),
    .C(C),
    .op(op),
    .rnd_mode(rnd_mode),
    .out(out)
);

initial
begin

rnd_mode = 2'b00;

$display("------------------------------------------------");
$display(" A        B        C        op | OUT");
$display("------------------------------------------------");

// Test 1 : 1*1 + 1 = 2
A = 32'h3f800000;   
B = 32'h3f800000;   
C = 32'h3f800000;   
op = 1;
#10;
$display("%h %h %h  %b | %h",A,B,C,op,out);

// Test 2 : 2*2 + 1 = 5
A = 32'h40000000;   
B = 32'h40000000;   
C = 32'h3f800000;   
op = 1;
#10;
$display("%h %h %h  %b | %h",A,B,C,op,out);

// Test 3 : 3*2 - 1 = 5
A = 32'h40400000;   
B = 32'h40000000;   
C = 32'h3f800000;   
op = 0;
#10;
$display("%h %h %h  %b | %h",A,B,C,op,out);

// Test 4 : 1.5*2 + 0.5 = 3.5
A = 32'h3fc00000;   
B = 32'h40000000;   
C = 32'h3f000000;   
op = 1;
#10;
$display("%h %h %h  %b | %h",A,B,C,op,out);

$display("------------------------------------------------");

#10 $finish;

end

endmodule