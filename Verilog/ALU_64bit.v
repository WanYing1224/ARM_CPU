// TOP LEVEL MODULE: ALU_64bit

`timescale 1ns / 1ps

module ALU_64bit (
    input clk,
    input rst,
    input [63:0] A,
    input [63:0] B,
    input [3:0] aluctrl,
    output reg [63:0] Z,
    output reg overflow
);

    // Internal wires for intermediate results
    wire [63:0] arith_res, logic_res, shift_res, comp_res;
    wire arith_ovf;
    
    // 1. Arithmetic Unit
    // aluctrl[0] is 1 for SUB (4'b0001), 0 for ADD (4'b0000)
    arithmetic_unit U_ARITH (
        .A(A), 
        .B(B), 
        .is_sub(aluctrl[0]), 
        .Result(arith_res), 
        .Overflow(arith_ovf)
    );

    // 2. Instantiate Logic Unit
    // Maps: 4'b0010 (AND), 4'b0011 (OR), 4'b0100 (XNOR)
    logic_unit U_LOGIC (
        .A(A), 
        .B(B), 
        .op_sel(aluctrl[1:0]), 
        .Result(logic_res)
    );

    // 3. Instantiate Comparator Unit
    // Maps: 4'b0101 (COMPARE)
    comparator_unit U_COMP (
        .A(A), 
        .B(B), 
        .Result(comp_res)
    );

    // 4. Instantiate Shifter Unit 
    // Maps: 4'b0110 (SHL), 4'b0111 (SHR). aluctrl[0] distinguishes L/R.
    shifter_unit U_SHIFT (
        .A(A), 
        .shamt(B[5:0]), 
        .is_right(aluctrl[0]), 
        .Result(shift_res)
    );

    // 5. Multiplexer & Output Register
    assign zero = (Z == 64'd0);

    always @(*) begin
        Z = 64'd0;
        overflow = 1'b0;
        case (aluctrl[3:2])
            2'b00: begin
                if (!aluctrl[1]) begin 
                    Z = arith_res; 
                    overflow = arith_ovf; 
                end else begin
                    Z = logic_res;
                end
            end
            2'b01: case (aluctrl[1:0])
                2'b00: Z = logic_res;
                2'b01: Z = comp_res;
                default: Z = shift_res;
            endcase
            default: begin
                Z = 64'd0;
            end
        endcase
    end

endmodule
