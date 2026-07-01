`timescale 1ns / 1ps

module tb_ping_pong();

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 8;

    logic                  clk;
    logic                  rst_n;
    logic                  swap;
    
    logic                  ext_we;
    logic [ADDR_WIDTH-1:0] ext_addr;
    logic [DATA_WIDTH-1:0] ext_din;
    
    logic                  core_re;
    logic [ADDR_WIDTH-1:0] core_addr;
    logic [DATA_WIDTH-1:0] core_dout;

    int error_count = 0;

    // Instantiate DUT
    ping_pong_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    // Clock Gen
    always #5 clk = ~clk;

    // Check Task (Accounts for 1-cycle BRAM read latency)
    task check_read(input logic [DATA_WIDTH-1:0] expected_data);
        @(negedge clk); // Wait for the cycle AFTER the read request
        if (core_dout !== expected_data) begin
            $error("FAIL @%0t! Expected: %h, Got: %h", $time, expected_data, core_dout);
            error_count++;
        end else begin
            $display("PASS -> Core read matched: %h", core_dout);
        end
    endtask

    initial begin
        // Reset (active_buffer = 0 -> Core reads RAM 0, Ext writes RAM 1)
        clk = 0; rst_n = 0; swap = 0; 
        ext_we = 0; ext_addr = 0; ext_din = 0;
        core_re = 0; core_addr = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;

        // ---------------------------------------------------------
        // PHASE 1: Pre-fill RAM 0 so the Core has something to read
        // ---------------------------------------------------------
        $display("\n--- Phase 1: Pre-filling background RAM 1 ---");
        // Wait, active_buffer is 0! That means Ext writes to RAM 1, not 0.
        @(negedge clk); ext_we = 1; ext_addr = 8'h05; ext_din = 32'hAAAA_BBBB;
        @(negedge clk); ext_we = 0;

        // SWAP! (Now active_buffer = 1 -> Core reads RAM 1, Ext writes RAM 0)
        @(negedge clk); swap = 1; 
        @(negedge clk); swap = 0;

        // ---------------------------------------------------------
        // PHASE 2: Concurrent Read/Write
        // Core reads RAM 1 (AAAA_BBBB). AT THE SAME TIME, Ext fills RAM 0 (CCCC_DDDD)
        // ---------------------------------------------------------
        $display("\n--- Phase 2: Concurrent Read/Write ---");
        @(negedge clk);
        core_re   = 1; 
        core_addr = 8'h05; // Request read from RAM 1
        
        ext_we    = 1;
        ext_addr  = 8'h0A; // Request write to RAM 0
        ext_din   = 32'hCCCC_DDDD;

        // Clear signals
        @(negedge clk);
        core_re = 0; ext_we = 0;

        // Check the read from RAM 1
        // We are already 1 cycle past the read request, so the data should be ready right now.
        if (core_dout !== 32'hAAAA_BBBB) begin
            $error("FAIL! Core did not correctly read RAM 1. Got: %h", core_dout);
            error_count++;
        end else begin
            $display("PASS -> Core successfully read background buffer while DMA wrote.");
        end

        // ---------------------------------------------------------
        // PHASE 3: SWAP again and read the new data from RAM 0
        // ---------------------------------------------------------
        $display("\n--- Phase 3: Swap and verify RAM 0 ---");
        @(negedge clk); swap = 1; 
        @(negedge clk); swap = 0;

        @(negedge clk);
        core_re   = 1;
        core_addr = 8'h0A; // Read the CCCC_DDDD we just wrote

        @(negedge clk);
        core_re = 0;

        if (core_dout !== 32'hCCCC_DDDD) begin
            $error("FAIL! Core did not correctly read RAM 0 after swap. Got: %h", core_dout);
            error_count++;
        end else begin
            $display("PASS -> Ping-Pong Swap successful. Data is perfectly isolated.");
        end

        // Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] PING-PONG MEMORY IS FLAWLESS! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] PING-PONG MEMORY FAILED! \n==============================================\n");

        $stop;
    end
endmodule