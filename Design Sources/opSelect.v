`timescale 1ns / 1ps

module opSelect(aSign,bSign,cSign,op,opSel);

input aSign,bSign,cSign,op;
output opSel;

wire abSign;
wire cSignEff;
wire opComp;

// sign of product A*B
xor x1(abSign,aSign,bSign);

// invert C sign when subtraction
not n1(opComp,op);
xor x2(cSignEff,cSign,opComp);

// decide add/sub
xor x3(opSel,abSign,cSignEff);

endmodule