// This is a structual type of reg_file

`timescale 1ns / 1ps

module reg_file (
    input clk,
	 input rst,
    input wena,                  
    input [2:0] waddr,           
    input [63:0] wdata,          
    input [2:0] r0addr,          
    input [2:0] r1addr,          
    output [63:0] r0data,        
    output [63:0] r1data         
);

    wire [7:0] reg_en;          					// Output of Decoder -> Input to Registers
    wire [63:0] r0, r1, r2, r3, r4, r5, r6, r7; 	// Outputs of Registers

    // 1. Decoder
    decoder_3to8 DECODER (
        .in(waddr),
        .enable(wena),
        .out(reg_en)
    );

    // 2. 64-bit DFF
    register_64bit R0 (.clk(clk), .rst(rst), .en(reg_en[0]), .D(wdata), .Q(r0));
    register_64bit R1 (.clk(clk), .rst(rst), .en(reg_en[1]), .D(wdata), .Q(r1));
    register_64bit R2 (.clk(clk), .rst(rst), .en(reg_en[2]), .D(wdata), .Q(r2));
    register_64bit R3 (.clk(clk), .rst(rst), .en(reg_en[3]), .D(wdata), .Q(r3));
    register_64bit R4 (.clk(clk), .rst(rst), .en(reg_en[4]), .D(wdata), .Q(r4));
    register_64bit R5 (.clk(clk), .rst(rst), .en(reg_en[5]), .D(wdata), .Q(r5));
    register_64bit R6 (.clk(clk), .rst(rst), .en(reg_en[6]), .D(wdata), .Q(r6));
    register_64bit R7 (.clk(clk), .rst(rst), .en(reg_en[7]), .D(wdata), .Q(r7));

    // 3. Read Port 0 Multiplexer
    mux_8to1 MUX_PORT0 (
        .sel(r0addr),
        .d0(r0), .d1(r1), .d2(r2), .d3(r3),
        .d4(r4), .d5(r5), .d6(r6), .d7(r7),
        .out(r0data)
    );

    // 4. Read Port 1 Multiplexer
    mux_8to1 MUX_PORT1 (
        .sel(r1addr),
        .d0(r0), .d1(r1), .d2(r2), .d3(r3),
        .d4(r4), .d5(r5), .d6(r6), .d7(r7),
        .out(r1data)
    );

endmodule
