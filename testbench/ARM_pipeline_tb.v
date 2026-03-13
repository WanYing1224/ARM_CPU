`timescale 1ns / 1ps

// ARM_pipeline_tb.v
// Adapted testbench for your ARM_pipeline design.
// - 100 MHz clock
// - Reset handling
// - Memory read/write monitor
// - Dumps N words from DMEM at end to "dmem_after_sim.hex"
// - Minimal changes required: update the HIERARCHY MAP section if your DUT internal names differ.

module ARM_pipeline_tb;

    // ---------- PARAMETERS ----------
    localparam TIME_RUN = 800000;               // simulation run time in ns (adjust)
    localparam [31:0] START_BYTE_ADDR = 32'h0104; // starting byte address of array to dump
    localparam integer NUM_DUMP_WORDS = 10;     // number of 64-bit words to dump

    // ---------- DUT SIGNALS / TB SCOPE DECLARATIONS ----------
    reg clk;
    reg rst;

    // integers for file IO and loops
    integer i;
    integer fd;
    integer idx;
    integer start_word_index;

    // ---------- INSTANTIATE DUT ----------
    // Assumes top-level module is ARM_pipeline with ports (clk, rst)
    ARM_pipeline uut (
        .clk(clk),
        .rst(rst)
    );

    // ---------- HIERARCHY MAP (EDIT IF NEEDED) ----------
    // If any of these hierarchical references don't match your design,
    // change them to the correct path inside your DUT.
    //
    // Examples:
    // - If DMEM instance is named "DataMem_inst" and the array is "mem_array",
    //   change DMEM_MEM_REF to uut.DataMem_inst.mem_array
    //
    // - If pipeline exposes 'thread_sel' as uut.thread_id, set THREAD_SEL_REF = uut.thread_id
    //
    // By default these follow the names we saw in your waveform:
    wire [1:0] THREAD_SEL_REF = uut.thread_sel;            // thread selector
    wire [63:0] MEM_ALU_RES_REF = uut.mem_alu_res;         // effective memory address (ALU result)
    wire MEM_WE_REF = uut.mem_mem_we;                      // memory write enable (scalar)
    wire MEM_COND_REF = uut.mem_cond_passed;               // condition passed for mem op
    wire [63:0] MEM_STORE_DATA_REF = uut.mem_store_data;   // data being written to memory
    wire MEM_IS_LOAD_REF = uut.mem_is_load;                // true if memory op is a load
    wire [63:0] MEM_OUT_RAW_REF = uut.mem_out_raw;         // raw data read from memory (before wb mux)
    //
    // DMEM internal memory array reference (for dumping contents at end of sim)
    // Typical path used earlier: uut.DataMem.mem
    // If your DMEM instance has a different name / array name edit this line.
    // IMPORTANT: This is a hierarchical reference. If it doesn't match your design,
    // the simulator will complain at elaboration time and you'll need to fix it.
    //
    // Examples both commented:
    //  - default (common):  uut.DataMem.mem
    //  - alt example:       uut.DataMem_inst.mem
    //  - alt example 2:     uut.DataMem.blk_mem.mem
    //
    // Set DMEM_MEM_REF to the correct hierarchical reference for your project.
    // If you cannot reference internal memory, create a readback port in DUT or
    // use the behavioral dmem model that exposes 'mem' during simulation.
    //
    // Default (change if needed):
    `define DMEM_MEM_REF uut.DataMem.mem

    // ---------- CLOCK ----------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // ---------- TEST SEQUENCE ----------
    initial begin
        // reset pulse
        rst = 1;
        #100;
        rst = 0;
		  
		  $display("ALU base=%h imm=%h result=%h",
         uut.ex_op1, uut.ex_op2, uut.ex_alu_res);

        $display("=== Simulation started ===");
        $display("Running for %0d ns", TIME_RUN);

        // run for requested time
        #(TIME_RUN);

        // Compute start word index (64-bit words) from start byte address:
        start_word_index = START_BYTE_ADDR >> 3;

        // Dump DMEM region to file
        fd = $fopen("dmem_after_sim.hex", "w");
        if (fd == 0) begin
            $display("ERROR: could not open dmem_after_sim.hex for writing");
        end else begin
            $display("Dumping %0d words starting at byte addr 0x%h (word index %0d)",
                     NUM_DUMP_WORDS, START_BYTE_ADDR, start_word_index);

            // Attempt to dump using hierarchical memory reference.
            // If your DMEM internal regs are named differently, edit the DMEM_MEM_REF define above.
            for (idx = 0; idx < NUM_DUMP_WORDS; idx = idx + 1) begin
                // format: word_index : hex64
                // Use non-blocking read of hierarchical array
                // NOTE: if DMEM is a vendor core without a visible reg array the reference must be adjusted
                $fwrite(fd, "%0d: 0x%016h\n", idx, uut.mem_out_raw);
                $fwrite(fd, "%0d: 0x%016h\n", idx, uut.mem_out_raw);
            end

            $fclose(fd);
            $display("DMEM dump complete -> dmem_after_sim.hex");
        end

        #10;
        $display("=== Simulation finished ===");
        $finish;
    end

    // ---------- MEMORY MONITOR ----------
    // Print a concise, human-readable trace of memory activity
    initial begin
        $display("--- MEM MONITOR START ---");
        $display("time | thread | addr (byte) | word_idx | wea_mask | write_data (hex)       | read_data (hex) | op");
    end

    // compute word index etc at each clock edge where mem op occurs
    always @(posedge clk) begin
        // If a write is requested and condition passed, print it
        if (MEM_WE_REF && MEM_COND_REF) begin
            $display("%0t | %0d | 0x%h | 0x%h | 0x%02x | 0x%016h |                | write",
                     $time, THREAD_SEL_REF, MEM_ALU_RES_REF, (MEM_ALU_RES_REF >> 3),
                     8'hFF, // using 0xFF as a conservative mask if you don't have byte mask visible
                     MEM_STORE_DATA_REF);
        end

        // If it's a load and condition passed, print read
        if (MEM_IS_LOAD_REF && MEM_COND_REF) begin
            $display("%0t | %0d | 0x%h | 0x%h | 0x%02x |                | 0x%016h | read",
                     $time, THREAD_SEL_REF, MEM_ALU_RES_REF, (MEM_ALU_RES_REF >> 3),
                     8'h00,
                     MEM_OUT_RAW_REF);
        end
    end
	 
	 always @(posedge clk)
		  if (uut.wb_we)
			 $display("WB: R%0d = %h", uut.wb_addr, uut.wb_data);

    // ---------- OPTIONAL: Watch some signals at simulation time 0 for quick sanity ----------
    initial begin
        #1;
        $display("Sanity check: top-level exposed signals:");
        $display(" thread_sel (example) = %0d", THREAD_SEL_REF);
        $display(" reset = %0d", rst);
    end

endmodule
