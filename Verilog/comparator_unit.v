// MODULE 4: Comparator Unit

`timescale 1ns / 1ps

module comparator_unit (
    input [63:0] A,
    input [63:0] B,
    output [63:0] Result
);
    // Returns 1 if A < B, else 0
    assign Result = (A < B) ? 64'd1 : 64'd0;
endmodule
