`timescale 1ns / 1ps
// =============================================================================
// ARM_pipeline_tb.v  —  Corrected testbench for the Quad-Threaded ARM Core
//
// Fixes applied vs. original:
//   1. wea forced as 1-bit (not 8-bit)
//   2. Readback uses uut.DataMem.douta (not uut.mem_out_raw)
//   3. Readback synchronises to clock edges (not blind #20 delay)
//   4. Loop reads 5 x 64-bit words (holds 10 x 32-bit sorted integers)
//   5. PC / instruction trace added so stalls are visible
//   6. Simulation time extended to 500 us to survive slow convergence
// =============================================================================

module ARM_pipeline_tb;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    // -------------------------------------------------------------------------
    // File-I/O handles
    // -------------------------------------------------------------------------
    integer file_out;
    integer i;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    ARM_pipeline uut (
        .clk(clk),
        .rst(rst)
    );

    // -------------------------------------------------------------------------
    // Clock  —  10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        // 1. Hold reset for 10 cycles
        rst = 1;
        repeat (10) @(posedge clk);
        @(negedge clk);          // release on a negedge for clean signal
        rst = 0;

        $display("==================================================");
        $display("=== ARM Core Simulation Started                ===");
        $display("==================================================");

        // 2. Run long enough for all 4 threads to complete the sort.
        //    Thread 0 gets 1/4 of the clock bandwidth.
        //    ~55 instructions x 4-cycle interleave x safety margin = ~500 us.
        #500_000;

        $display("==================================================");
        $display("=== Simulation complete — dumping memory       ===");
        $display("==================================================");

        // 3. Open result file
        file_out = $fopen("sort_result.txt", "w");
        if (file_out == 0) begin
            $display("ERROR: Could not open sort_result.txt");
            $finish;
        end

        // 4. Freeze any further CPU writes to data memory
        //    wea is 1-bit on the dmem_64x256 IP core
        force uut.DataMem.wea = 1'b0;

        $fdisplay(file_out, "=== Final Sorted Data Memory Content ===");
        $fdisplay(file_out, "%-6s  %-18s  %-18s  %-12s  %-12s",
                  "Word", "[63:32] hex", "[31:0]  hex", "high (dec)", "low  (dec)");
        $fdisplay(file_out, "%s", {70{"-"}});

        // 5. Read back 5 x 64-bit words  =  10 x 32-bit sorted integers.
        //    Each pair is packed: word[31:0] = lower byte-address (even index),
        //                         word[63:32] = higher byte-address (odd index).
        for (i = 0; i < 5; i = i + 1) begin
            force uut.DataMem.addra = i[7:0];
            @(posedge clk);   // clock the address into the synchronous BRAM
            @(posedge clk);   // one more cycle for registered output to settle

            $fdisplay(file_out, "%-60d  0x%08h          0x%08h          %-12d  %-12d",
                      i,
                      uut.DataMem.douta[63:32],
                      uut.DataMem.douta[31:0],
                      $signed(uut.DataMem.douta[63:32]),
                      $signed(uut.DataMem.douta[31:0]));

            $display("Word %0d | [63:32]=0x%08h (%0d)  [31:0]=0x%08h (%0d)",
                     i,
                     uut.DataMem.douta[63:32],
                     $signed(uut.DataMem.douta[63:32]),
                     uut.DataMem.douta[31:0],
                     $signed(uut.DataMem.douta[31:0]));
        end

        // 6. Release forced signals and close file
        release uut.DataMem.wea;
        release uut.DataMem.addra;
        $fclose(file_out);

        $display("==================================================");
        $display("=== Results saved to sort_result.txt           ===");
        $display("=== Expected (ascending): -455,-56,0,2,10,65,98,123,125,323 ===");
        $display("==================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Real-time monitor: data memory WRITES
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && uut.mem_mem_we && uut.mem_cond_passed) begin
            $display("[%0t ns] DMEM WRITE | Thread %0d | ByteAddr=0x%04h | Data=0x%016h",
                     $time,
                     uut.mem_tid,
                     uut.mem_alu_res[15:0],
                     uut.aligned_store_data);
        end
    end

    // -------------------------------------------------------------------------
    // Real-time monitor: data memory READS
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && uut.mem_is_load && uut.mem_cond_passed) begin
            $display("[%0t ns] DMEM READ  | Thread %0d | ByteAddr=0x%04h",
                     $time,
                     uut.mem_tid,
                     uut.mem_alu_res[15:0]);
        end
    end

    // -------------------------------------------------------------------------
    // Real-time monitor: PC advance per thread  (optional — comment out if
    // the transcript becomes too noisy once the pipeline is working)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst) begin
            $display("[%0t ns] IF | Thread %0d | PC=0x%08h | Instr=0x%08h",
                     $time,
                     uut.thread_sel,
                     uut.curr_pc,
                     uut.if_instr);
        end
    end

    // -------------------------------------------------------------------------
    // Watchdog  —  abort if something is clearly wrong and we spin forever
    // -------------------------------------------------------------------------
    initial begin
        #1_000_000;
        $display("WATCHDOG: simulation exceeded 1 ms — forcing stop.");
        $finish;
    end

endmodule
