`timescale 1ns / 1ps

module tb_systolic_array();
    import cnn_pkg::*;

    localparam ROWS = 2;
    localparam COLS = 2;

    logic                                clk;
    logic                                rst_n;
    logic                                en;
    logic                                setup_mode;
    
    act_t    [ROWS-1:0]                  i_act_left;
    weight_t [ROWS-1:0][COLS-1:0]        i_weight_matrix;
    psum_t   [COLS-1:0]                  i_psum_top;
    
    act_t    [ROWS-1:0]                  o_act_right;
    psum_t   [COLS-1:0]                  o_psum_bottom;

    // Instantiate DUT
    systolic_array_2d #(
        .ROWS(ROWS),
        .COLS(COLS)
    ) dut (.*);

    // Clock Generation
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    //  Continuous Output Monitor
    // ---------------------------------------------------------
    // Instead of guessing the clock cycle, we actively watch the bus.
    // When the math (100) cascades out of Col 0, we catch it instantly.
    always @(posedge clk) begin
        if (rst_n) begin
            if (o_psum_bottom[0] == 32'd100) begin
                $display("\n==============================================\n  [SUCCESS] BOOM! CAUGHT 100 AT TIME %0t! \n  SYSTOLIC ARRAY IS FLAWLESS. \n==============================================\n", $time);
                $stop;
            end
        end
    end

    // ---------------------------------------------------------
    // Stimulus Generation
    // ---------------------------------------------------------
    initial begin
        // 1. Reset
        clk = 0; rst_n = 0; en = 1; setup_mode = 0;
        i_act_left = '0; i_weight_matrix = '0; i_psum_top = '0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;
        
        // 2. Setup Phase: Load Weights
        @(negedge clk);
        setup_mode = 1;
        // Col 0 weights: 2 and 4. (We are aiming for 10*2 + 20*4 = 100)
        i_weight_matrix[0][0] = 8'd2; i_weight_matrix[0][1] = 8'd3;
        i_weight_matrix[1][0] = 8'd4; i_weight_matrix[1][1] = 8'd5;
        
        @(negedge clk);
        setup_mode = 0;
        
        // 3. Compute Phase: The Data Skew
        // Feed Row 0
        @(negedge clk);
        i_act_left[0] = 8'd10; 
        
        // Clear Row 0
        @(negedge clk);
        i_act_left[0] = 8'd0;
        
        // Wait for pipeline delay (3 cycles per PE)
        @(negedge clk);
        
        // Feed Row 1 (Exactly 3 cycles after Row 0)
        @(negedge clk);
        i_act_left[1] = 8'd20; 
        
        // Clear Row 1
        @(negedge clk);
        i_act_left[1] = 8'd0;
        
        // 4. Timeout Watchdog
        // If the monitor doesn't catch the '100' within 20 clock cycles, we have a real problem.
        repeat(20) @(posedge clk);
        
        $display("\n==============================================\n  [FATAL] TIMEOUT: MISSED THE DATA WAVE! \n==============================================\n");
        $stop;
    end
endmodule