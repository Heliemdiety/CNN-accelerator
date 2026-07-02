`timescale 1ns / 1ps

module dp_bram #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 10 // 1024 depth
)(
    input  logic                  clk,
    
    // PORT A (Write Port - Used for loading data)
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [DATA_WIDTH-1:0] din_a,
    output logic [DATA_WIDTH-1:0] dout_a,
    
    // PORT B (Read Port - Used by the Systolic Array)
    input  logic                  we_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [DATA_WIDTH-1:0] din_b,
    output logic [DATA_WIDTH-1:0] dout_b
);

    // The actual memory array
    //(* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(2ADDR_WIDTH)-1];
    //logic [DATA_WIDTH-1:0] ram [0:(2**ADDR_WIDTH)-1];
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Port A Logic
    always_ff @(posedge clk) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
            dout_a      <= din_a; // Write-first behavior
        end else begin
            dout_a      <= ram[addr_a];
        end
    end

    // Port B Logic
    always_ff @(posedge clk) begin
        if (we_b) begin
            ram[addr_b] <= din_b;
            dout_b      <= din_b;
        end else begin
            dout_b      <= ram[addr_b];
        end
    end

endmodule