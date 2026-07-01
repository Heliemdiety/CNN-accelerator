`timescale 1ns / 1ps

module tb_cnn_sys_ctrl();

    // Small pipeline depth for fast simulation
    localparam int PIPELINE_DEPTH = 3; 

    logic clk;
    logic rst_n;
    logic start;
    logic sys_done;
    logic array_en;
    logic setup_mode;
    logic start_act_read;
    logic act_read_done;

    int error_count = 0;

    // Instantiate DUT
    cnn_sys_ctrl #(
        .PIPELINE_DEPTH(PIPELINE_DEPTH)
    ) dut (.*);

    // Clock Generation
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // The Transparent Checker
    // Samples safely on the negedge, no hidden delays.
    // ---------------------------------------------------------
    task check_state(
        input string state_name,
        input logic exp_array_en,
        input logic exp_setup_mode,
        input logic exp_start_act,
        input logic exp_sys_done
    );
        if (array_en !== exp_array_en || setup_mode !== exp_setup_mode || 
            start_act_read !== exp_start_act || sys_done !== exp_sys_done) begin
            
            $error("FAIL [%s] @%0t | Expected EN:%b SETUP:%b START_RD:%b DONE:%b | Got EN:%b SETUP:%b START_RD:%b DONE:%b", 
                    state_name, $time, exp_array_en, exp_setup_mode, exp_start_act, exp_sys_done,
                    array_en, setup_mode, start_act_read, sys_done);
            error_count++;
        end else begin
            $display("PASS [%s] -> Outputs perfectly matched.", state_name);
        end
    endtask

    initial begin
        // 1. Reset
        clk = 0; rst_n = 0; start = 0; act_read_done = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;
        
        // --- Verify IDLE ---
        @(negedge clk);
        check_state("IDLE", 1'b0, 1'b0, 1'b0, 1'b0);
        
        // 2. Trigger FSM Start
        @(negedge clk);
        start = 1;
        
        // --- Verify SETUP ---
        // State updates on posedge, we check on the next negedge.
        @(negedge clk);
        start = 0; // Clear start trigger
        check_state("SETUP", 1'b1, 1'b1, 1'b0, 1'b0); // Array should be enabled, setup mode ON
        
        // --- Verify COMPUTE (Pulse check) ---
        // On entry to COMPUTE, start_act_read should pulse HIGH for exactly 1 cycle.
        @(negedge clk);
        check_state("COMPUTE (Pulse High)", 1'b1, 1'b0, 1'b1, 1'b0); 
        
        // Verify pulse drops on the next cycle, but we stay in COMPUTE
        @(negedge clk);
        check_state("COMPUTE (Pulse Low)", 1'b1, 1'b0, 1'b0, 1'b0); 
        
        // 3. Trigger Address Generator Done
        @(negedge clk);
        act_read_done = 1;
        
        // --- Verify DRAIN ---
        @(negedge clk);
        act_read_done = 0; // Clear trigger
        check_state("DRAIN (Cycle 1)", 1'b1, 1'b0, 1'b0, 1'b0); // Array stays ON to flush data
        
        // Wait out the rest of the pipeline depth (PIPELINE_DEPTH = 3, we used 1, wait 2 more)
        repeat(PIPELINE_DEPTH - 1) @(negedge clk);
        
        // --- Verify DONE ---
        // FSM should automatically transition to DONE after the timer expires
        @(negedge clk);
        check_state("DONE", 1'b0, 1'b0, 1'b0, 1'b1); // Array turns off, sys_done flag raises
        
        // --- Verify Auto-Clear to IDLE ---
        @(negedge clk);
        check_state("RETURN TO IDLE", 1'b0, 1'b0, 1'b0, 1'b0);
        
        // Final Report
        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] SYSTEM CONTROLLER FSM PASSED! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] SYSTEM CONTROLLER FAILED %0d CHECKS! \n==============================================\n", error_count);

        $stop;
    end
endmodule