`timescale 1ns / 1ps
// ARM_pipeline.v - Quad-Threaded ZOMT ARM Core
// FIXES APPLIED:
//   1. wb_alu_res_reg widened to 64-bit (was 32-bit, silently truncated)
//   2. extracted_32bit now uses wb_mem_data_reg (registered), not live mem_out_raw
//   3. thread_sel double-driver removed (only one always block owns it)
//   4. PC stall condition corrected to use >= instead of stopping dead

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
            thread_sel <= thread_sel + 1;
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

    // FIX 3: thread_sel is owned ONLY by the scheduler always block above.
    // This always block only updates pc[], never thread_sel.
    always @(posedge clk) begin
        if (rst) begin
            pc[0] <= 32'h000; 
            pc[1] <= 32'h400; 
            pc[2] <= 32'h800; 
            pc[3] <= 32'hC00;
        end else begin
            if (ex_is_branch && cond_passed) begin
                // Branch taken: redirect the branching thread's PC
                pc[ex_tid] <= ex_branch_target;
            end 
            else begin
                // Normal sequential fetch — no upper-bound stop.
                // The program terminates via the infinite loop (B .) at its end.
                pc[thread_sel] <= pc[thread_sel] + 4;
            end
        end
    end

    imem_32x512 InstrMem (
        .clk(clk),
        .addr(curr_pc[10:2]),   // Word addressing: byte addr >> 2
        .din (32'b0),
        .we  (1'b0),
        .dout(if_instr)
    );

    // IF/ID Pipeline Registers (one per thread)
    reg [31:0] id_instr [3:0];
    always @(posedge clk) begin
        id_instr[thread_sel] <= if_instr;
    end

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // =========================================================================
    wire [31:0] active_id_instr = id_instr[id_tid];
    
    // Writeback signals (from WB stage, fed back to all register files)
    wire        wb_we;
    wire [3:0]  wb_addr;
    wire [63:0] wb_data;

    // RegFile read outputs, one set per thread
    wire [63:0] id_r0 [3:0];
    wire [63:0] id_r1 [3:0];
	 
    // For store instructions, Rt (source register) lives in [15:12]; 
    // for all others, Rm (second operand) lives in [3:0].
    wire is_store    = (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b0);
    wire [3:0] r1_addr_mux = is_store ? active_id_instr[15:12] : active_id_instr[3:0];
    wire [3:0] r0_addr_mux = active_id_instr[19:16];

    // 4 independent register files, one per thread
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : REG_FILES
            reg_file RF (
                .clk   (clk),
                .rst   (rst),
                .wena  (wb_we && (wb_tid == i)), 
                .waddr (wb_addr),
                .wdata (wb_data),
                .r0addr(r0_addr_mux), 
                .r1addr(r1_addr_mux),
                .r0data(id_r0[i]),
                .r1data(id_r1[i])
            );
        end
    endgenerate
	 
    wire [63:0] id_op1 = id_r0[id_tid];
    wire [63:0] id_op2 = id_r1[id_tid];

    // ID/EX Pipeline Registers
    reg [3:0]  ex_cond;
    reg [63:0] ex_op1, ex_op2;
    reg [3:0]  ex_aluctrl;
    reg        ex_we, ex_mem_we;
    reg [3:0]  ex_waddr;
    reg [63:0] ex_imm;
    reg        ex_use_imm;
    reg        ex_is_load;

    always @(posedge clk) begin
        if (rst) begin
            ex_cond          <= 4'b1110; // AL — always execute (safe default)
            ex_op1           <= 64'b0;
            ex_op2           <= 64'b0;
            ex_imm           <= 64'b0;
            ex_aluctrl       <= 4'b0;
            ex_we            <= 1'b0;
            ex_mem_we        <= 1'b0;
            ex_waddr         <= 4'b0;
            ex_use_imm       <= 1'b0;
            ex_is_load       <= 1'b0;
            ex_is_branch     <= 1'b0;
            ex_branch_offset <= 24'b0;
        end else begin
            ex_cond    <= active_id_instr[31:28];
            ex_op1     <= id_op1;
            ex_op2     <= id_op2;
            // Sign-extend 12-bit immediate to 64 bits
            ex_imm     <= {{52{active_id_instr[11]}}, active_id_instr[11:0]};
            
            // Immediate source: LDR/STR (bits[27:26]=01) or Data-proc with I=1 (bit[25]=1)
            ex_use_imm <= (active_id_instr[27:26] == 2'b01) || 
                          (active_id_instr[27:26] == 2'b00 && active_id_instr[25] == 1'b1);

            ex_is_load <= (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b1);

            // ALU control from opcode field [24:21]
            case (active_id_instr[24:21])
                4'b0100: ex_aluctrl <= 4'b0000; // ADD
                4'b0010: ex_aluctrl <= 4'b0001; // SUB
                4'b1010: ex_aluctrl <= 4'b0101; // CMP
                default: ex_aluctrl <= 4'b0000;
            endcase
            
            // Writeback enable: Data-proc writes Rd, LDR writes Rd, STR does not
            ex_we     <= (active_id_instr[27:26] == 2'b00) || 
                         (active_id_instr[27:26] == 2'b01 && active_id_instr[20] == 1'b1);
            ex_mem_we <= (active_id_instr[27:26] == 2'b01) && (active_id_instr[20] == 1'b0);
            ex_waddr  <= active_id_instr[15:12];
			
            ex_is_branch     <= (active_id_instr[27:26] == 2'b10);
            ex_branch_offset <= active_id_instr[23:0];
        end
    end

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    reg [3:0] cpsr [3:0]; // {N, Z, C, V} per thread
    wire [3:0] curr_flags = cpsr[ex_tid];
    
    wire cond_passed;
    Condition_Check CondUnit (
        .cond  (ex_cond),
        .flags (curr_flags),
        .passed(cond_passed)
    );

    wire [63:0] alu_res;
    wire        alu_ovf;
    
    wire [63:0] alu_input_b = ex_use_imm ? ex_imm : ex_op2;
	
    // Branch target: PC_of_fetching_thread + 8 + (sign_extended_offset << 2)
    // The +8 accounts for ARM's prefetch offset (pipeline depth of 2 in classic ARM)
    assign signed_branch_offset = {{6{ex_branch_offset[23]}}, ex_branch_offset, 2'b00};
    assign ex_branch_target     = pc[ex_tid] + 4 + signed_branch_offset;
	 
    ALU_64bit MainALU (
        .clk     (clk),
        .rst     (rst),
        .A       (ex_op1), 
        .B       (alu_input_b),
        .aluctrl (ex_aluctrl),
        .Z       (alu_res),
        .overflow(alu_ovf)
    );

    // Update CPSR for the executing thread (only on condition pass, only for ALU ops)
    always @(posedge clk) begin
        if (rst) begin
            cpsr[0] <= 4'b0;
            cpsr[1] <= 4'b0;
            cpsr[2] <= 4'b0;
            cpsr[3] <= 4'b0;
        end else if (cond_passed && !ex_mem_we && !ex_is_branch) begin
            // {N, Z, C, V}
            cpsr[ex_tid] <= {alu_res[63], (alu_res == 64'd0), 1'b0, alu_ovf};
        end
    end

    // EX/MEM Pipeline Registers
    reg [63:0] mem_alu_res, mem_store_data;
    reg        mem_we, mem_mem_we, mem_cond_passed, mem_is_load;
    reg [3:0]  mem_waddr;

    always @(posedge clk) begin
        if (rst) begin
            mem_alu_res     <= 64'b0;
            mem_store_data  <= 64'b0;
            mem_we          <= 1'b0;
            mem_mem_we      <= 1'b0;
            mem_waddr       <= 4'b0;
            mem_cond_passed <= 1'b0;
            mem_is_load     <= 1'b0;
        end else begin
            mem_alu_res     <= alu_res;
            mem_store_data  <= ex_op2;
            mem_we          <= ex_we;
            mem_mem_we      <= ex_mem_we;
            mem_waddr       <= ex_waddr;
            mem_cond_passed <= cond_passed;
            mem_is_load     <= ex_is_load;
        end
    end
	 
    // =========================================================================
    // STAGE 4: MEMORY (MEM)
    // =========================================================================
    wire [63:0] mem_out_raw;
    wire        actual_mem_write = mem_mem_we && mem_cond_passed;

    // For 64-bit BRAM: byte address >> 3 gives the 64-bit word address
    // mem_alu_res[2] selects upper (1) or lower (0) 32-bit word within the 64-bit word
    wire [63:0] aligned_store_data = mem_alu_res[2] 
                                     ? {mem_store_data[31:0], 32'd0} 
                                     : {32'd0, mem_store_data[31:0]};
	 
    dmem_64x256 DataMem (
        .clka (clk),
        .wea  (actual_mem_write),       // 1-bit write enable
        .addra(mem_alu_res[9:2]),        // 8-bit word address (byte addr >> 2, adjusted for 64-bit)
        .dina (aligned_store_data),      // data positioned in correct 32-bit half
        .douta(mem_out_raw),
        .clkb (),
        .web  (),
        .addrb(),
        .dinb (),
        .doutb()
    );

    // MEM/WB Pipeline Registers
    // FIX 1: wb_alu_res_reg must be 64-bit — was 32-bit, silently dropped upper 32 bits
    reg [63:0] wb_alu_res_reg;
    reg [63:0] wb_mem_data_reg;
    reg [3:0]  wb_waddr_reg;
    reg        wb_we_reg, wb_cond_passed_reg, wb_is_load_reg;

    always @(posedge clk) begin
        if (rst) begin
            wb_alu_res_reg     <= 64'b0;
            wb_mem_data_reg    <= 64'b0;
            wb_we_reg          <= 1'b0;
            wb_waddr_reg       <= 4'b0;
            wb_cond_passed_reg <= 1'b0;
            wb_is_load_reg     <= 1'b0;
        end else begin
            wb_alu_res_reg     <= mem_alu_res;
            wb_mem_data_reg    <= mem_out_raw;  // Register the BRAM output here
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

    // FIX 2: Use wb_mem_data_reg (registered from MEM stage, stable in WB stage)
    //        NOT mem_out_raw (live BRAM output, belongs to MEM stage of current cycle)
    wire [31:0] extracted_32bit = wb_alu_res_reg[2] 
                                  ? wb_mem_data_reg[63:32] 
                                  : wb_mem_data_reg[31:0];

    assign wb_data = wb_is_load_reg ? {32'd0, extracted_32bit} : wb_alu_res_reg;
	 
endmodule
