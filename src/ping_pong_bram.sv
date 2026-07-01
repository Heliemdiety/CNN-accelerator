`timescale 1ns / 1ps

module ping_pong_bram #(
    parameter int DATA_WIDTH = 32, // Matches packed rows
    parameter int ADDR_WIDTH = 10
)(
    input  logic                  clk,
    input  logic                  rst_n,
    
    // Control Interface
    input  logic                  swap, // Pulses high for 1 cycle to flip buffers
    
    // External Write Interface (From DMA/CPU)
    input  logic                  ext_we,
    input  logic [ADDR_WIDTH-1:0] ext_addr,
    input  logic [DATA_WIDTH-1:0] ext_din,
    
    // Internal Core Interface (To CNN Address Gen & Array)
    input  logic                  core_re,
    input  logic [ADDR_WIDTH-1:0] core_addr,
    output logic [DATA_WIDTH-1:0] core_dout
);

    // active_buffer == 0: Core reads RAM 0, Ext writes RAM 1
    // active_buffer == 1: Core reads RAM 1, Ext writes RAM 0
    logic active_buffer; 

    // The two physical memory arrays
    logic [DATA_WIDTH-1:0] ram_0 [0:(2**ADDR_WIDTH)-1];
    logic [DATA_WIDTH-1:0] ram_1 [0:(2**ADDR_WIDTH)-1];

    // Output registers for True BRAM inference (1 cycle read latency)
    logic [DATA_WIDTH-1:0] dout_0;
    logic [DATA_WIDTH-1:0] dout_1;

    // 1. Buffer Toggle Logic
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active_buffer <= 1'b0;
        end else if (swap) begin
            active_buffer <= ~active_buffer;
        end
    end

    // 2. RAM 0 Control Logic
    always_ff @(posedge clk) begin
        // If active_buffer is 1, External writes to RAM 0
        if (ext_we && active_buffer == 1'b1) begin
            ram_0[ext_addr] <= ext_din;
        end
        // If active_buffer is 0, Core reads from RAM 0
        if (core_re && active_buffer == 1'b0) begin
            dout_0 <= ram_0[core_addr];
        end
    end

    // 3. RAM 1 Control Logic
    always_ff @(posedge clk) begin
        // If active_buffer is 0, External writes to RAM 1
        if (ext_we && active_buffer == 1'b0) begin
            ram_1[ext_addr] <= ext_din;
        end
        // If active_buffer is 1, Core reads from RAM 1
        if (core_re && active_buffer == 1'b1) begin
            dout_1 <= ram_1[core_addr];
        end
    end

    // 4. Output Multiplexer
    assign core_dout = (active_buffer == 1'b0) ? dout_0 : dout_1;

endmodule