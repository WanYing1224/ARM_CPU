// MODULE 2: Logic Unit

`timescale 1ns / 1ps

module logic_unit (
    input [63:0] A,
    input [63:0] B,
    input [1:0] op_sel, // 10: AND, 11: OR, 00: XNOR
    output reg [63:0] Result
);
    always @(*) begin
        case(op_sel)
            2'b10: Result = A & B;
            2'b11: Result = A | B;
            2'b00: Result = ~(A ^ B);
            default: Result = 64'd0;
        endcase
    end
endmodule
