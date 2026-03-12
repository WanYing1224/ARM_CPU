`timescale 1ns / 1ps
// Condition_Check.v
// Evaluates ARM condition codes (bits 31:28 of instruction) 
// based on the Current Program Status Register (CPSR) flags.

module Condition_Check (
    input [3:0] cond,    // From Instruction[31:28]
    input [3:0] flags,   // {N, Z, C, V} from the thread's CPSR
    output reg passed
);
    wire N = flags[3];
    wire Z = flags[2];
    wire C = flags[1];
    wire V = flags[0];

    always @(*) begin
        case (cond)
            4'b0000: passed = Z;                   // EQ (Equal)
            4'b0001: passed = !Z;                  // NE (Not Equal)
            4'b0010: passed = C;                   // CS/HS (Carry Set)
            4'b0011: passed = !C;                  // CC/LO (Carry Clear)
            4'b0100: passed = N;                   // MI (Minus)
            4'b0101: passed = !N;                  // PL (Plus)
            4'b0110: passed = V;                   // VS (Overflow Set)
            4'b0111: passed = !V;                  // VC (Overflow Clear)
            4'b1000: passed = C && !Z;             // HI (Unsigned Higher)
            4'b1001: passed = !C || Z;             // LS (Unsigned Lower or Same)
            4'b1010: passed = (N == V);            // GE (Signed Greater than or Equal)
            4'b1011: passed = (N != V);            // LT (Signed Less than)
            4'b1100: passed = !Z && (N == V);      // GT (Signed Greater than)
            4'b1101: passed = Z || (N != V);       // LE (Signed Less than or Equal)
            4'b1110: passed = 1'b1;                // AL (Always)
            default: passed = 1'b1;
        endcase
    end
endmodule