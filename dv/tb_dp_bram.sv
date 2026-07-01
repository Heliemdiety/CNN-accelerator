`timescale 1ns / 1ps

module tb_dp_bram();
    
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4; // Tiny depth of 16 for fast simulation

    logic                  clk;
    
    logic                  we_a;
    logic [ADDR_WIDTH-1:0] addr_a;
    logic [DATA_WIDTH-1:0] din_a;
    logic [DATA_WIDTH-1:0] dout_a;
    
    logic                  we_b;
    logic [ADDR_WIDTH-1:0] addr_b;
    logic [DATA_WIDTH-1:0] din_b;
    logic [DATA_WIDTH-1:0] dout_b;

    int error_count = 0;
    logic test_complete = 0;

    // Instantiate DUT
    dp_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    // Clock Generation
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    //  MONITOR: Watch Port B for the correct read
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (test_complete) begin
            if (dout_b === 8'hAA) begin
                $display("\n==============================================\n  [SUCCESS] BRAM PORT B READ EXACTLY WHAT PORT A WROTE! \n==============================================\n");
                $stop;
            end else begin
                $display("\n==============================================\n  [FATAL] BRAM READ FAILED! Got: %h \n==============================================\n", dout_b);
                $stop;
            end
        end
    end

    // ---------------------------------------------------------
    // Stimulus Generation
    // ---------------------------------------------------------
    initial begin
        // Reset state
        clk = 0; 
        we_a = 0; addr_a = 0; din_a = 0;
        we_b = 0; addr_b = 0; din_b = 0;
        
        // Wait a few cycles
        repeat(3) @(negedge clk);
        
        // 1. Write Data to Port A
        @(negedge clk);
        we_a = 1;
        addr_a = 4'h5;
        din_a = 8'hAA;
        
        // 2. Stop Writing
        @(negedge clk);
        we_a = 0;
        
        // 3. Read from Port B (Same Address)
        @(negedge clk);
        addr_b = 4'h5;
        
        // 4. Trigger the monitor on the next clock cycle
        @(negedge clk);
        test_complete = 1;
        
        // Watchdog Timeout
        repeat(10) @(posedge clk);
        $display("TIMEOUT!");
        $stop;
    end
endmodule