`timescale 1ns / 1ps

module reg_file (
    input clk,
    input rst,
    input wena,                  
    input [3:0] waddr,   // 4-bit address for 16 registers
    input [63:0] wdata,          
    input [3:0] r0addr,  // 4-bit address
    input [3:0] r1addr,  // 4-bit address
    output [63:0] r0data,        
    output [63:0] r1data         
);

    // 16 Registers, each 64-bits wide
    reg [63:0] registers [0:15];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] <= 64'd0;
            end
        end else if (wena) begin
            registers[waddr] <= wdata;
        end
    end

    // Asynchronous Read
    assign r0data = registers[r0addr];
    assign r1data = registers[r1addr];

endmodule
