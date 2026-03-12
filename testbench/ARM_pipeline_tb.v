`timescale 1ns / 1ps

// Clean, self-contained testbench for ARM_pipeline
// - 100 MHz clock
// - Reset handling
// - Longer run time (adjust TIME_RUN if needed)
// - Monitors memory loads/stores
// - Dumps N words from DMEM at end using $fopen/$fwrite (portable)
// - Includes a behavioral dmem_64x256 for simulation convenience
//   (Remove the behavioral module if you prefer the vendor IP model.)

module ARM_pipeline_tb;

    // ---------- PARAMETERS ----------
    localparam TIME_RUN = 800000;               // simulation run time in ns (adjust)
    localparam [31:0] START_BYTE_ADDR = 32'h0104; // starting byte address of array to dump
    localparam integer NUM_DUMP_WORDS = 10;     // number of 64-bit words to dump

    // ---------- DUT SIGNALS / TB SCOPE DECLARATIONS ----------
    reg clk;
    reg rst;

    // module-scope integers (declared here to avoid in-block declaration errors)
    integer i;
    integer fd;
    integer idx;
    integer b;
    integer bb;
    integer start_word_index;

    // TB helper regs
    reg [7:0] tb_addra_word;
    reg [7:0] tb_wea_bus;

    // Instantiate DUT
    ARM_pipeline uut (
        .clk(clk),
        .rst(rst)
    );

    // ---------- CLOCK ----------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // ---------- TEST SEQUENCE ----------
    initial begin
        // initial reset
        rst = 1;
        #100;
        rst = 0;

        $display("=== Simulation started ===");
        $display("Running for %0d ns", TIME_RUN);

        // run CPU for TIME_RUN ns
        #(TIME_RUN);

        // compute start word index (byte address divided by 8)
        start_word_index = START_BYTE_ADDR >> 3;

        // Dump DMEM region using $fopen/$fwrite (portable)
        fd = $fopen("dmem_after_sim.hex", "w");
        if (fd == 0) begin
            $display("ERROR: could not open dmem_after_sim.hex for writing");
        end else begin
            $display("Dumping %0d words starting at byte addr 0x%h (word index %0d)",
                     NUM_DUMP_WORDS, START_BYTE_ADDR, start_word_index);
            for (idx = 0; idx < NUM_DUMP_WORDS; idx = idx + 1) begin
                // hierarchical read from the memory instance inside the DUT
                // This expects the instance inside the DUT to be named DataMem and to have 'mem' array
                $fwrite(fd, "%0d: 0x%016h\n", idx, uut.DataMem.mem[start_word_index + idx]);
                $display("%0d: 0x%016h (signed %0d)",
                         idx, uut.DataMem.mem[start_word_index + idx], $signed(uut.DataMem.mem[start_word_index + idx]));
            end
            $fclose(fd);
            $display("DMEM dump complete -> dmem_after_sim.hex");
        end

        #10;
        $finish;
    end

    // ---------- MEMORY MONITOR ----------
    initial begin
        $display("--- MEM MONITOR START ---");
        $display("time | thread | byte_addr | word_idx | wea_bus | dina (dec) | dina (hex)           | douta(hex)           | op");
    end

    always @(posedge clk) begin
        // compute word index and expected wea bus from DUT signals
        tb_addra_word = uut.mem_alu_res[10:3];
        tb_wea_bus    = {8{(uut.mem_mem_we && uut.mem_cond_passed)}};

        if (|tb_wea_bus) begin
            $display("%0t | %0d | 0x%0h | 0x%0h | 0x%0h | %0d | 0x%016h |      | write",
                     $time, uut.thread_sel, uut.mem_alu_res, tb_addra_word, tb_wea_bus,
                     $signed(uut.mem_store_data), uut.mem_store_data);
        end

        if (uut.mem_is_load && uut.mem_cond_passed) begin
            $display("%0t | %0d | 0x%0h | 0x%0h | 0x%0h |      |            | 0x%016h | read",
                     $time, uut.thread_sel, uut.mem_alu_res, tb_addra_word, tb_wea_bus, uut.mem_out_raw);
        end
    end

endmodule


// ------------------------------------------------------------------
// Behavioral replacement for dmem_64x256 (simulation-only)
// ------------------------------------------------------------------
module dmem_64x256(
    addra,
    addrb,
    clka,
    clkb,
    dina,
    dinb,
    douta,
    doutb,
    wea,
    web
);
    input  [7:0] addra;
    input  [7:0] addrb;
    input        clka;
    input        clkb;
    input  [63:0] dina;
    input  [63:0] dinb;
    output reg [63:0] douta;
    output reg [63:0] doutb;
    input  [7:0] wea;
    input  [7:0] web;

    reg [63:0] mem [0:255];

    integer i;
    integer b;
    integer bb;

    initial begin
        // Try to read a simple hex init first (create dmem_init.hex if you want)
        $display("behav_dmem: reading dmem_init.hex if present...");
        $readmemh("dmem_init.hex", mem);
        // Also try binary mif style as fallback (optional)
        $display("behav_dmem: reading dmem_64x256.mif (binary) if present...");
        $readmemb("dmem_64x256.mif", mem);

        for (i = 0; i < 10; i = i + 1) begin
            $display("behav_dmem: mem[%0d] = 0x%016h", i, mem[i]);
        end
    end

    always @(posedge clka) begin
        if (|wea) begin
            for (b = 0; b < 8; b = b + 1) begin
                if (wea[b]) mem[addra][8*b +: 8] <= dina[8*b +: 8];
            end
        end
        douta <= mem[addra];
    end

    always @(posedge clkb) begin
        if (|web) begin
            for (bb = 0; bb < 8; bb = bb + 1) begin
                if (web[bb]) mem[addrb][8*bb +: 8] <= dinb[8*bb +: 8];
            end
        end
        doutb <= mem[addrb];
    end

endmodule
