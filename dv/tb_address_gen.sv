`timescale 1ns / 1ps

module tb_address_gen();
    
    localparam ADDR_WIDTH = 8;

    logic                  clk;
    logic                  rst_n;
    logic                  start;
    logic [ADDR_WIDTH-1:0] burst_length;
    logic                  done;
    logic                  rd_en;
    logic [ADDR_WIDTH-1:0] rd_addr;

    int error_count = 0;

    // Instantiate DUT
    address_gen #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    // Clock Generation
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // The Transparent Checker
    // (No hidden clock delays. checks exactly when called.)
    // ---------------------------------------------------------
    task check_output(input logic exp_rd_en, input logic [ADDR_WIDTH-1:0] exp_addr);
        if (rd_en !== exp_rd_en || (rd_en && rd_addr !== exp_addr)) begin
            $error("FAIL at time %0t! Expected EN:%b ADDR:%0d | Got EN:%b ADDR:%0d", 
                    $time, exp_rd_en, exp_addr, rd_en, rd_addr);
            error_count++;
        end else if (rd_en) begin
            $display("PASS -> Read Addr: %0d", rd_addr);
        end
    endtask

    initial begin
        // 1. Reset
        clk = 0; rst_n = 0; start = 0; burst_length = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;
        
        // 2. Configure Burst 
        @(negedge clk);
        burst_length = 8'd5;
        start = 1;
        
        // 3. Verify the Wave (Cycle by Cycle)
        
        // Cycle 0
        @(negedge clk);
        start = 0; // Clear start signal
        check_output(1'b1, 8'd0);
        
        // Cycle 1
        @(negedge clk);
        check_output(1'b1, 8'd1);
        
        // Cycle 2
        @(negedge clk);
        check_output(1'b1, 8'd2);
        
        // Cycle 3
        @(negedge clk);
        check_output(1'b1, 8'd3);
        
        // Cycle 4
        @(negedge clk);
        check_output(1'b1, 8'd4);
        
        // 4. Verify DONE flag
        @(negedge clk);
        if (done !== 1'b1 || rd_en !== 1'b0) begin
            $error("FAIL! Done flag did not assert or rd_en stayed high.");
            error_count++;
        end else begin
            $display("PASS -> FSM cleanly asserted DONE and stopped reading.");
        end
        
        // 5. Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] ADDRESS GEN FSM PASSED ALL CHECKS! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] ADDRESS GEN FAILED %0d CHECKS! \n==============================================\n", error_count);

        $stop;
    end
endmodule