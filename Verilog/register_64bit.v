module register_64bit (
    input        clk,
    input        rst,    
    input        en,
    input  [63:0] D,
    output reg [63:0] Q
);

    always @(posedge clk) begin
        if (rst) begin
            Q <= 64'd0;
        end else if (en) begin
            Q <= D;
        end
    end

endmodule
