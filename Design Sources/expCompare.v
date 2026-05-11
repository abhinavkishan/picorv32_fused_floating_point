`timescale 1ns / 1ps

module expCompare(aExp,bExp,cExp,exp,expComp,expDiff);

input [7:0] aExp,bExp,cExp;

output expComp;
output [7:0] exp,expDiff;

wire [7:0] abExp;
wire [7:0] abExpBias;
wire [7:0] cExpComp;
wire [7:0] diff;
wire [7:0] muxOut;
wire [7:0] bias;

wire cy_ab,cout;

// A+B exponent
KSA_8 k1(aExp,bExp,1'b0,abExp,cy_ab);

// subtract bias
complement_2s c2(8'd127,bias);
KSA_8 k2(abExp,bias,1'b0,abExpBias,cout);

// complement of C exponent
complement_2s c1(cExp,cExpComp);

// compare exponents
KSA_8 k3(abExpBias,cExpComp,1'b0,diff,expComp);

// choose larger exponent
mux_2_1 m1(cExp,abExpBias,expComp,muxOut);

// absolute difference
expInvert e1(diff,expComp,expDiff);

// output exponent
assign exp = muxOut;

endmodule

module expInvert(in,control,out);
input control;
input [7:0]in;
output reg [7:0]out;
always@(in or control)
begin
if(control==0)
begin
out=~in;
out=out+1;
end
else
out=in;
end
endmodule