`timescale 1ns / 1ps
// Complete ARM_pipeline.v - Quad-Threaded ZOMT ARM Core [cite: 184]

module ARM_pipeline (
    input clk,
    input rst 
);
	 
	 // Global Wire
	 reg ex_is_branch;
    reg [23:0] ex_branch_offset;
    wire [31:0] ex_branch_target;
    wire [31:0] signed_branch_offset;
	 
    // =========================================================================
    // THREAD SCHEDULER: 2-bit Round-Robin
    // =========================================================================
    reg [1:0] thread_sel;
    reg [1:0] id_tid, ex_tid, mem_tid, wb_tid;

    always @(posedge clk) begin
        if (rst) begin
            {thread_sel, id_tid, ex_tid, mem_tid, wb_tid} <= 10'b0;
        end else begin
            thread_sel <= thread_sel + 1;  // Cycles 00, 01, 10, 11 [cite: 187]
            id_tid     <= thread_sel;
            ex_tid     <= id_tid;
            mem_tid    <= ex_tid;
            wb_tid     <= mem_tid;
        end
    end

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    reg [31:0] pc [3:0]; 
    wire [31:0] curr_pc = pc[thread_sel];
    wire [31:0] if_instr;

    always @(posedge clk) begin
        if (rst) begin
            pc[0] <= 32'h000; 
            pc[1] <= 32'h400; 
            pc[2] <= 32'h800; 
            pc[3] <= 32'hC00;

            thread_sel <= 0;
            
        end else begin
            if (ex_is_branch && cond_passed) begin
                pc[ex_tid] <= ex_branch_target;
            end 
            else if (curr_pc[9:0] < 10'h114) begin
                pc[thread_sel] <= pc[thread_sel] + 4;
            end
            
            // thread_sel is ONLY incremented in this single block
            thread_sel <= thread_sel + 1;
        end
    end

    imem_32x512 InstrMem (
        .clk(clk),
        .addr(curr_pc[10:2]), // Word addressing
		  .din (32'b0),
		  .we(1'b0),
        .dout(if_instr)
    );

    // IF/ID Pipeline Register (Replicated for 4 threads)
    reg [31:0] id_instr [3:0];
    always @(posedge clk) begin
        id_instr[thread_sel] <= if_instr;
    end

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    wire [31:0] active_id_instr = id_instr[id_tid];
    
    // Writeback signals (from WB stage)
    wire wb_we;
    wire [3:0] wb_addr;
    wire [63:0] wb_data;

    // RegFile outputs arrays
    wire [63:0] id_r0 [3:0];
    wire [63:0] id_r1 [3:0];
	 
	 wire is_store = (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b0);
    wire [3:0] r1_addr_mux = is_store ? active_id_instr[15:12] : active_id_instr[3:0];
    wire [3:0] r0_addr_mux = active_id_instr[19:16];

    // Generate 4 RegFiles for 4 Threads 
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : REG_FILES
            reg_file RF (
                .clk(clk), .rst(rst),
                .wena(wb_we && (wb_tid == i)), 
                .waddr(wb_addr),
                .wdata(wb_data),
                .r0addr(r0_addr_mux), 
                .r1addr(r1_addr_mux),
                .r0data(id_r0[i]),
                .r1data(id_r1[i])
            );
        end
    endgenerate
	 
    // Select the operands for the thread currently in the ID stage
    wire [63:0] id_op1 = id_r0[id_tid];
    wire [63:0] id_op2 = id_r1[id_tid];

    // ID/EX Pipeline Register
    reg [3:0] ex_cond;
    reg [63:0] ex_op1, ex_op2;
    reg [3:0] ex_aluctrl;
    reg ex_we, ex_mem_we;
    reg [3:0] ex_waddr;
    reg [63:0] ex_imm;
    reg ex_use_imm; // NEW: Tells ALU to use immediate
    reg ex_is_load; // NEW: Tells WB to use memory data

    always @(posedge clk) begin
        if (rst) begin
            {ex_cond, ex_op1, ex_op2, ex_imm, ex_aluctrl, ex_we, ex_mem_we, ex_waddr, ex_use_imm, ex_is_load} <= 0;
				ex_is_branch     <= 1'b0;
            ex_branch_offset <= 24'd0;
        end else begin
            ex_cond    <= active_id_instr[31:28];
            ex_op1     <= id_op1;
            ex_op2     <= id_op2;
            ex_imm     <= {{52{active_id_instr[11]}}, active_id_instr[11:0]}; // Sign-extend
            
            // Generate pipeline control signals from the CURRENT ID instruction
            ex_use_imm <= (active_id_instr[27:26] == 2'b01) || (active_id_instr[27:26] == 2'b00 && active_id_instr[25] == 1'b1);
            ex_is_load <= (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b1);

            case (active_id_instr[24:21])
                4'b0100: ex_aluctrl <= 4'b0000; // ADD
                4'b0010: ex_aluctrl <= 4'b0001; // SUB
                4'b1010: ex_aluctrl <= 4'b0101; // CMP
                default: ex_aluctrl <= 4'b0000;
            endcase
            
            ex_we      <= (active_id_instr[27:26] == 2'b00) || 
                          (active_id_instr[27:26] == 2'b01 && active_id_instr[20] == 1'b1);
            ex_mem_we  <= (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b0);
            ex_waddr   <= active_id_instr[15:12];
				
				ex_is_branch     <= (active_id_instr[27:26] == 2'b10);
            ex_branch_offset <= active_id_instr[23:0];
        end
    end

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    reg [3:0] cpsr [3:0]; // Replicated CPSR {N, Z, C, V} for 4 threads 
    wire [3:0] curr_flags = cpsr[ex_tid];
    
    wire cond_passed;
    Condition_Check CondUnit (
        .cond(ex_cond),
        .flags(curr_flags),
        .passed(cond_passed)
    );

    wire [63:0] alu_res;
    wire alu_ovf;
    
	 // Instantiate your Lab 5 ALU
	 wire [63:0] alu_input_b = ex_use_imm ? ex_imm : ex_op2;
	
	 // Branch Target Calculation (Using ASSIGN instead of WIRE)
    // Extract the 24-bit offset, sign-extend it, and multiply by 4 (shift left by 2)
    assign signed_branch_offset = {{6{ex_branch_offset[23]}}, ex_branch_offset, 2'b00};
    
    // Target = (PC + 4) + 4 + Offset = PC + 8 + Offset
    assign ex_branch_target = pc[ex_tid] + 4 + signed_branch_offset;
	 
    ALU_64bit MainALU (
        .clk(clk), .rst(rst),
        .A(ex_op1), 
        .B(alu_input_b), // Use the muxed input here!
        .aluctrl(ex_aluctrl),
        .Z(alu_res), .overflow(alu_ovf)
    );

    // Update CPSR (Only updates if condition passes and it's an ALU op)
    always @(posedge clk) begin
        if (rst) begin
            cpsr[0] <= 4'b0; cpsr[1] <= 4'b0; cpsr[2] <= 4'b0; cpsr[3] <= 4'b0;
        end else if (cond_passed) begin
            // {N, Z, C, V}
            cpsr[ex_tid] <= {alu_res[63], (alu_res == 0), 1'b0, alu_ovf};
        end
    end

    // EX/MEM Register
    reg [63:0] mem_alu_res, mem_store_data;
    reg mem_we, mem_mem_we, mem_cond_passed, mem_is_load; // Added mem_is_load
    reg [3:0] mem_waddr;

    always @(posedge clk) begin
        if (rst) begin
            {mem_alu_res, mem_store_data, mem_we, mem_mem_we, mem_waddr, mem_cond_passed, mem_is_load} <= 0;
        end else begin
            mem_alu_res     <= alu_res;
            mem_store_data  <= ex_op2;
            mem_we          <= ex_we;
            mem_mem_we      <= ex_mem_we;
            mem_waddr       <= ex_waddr;
            mem_cond_passed <= cond_passed;
            mem_is_load     <= ex_is_load; // Pass it down
        end
    end
	 
    // =========================================================================
    // STAGE 4: MEMORY (MEM)
    // =========================================================================
    wire [63:0] mem_out_raw;
    wire actual_mem_write = mem_mem_we && mem_cond_passed;
    
    // Address for 64-bit BRAM (8-byte chunks)
    wire [7:0] addra_word = mem_alu_res[10:3];
    
    // 8-bit Byte Enable mask based on bit [2] (the 4-byte offset)
    wire [7:0] wea_mask = mem_alu_res[2] ? 8'hF0 : 8'h0F;
    //wire [7:0] wea_bus = (mem_mem_we && mem_cond_passed) ? (mem_alu_res[2] ? 8'hF0 : 8'h0F) : 8'h00;

    wire [63:0] aligned_store_data = mem_alu_res[2] ? {mem_store_data[31:0], 32'd0} : {32'd0, mem_store_data[31:0]};
	 
    dmem_64x256 DataMem (
        .clka(clk),
        .wea(actual_mem_write),
        .addra(mem_alu_res[9:2]),
        .dina(aligned_store_data),
        .douta(mem_out_raw),
        .clkb(),
        .web(),
        .addrb(),
        .dinb(),
        .doutb()
    );

    // --- MEM/WB Pipeline Registers ---
    reg [31:0] wb_alu_res_reg;   // Changed to 32-bit
    reg [63:0] wb_mem_data_reg;  // Stays 64-bit to hold both words
    reg [3:0]  wb_waddr_reg;     // ARM uses 4-bit register addresses (0-15)
    reg        wb_we_reg, wb_cond_passed_reg, wb_is_load_reg;

    always @(posedge clk) begin
        if (rst) begin
            wb_alu_res_reg     <= 0;
            wb_mem_data_reg    <= 0;
            wb_we_reg          <= 0;
            wb_waddr_reg       <= 0;
            wb_cond_passed_reg <= 0;
            wb_is_load_reg     <= 0;
        end else begin
            wb_alu_res_reg     <= mem_alu_res;
            wb_mem_data_reg    <= mem_out_raw; // Pass the raw 64-bit line
            wb_we_reg          <= mem_we;
            wb_waddr_reg       <= mem_waddr;
            wb_cond_passed_reg <= mem_cond_passed;
            wb_is_load_reg     <= mem_is_load;
        end
    end

    // =========================================================================
    // STAGE 5: WRITE BACK (WB)
    // =========================================================================

    assign wb_we   = wb_we_reg && wb_cond_passed_reg;
    assign wb_addr = wb_waddr_reg;

    wire [31:0] extracted_32bit = wb_alu_res_reg[2] ? mem_out_raw[63:32] : mem_out_raw[31:0];

    assign wb_data = wb_is_load_reg ? {32'd0, extracted_32bit} : wb_alu_res_reg;
	 
endmodule
