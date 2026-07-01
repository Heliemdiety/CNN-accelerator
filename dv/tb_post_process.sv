`timescale 1ns / 1ps

module tb_post_process();
    import cnn_pkg::*;

    logic        clk;
    logic        rst_n;
    logic        en;
    
    psum_t       i_psum;
    psum_t       i_bias;
    logic [4:0]  i_shift;
    
    act_t        o_act;

    int error_count = 0;

    // Instantiate DUT
    cnn_post_process dut (.*);

    // Clock Generation
    always #5 clk = ~clk;

    // Transparent Checker Task
    task check_output(input string test_name, input act_t expected_act);
        if (o_act !== expected_act) begin
            $error("FAIL [%s] at time %0t! Expected: %0d | Got: %0d", 
                    test_name, $time, expected_act, o_act);
            error_count++;
        end else begin
            $display("PASS [%s] -> Output perfectly clamped to: %0d", test_name, o_act);
        end
    endtask

    initial begin
        // 1. Reset
        clk = 0; rst_n = 0; en = 1; 
        i_psum = 0; i_bias = 0; i_shift = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;
        
        // --- Test 1: Normal Operation (No Saturation) ---
        @(negedge clk);
        i_psum  = 32'd50;
        i_bias  = 32'd14;
        i_shift = 5'd1; // Shift right by 1 (Divide by 2)
        // Math: (50 + 14) / 2 = 32. 
        
        // Wait 2 clock cycles for the 2-stage pipeline
        repeat(2) @(negedge clk);
        check_output("Normal Math", 8'd32);
        
        // --- Test 2: ReLU Cutoff (Negative Input) ---
        @(negedge clk);
        i_psum  = -32'd100;
        i_bias  = 32'd10;
        i_shift = 5'd0; 
        // Math: (-100 + 10) = -90. ReLU should crush this to 0.
        
        repeat(2) @(negedge clk);
        check_output("ReLU Cutoff", 8'd0);
        
        // --- Test 3: Saturation Overflow (Massive Input) ---
        @(negedge clk);
        i_psum  = 32'd5000;
        i_bias  = 32'd1000;
        i_shift = 5'd0; // No shift
        // Math: (5000 + 1000) = 6000. 
        // 6000 cannot fit in an 8-bit signed int (max 127). It must clamp to 127.
        
        repeat(2) @(negedge clk);
        check_output("Saturation Guard", 8'd127);
        
        // Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] POST-PROCESSOR PASSED ALL CHECKS! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] POST-PROCESSOR FAILED %0d CHECKS! \n==============================================\n", error_count);

        $stop;
    end
endmodule