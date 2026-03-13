`timescale 1ns / 1ps
// ARM_pipeline_tb.v
// Use with: imem = sort.coe (21 instructions, register-based sort)
//           dmem = data.coe (10 values, one per 64-bit BRAM word in [31:0])

module ARM_pipeline_tb;

    reg clk;
    reg rst;
    integer file_out;
    integer i;
    reg [7:0] bram_addr;

    ARM_pipeline uut (
        .clk(clk),
        .rst(rst)
    );

    // 10 ns clock (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        @(negedge clk);
        rst = 0;

        $display("==================================================");
        $display("=== ARM Core Simulation Started  t=%0t ns", $time);
        $display("==================================================");

        // sort.coe: 21 instructions, 10 elements, pointer-based bubble sort.
        // Worst case ~45 swaps * ~4 instrs * 4-thread interleave * 4 pipeline stages
        // = ~2880 cycles = ~29000 ns. Use 100 us for comfortable margin.
        #100_000;

        $display("==================================================");
        $display("=== Simulation complete at t=%0t ns", $time);
        $display("==================================================");

        file_out = $fopen("sort_result.txt", "w");
        if (file_out == 0) begin
            $display("ERROR: $fopen failed");
            $finish;
        end

        // Freeze writes while we read back
        force uut.DataMem.wea = 1'b0;

        $fdisplay(file_out, "=== Sorted Array (sort.coe + data.coe) ===");
        $fdisplay(file_out, "Element  BRAM_addr  Hex         Decimal");
        $fdisplay(file_out, "-------  ---------  ----------  -------");

        // sort.coe places element i at byte address i*8.
        // BRAM addra = byte_addr >> 2 = i*8 >> 2 = i*2.
        // Value is always in douta[31:0] (bit[2] of byte addr is always 0).
        for (i = 0; i < 10; i = i + 1) begin
            bram_addr = i * 2;
            force uut.DataMem.addra = bram_addr;
            @(posedge clk);
            @(posedge clk);
            $fdisplay(file_out, "%6d   %6d     0x%08h  %0d",
                      i, i*2,
                      uut.DataMem.douta[31:0],
                      $signed(uut.DataMem.douta[31:0]));
            $display("Element %2d (BRAM addr %2d): 0x%08h = %5d",
                     i, i*2,
                     uut.DataMem.douta[31:0],
                     $signed(uut.DataMem.douta[31:0]));
        end

        release uut.DataMem.wea;
        release uut.DataMem.addra;
        $fclose(file_out);

        $display("Expected: -455, -56, 0, 2, 10, 65, 98, 123, 125, 323");
        $finish;
    end

    // DMEM write monitor — shows each swap
    always @(posedge clk) begin
        if (!rst && uut.mem_mem_we && uut.mem_cond_passed)
            $display("[%8t] WRITE T%0d ByteAddr=0x%04h Data[31:0]=0x%08h (%0d)",
                     $time, uut.mem_tid,
                     uut.mem_alu_res[15:0],
                     uut.aligned_store_data[31:0],
                     $signed(uut.aligned_store_data[31:0]));
    end

    // Branch taken monitor
    always @(posedge clk) begin
        if (!rst && uut.ex_is_branch && uut.cond_passed)
            $display("[%8t] BRANCH T%0d -> 0x%08h",
                     $time, uut.ex_tid, uut.ex_branch_target);
    end

    // Watchdog
    initial begin
        #500_000;
        $display("WATCHDOG: 500 us — forcing stop");
        $finish;
    end

endmodule
