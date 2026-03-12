// MODULE 3: Shifter Unit

`timescale 1ns / 1ps

module shifter_unit (
    input [63:0] A,
    input [5:0] shamt,  // Shift amount (lower 6 bits of B)
    input is_right,     // 0: Left, 1: Right
    output [63:0] Result
);
    assign Result = is_right ? (A >> shamt) : (A << shamt);
endmodule
