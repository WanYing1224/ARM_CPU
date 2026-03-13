`timescale 1ns / 1ps

module ARM_pipeline_tb;

    // --- Inputs ---
    reg clk;
    reg rst;

    // --- Internal Variables for File I/O ---
    integer file_out;
    integer i;

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
        // Thread 0 runs at 1/4 speed due to 4-thread interleaving.
        #200000; 

        $display("==================================================");
        $display("=== Simulation Complete: Writing to File       ===");
        $display("==================================================");

        // 4. Open Output File
        file_out = $fopen("sort_result.txt", "w");
        
        if (file_out == 0) begin
            $display("Error: Could not open sort_result.txt for writing.");
        end else begin
            // 5. Force control of Memory Bus to read final values
            // We use 'force' to override the CPU control signals
            force uut.DataMem.wea = 8'h00; 

            $fdisplay(file_out, "=== Final Sorted Data Memory Content ===");
            
            // Loop through the first 5 lines (which hold 10 integers)
            for (i = 0; i < 5; i = i + 1) begin
                force uut.DataMem.addra = i[7:0];
                #20; // Wait for memory read latency
                
                $fdisplay(file_out, "Line %0d (64-bit Hex): %h", i, uut.mem_out_raw);
                $display("Transcript -> Line %0d: %h", i, uut.mem_out_raw);
            end
            
            // 6. Release hardware control and close file
            release uut.DataMem.wea;
            release uut.DataMem.addra;
            $fclose(file_out);
            
            $display("Success: Results saved to 'sort_result.txt'");
        end

        $display("==================================================");
        $finish;
    end

    // --- Real-Time Memory Write Monitor ---
    always @(posedge clk) begin
        if (uut.mem_mem_we && uut.mem_cond_passed) begin
            $display("Time: %0t ns | Thread: %0d | DMEM Write -> Byte Addr: 0x%04h | Data: 0x%016h",
                     $time, uut.mem_tid, uut.mem_alu_res[15:0], uut.aligned_store_data);
        end
    end

    // --- Real-Time Memory Read Monitor ---
    always @(posedge clk) begin
        if (uut.mem_is_load && uut.mem_cond_passed) begin
            $display("Time: %0t ns | Thread: %0d | DMEM Read  <- Byte Addr: 0x%04h",
                     $time, uut.mem_tid, uut.mem_alu_res[15:0]);
        end
    end

endmodule
