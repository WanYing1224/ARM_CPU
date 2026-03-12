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
    always @(posedge clk) begin
        if (rst) begin
            Z <= 64'd0;
            overflow <= 1'b0;
        end else begin
            // Default: reset overflow unless it's arithmetic
            overflow <= 1'b0; 
            
            case (aluctrl[3:2]) // Use upper bits to select Unit
                2'b00: begin 
                    // 00XX -> Arithmetic or Logic
                    if (aluctrl[1] == 1'b0) begin 
                         // 0000 (ADD) or 0001 (SUB)
                         Z <= arith_res;
                         overflow <= arith_ovf;
                    end else begin 
                         // 0010 (AND) or 0011 (OR)
                         Z <= logic_res;
                    end
                end

                2'b01: begin
                    // 01XX -> XNOR, CMP, Shift
                    case (aluctrl[1:0])
                        2'b00: Z <= logic_res; // 0100 (XNOR - reused logic unit path)
                        2'b01: Z <= comp_res;  // 0101 (CMP)
                        2'b10: Z <= shift_res; // 0110 (SHL)
                        2'b11: Z <= shift_res; // 0111 (SHR)
                    endcase
                end
                
                default: Z <= 64'd0;
            endcase
        end
    end

endmodule
