`timescale 1ns / 1ps

module layer_sequencer #(
    parameter int MAX_INSTRUCTIONS = 64
)(
    input  logic        clk,
    input  logic        rst_n,

    // High-level triggers (keeping the  RV32I CPU integration in mind )
    input  logic        seq_start,
    output logic        seq_done,

    // Hardware Feedback (From the CNN Core)
    input  logic        core_done,

    // CSR Master Interface (Drives the dashboard we built in Phase 7)
    output logic        csr_wr_en,
    output logic [7:0]  csr_wr_addr,
    output logic [31:0] csr_wr_data
);

    // Microcode format: {8-bit Command/Addr, 32-bit Data}
    logic [39:0] microcode_rom [0:MAX_INSTRUCTIONS-1];

    // Initialize ROM ("Compiled" Neural Network)
    initial begin
        // Normally: $readmemh("compiled_network.hex", microcode_rom);
        
        // --- Layer 1 Configuration ---
        microcode_rom[0] = {8'h08, 32'h8000_1000}; // Set ACT_BASE
        microcode_rom[1] = {8'h0C, 32'h8000_2000}; // Set WT_BASE
        microcode_rom[2] = {8'h10, 32'h8000_3000}; // Set OUT_BASE
        microcode_rom[3] = {8'h14, 32'h0037_0003}; // Set Quant (Bias=55, Shift=3)
        microcode_rom[4] = {8'hAA, 32'h0000_0000}; // CMD 0xAA: TRIGGER CORE & WAIT
        
        // --- Layer 2 Configuration (Reads Layer 1's output) ---
        microcode_rom[5] = {8'h08, 32'h8000_3000}; // New Act Base = Old Out Base
        microcode_rom[6] = {8'h0C, 32'h8000_4000}; // New Weights
        microcode_rom[7] = {8'h10, 32'h8000_5000}; // Final Output
        microcode_rom[8] = {8'h14, 32'h0010_0001}; // New Quant (Bias=16, Shift=1)
        microcode_rom[9] = {8'hAA, 32'h0000_0000}; // CMD 0xAA: TRIGGER CORE & WAIT
        
        // --- End of Network ---
        microcode_rom[10] = {8'hFF, 32'h0000_0000}; // CMD 0xFF: HALT
    end

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        FETCH     = 3'b001,
        DECODE    = 3'b010,
        WRITE_CSR = 3'b011,
        WAIT_CORE = 3'b100,
        DONE      = 3'b101
    } state_t;

    state_t state, next_state;
    logic [7:0] pc, next_pc; 
    logic [39:0] instruction;

    // FSM State & Program Counter Register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            pc    <= '0;
        end else begin
            state <= next_state;
            pc    <= next_pc;
        end
    end

    // Instruction Fetch
    assign instruction = microcode_rom[pc];

    // FSM Next State Logic
    always_comb begin
        next_state = state;
        next_pc    = pc;

        case (state)
            IDLE: begin
                if (seq_start) next_state = FETCH;
            end
            FETCH: begin
                next_state = DECODE;
            end
            DECODE: begin
                if (instruction[39:32] == 8'hFF) begin
                    next_state = DONE;      // HALT command
                end else if (instruction[39:32] == 8'hAA) begin
                    next_state = WAIT_CORE; // TRIGGER command
                end else begin
                    next_state = WRITE_CSR; // Normal register write
                end
            end
            WRITE_CSR: begin
                next_pc = pc + 1'b1;
                next_state = FETCH;
            end
            WAIT_CORE: begin
                if (core_done) begin
                    next_pc = pc + 1'b1;
                    next_state = FETCH;
                end
            end
            DONE: begin
                next_state = IDLE; 
                next_pc    = '0; // Auto-reset PC for the next inference
            end
            default: next_state = IDLE;
        endcase
    end

    // Datapath (Glitch-free registered outputs)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            csr_wr_en   <= 1'b0;
            csr_wr_addr <= '0;
            csr_wr_data <= '0;
            seq_done    <= 1'b0;
        end else begin
            // Defaults
            csr_wr_en <= 1'b0;
            seq_done  <= 1'b0;

            case (next_state)
                WRITE_CSR: begin
                    csr_wr_en   <= 1'b1;
                    csr_wr_addr <= instruction[39:32];
                    csr_wr_data <= instruction[31:0];
                end
                WAIT_CORE: begin
                    // Pulse the start register (Addr 0x00) for exactly 1 cycle 
                    // upon entering the WAIT_CORE state
                    if (state == DECODE) begin
                        csr_wr_en   <= 1'b1;
                        csr_wr_addr <= 8'h00;
                        csr_wr_data <= 32'h0000_0001;
                    end
                end
                DONE: begin
                    seq_done <= 1'b1;
                end
                default: ; // IDLE, FETCH, DECODE do not assert write enables
            endcase
        end
    end

endmodule