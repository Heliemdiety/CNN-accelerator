`timescale 1ns / 1ps

module tb_cnn_csr();

    logic        clk;
    logic        rst_n;

    logic        wr_en;
    logic [7:0]  wr_addr;
    logic [31:0] wr_data;
    
    logic        rd_en;
    logic [7:0]  rd_addr;
    logic [31:0] rd_data;

    logic        core_start;
    logic        core_soft_rst;
    logic [31:0] act_base_ptr;
    logic [31:0] wt_base_ptr;
    logic [31:0] out_base_ptr;
    logic [31:0] bias_val;
    logic [4:0]  shift_val;
    
    logic        core_done;
    logic        core_busy;

    int error_count = 0;

    // Instantiate DUT
    cnn_csr dut (.*);

    // Clock Gen
    always #5 clk = ~clk;

    // CPU Write Task
    task cpu_write(input logic [7:0] addr, input logic [31:0] data);
        @(negedge clk);
        wr_en   = 1;
        wr_addr = addr;
        wr_data = data;
        @(negedge clk);
        wr_en   = 0;
    endtask

    // CPU Read & Check Task
    task cpu_read_check(input logic [7:0] addr, input logic [31:0] exp_data, input string reg_name);
        @(negedge clk);
        rd_en   = 1;
        rd_addr = addr;
        #1; // Tiny combinational settle time
        if (rd_data !== exp_data) begin
            $error("FAIL [%s]! Exp: %h, Got: %h", reg_name, exp_data, rd_data);
            error_count++;
        end else begin
            $display("PASS [%s] -> Read matched: %h", reg_name, rd_data);
        end
        @(negedge clk);
        rd_en = 0;
    endtask

    initial begin
        // Reset
        clk = 0; rst_n = 0; wr_en = 0; rd_en = 0;
        core_done = 0; core_busy = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;

        // 1. CPU Configures Pointers (Mimicking DDR4 Addresses)
        cpu_write(8'h08, 32'h8000_1000); // Act Pointer
        cpu_write(8'h0C, 32'h8000_2000); // Wt Pointer
        cpu_write(8'h14, {16'd55, 11'd0, 5'd3}); // Bias = 55, Shift = 3
        
        // 2. CPU Reads back to verify
        cpu_read_check(8'h08, 32'h8000_1000, "ACT_BASE");
        cpu_read_check(8'h14, {16'd55, 11'd0, 5'd3}, "QUANT_CFG");
        
        // Verify Hardware output ports are actively driven
        if (bias_val !== 32'd55 || shift_val !== 5'd3) begin
            $error("FAIL [HW Wires]! Bias or Shift did not propagate.");
            error_count++;
        end

        // 3. Hardware asserts BUSY
        @(negedge clk);
        core_busy = 1;
        cpu_read_check(8'h04, 32'h0000_0002, "STATUS_BUSY");

        // 4. CPU hits START
        cpu_write(8'h00, 32'h0000_0001);
        
        // Verify Start wire pulsed high
        
        if (core_start !== 1'b1) begin
            $error("FAIL [Start Trigger]! core_start did not pulse.");
            error_count++;
        end
        
        // Verify self-clearing mechanism
        @(negedge clk);
        if (core_start !== 1'b0) begin
            $error("FAIL [Start Clear]! core_start did not self-clear.");
            error_count++;
        end

        // Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] CSR DASHBOARD FULLY OPERATIONAL! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] CSR FAILED %0d CHECKS! \n==============================================\n", error_count);

        $stop;
    end
endmodule