`timescale 1ns / 1ps

module decoder_3to8 (
    input [2:0] in,
    input enable,
    output reg [7:0] out
);
    always @(*) begin
        out = 8'b00000000;
        if (enable) 
            out[in] = 1'b1; // Set the Nth bit to 1 based on input address
    end
endmodule
