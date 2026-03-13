`timescale 1ns / 1ps

module ARM_pipeline_tb;

    // --- Inputs ---
    reg clk;
    reg rst;

    // --- Instantiate the Unit Under Test (UUT) ---
    ARM_pipeline uut (
        .clk(clk),
        .rst(rst)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        // 10ns period -> 100 MHz clock
        forever #5 clk = ~clk; 
    end

    // --- Main Test Sequence ---
    initial begin
        // 1. Apply Reset
        rst = 1;
        #100;
        
        // 2. Release Reset
        rst = 0;
        $display("==================================================");
        $display("=== ARM Core Simulation Started                ===");
        $display("==================================================");

        // 3. Wait for Bubble Sort to complete.
        // A 10-element bubble sort takes roughly O(N^2) iterations.
        // Because your ZOMT design interleaves 4 threads, Thread 0 
        // effectively runs at 1/4th the clock speed. 
        // 200,000 ns (20,000 cycles) is plenty of time for it to finish.
        #200000; 

        $display("==================================================");
        $display("=== Simulation Complete                        ===");
        $display("==================================================");
        $finish;
    end

    // --- Memory Write Monitor ---
    // This block prints exactly what the CPU is writing to Data Memory.
    // As the Bubble Sort runs, you should see it swapping your packed 32-bit values.
    always @(posedge clk) begin
        if (uut.mem_mem_we && uut.mem_cond_passed) begin
            $display("Time: %0t ns | Thread: %0d | DMEM Write -> Byte Addr: 0x%04h | Data: 0x%016h",
                     $time, uut.ex_tid, uut.mem_alu_res[15:0], uut.mem_store_data);
        end
    end

    // --- Memory Read Monitor ---
    // This tracks loads (LDR) from the memory to verify the 32-bit extraction
    // logic you added to the Writeback stage is fetching the correct half.
    always @(posedge clk) begin
        if (uut.mem_is_load && uut.mem_cond_passed) begin
            $display("Time: %0t ns | Thread: %0d | DMEM Read  <- Byte Addr: 0x%04h",
                     $time, uut.ex_tid, uut.mem_alu_res[15:0]);
        end
    end

    // --- Register Writeback Monitor (Optional but helpful) ---
    // Uncomment this if you want to trace every single register update
    /*
    always @(posedge clk) begin
        if (uut.wb_we_reg && uut.wb_cond_passed_reg) begin
            $display("Time: %0t ns | Thread: %0d | RegWrite   -> R%0d = 0x%08h",
                     $time, uut.wb_tid, uut.wb_waddr_reg, uut.wb_data[31:0]);
        end
    end
    */

endmodule
