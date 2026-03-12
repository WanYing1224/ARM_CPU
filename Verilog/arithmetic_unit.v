// MODULE 1: Arithmetic Unit (Adder/Subtractor)

`timescale 1ns / 1ps

module arithmetic_unit (
    input [63:0] A,
    input [63:0] B,
    input is_sub,       // Control signal: 0 for Add, 1 for Sub
    output [63:0] Result,
    output Overflow
);
    wire [63:0] B_mux;
    
    // If subtracting, we use 2's complement: ~B + 1. 
    // We achieve the "+1" by setting the carry-in of the adder to 1.
    assign B_mux = is_sub ? ~B : B;
    
    // Structural addition with carry
    assign {Overflow, Result} = A + B_mux + is_sub; 
endmodule
