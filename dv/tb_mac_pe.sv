`timescale 1ns / 1ps

module tb_mac_pe();
    import cnn_pkg::*;

    logic    clk;
    logic    rst_n;
    logic    en;
    logic    setup_mode;
    act_t    i_act;
    weight_t i_weight;
    psum_t   i_psum;
    
    act_t    o_act;
    psum_t   o_psum;

    int error_count = 0;

    // Instantiate DUT
    mac_pe dut (.*);

    always #5 clk = ~clk;


    // The Automated Checker
    task check_output(input psum_t expected_psum);
        // Wait for the active positive edge to compute, then sample
        @(posedge clk); 
        #1; // Settle time
        if (o_psum !== expected_psum) begin
            $error("FAIL! Expected: %0d, Got: %0d at time %0t", expected_psum, o_psum, $time);
            error_count++;
        end else begin
            $display("PASS! Output perfectly matched: %0d", o_psum);
        end
    endtask

    initial begin
        // 1. System Reset
        clk = 0; rst_n = 0; en = 1; setup_mode = 0;
        i_act = 0; i_weight = 0; i_psum = 0;
        
        // Wait a few cycles, then release reset on a negative edge
        repeat(3) @(negedge clk);
        rst_n = 1;
        
        // 2. Setup Phase: Load Stationary Weight (W = 5)
        @(negedge clk);
        setup_mode = 1;
        i_weight = 8'd5;
        
        @(negedge clk);
        setup_mode = 0; // Turn off setup mode
        
        // 3. Compute Phase: Stream Inputs
        // Feed Cycle 1: Act = 2, incoming Psum = 100
        @(negedge clk);
        i_act  = 8'd2;   
        i_psum = 32'd100; 
        
        // Feed Cycle 2: Act = 3, incoming Psum = 200
        @(negedge clk);
        i_act  = 8'd3;   
        i_psum = 32'd200; 
        
        // Clear inputs on the next negative edge so we don't pollute the pipeline
        @(negedge clk);
        i_act  = 0;
        i_psum = 0;
        
        // 4. Verification Phase
        // The data takes 3 full clock cycles to traverse the pipeline.
        // Since we fed the first data, 2 cycles have passed. 
        // We need to wait for 1 more positive edge for the first result to pop out.
        
        check_output(32'd110); // Cycle 1 expected: 100 + (2*5)
        check_output(32'd215); // Cycle 2 expected: 200 + (3*5)
        
        // 5. Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] PE MODULE PASSED ALL CHECKS! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] PE MODULE FAILED %0d CHECKS! \n==============================================\n", error_count);

        $stop; 
    end
endmodule