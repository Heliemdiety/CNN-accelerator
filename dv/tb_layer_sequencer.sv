`timescale 1ns / 1ps

module tb_layer_sequencer();

    logic        clk;
    logic        rst_n;
    logic        seq_start;
    logic        seq_done;
    logic        core_done;
    
    logic        csr_wr_en;
    logic [7:0]  csr_wr_addr;
    logic [31:0] csr_wr_data;

    int error_count = 0;
    int writes_captured = 0;

    layer_sequencer dut (.*);

    always #5 clk = ~clk;

    // A transparent monitor to catch every write hitting the CSR
    always @(negedge clk) begin
        if (csr_wr_en) begin
            $display("T=%0t | Sequencer wrote %h to Addr %h", $time, csr_wr_data, csr_wr_addr);
            writes_captured++;
        end
    end

    initial begin
        // Reset
        clk = 0; rst_n = 0; seq_start = 0; core_done = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;

        // Kick off the network sequencer
        @(negedge clk);
        seq_start = 1;
        @(negedge clk);
        seq_start = 0;

        // Wait for it to hit the first WAIT_CORE trigger (Layer 1)
        wait(csr_wr_addr == 8'h00 && csr_wr_en == 1'b1);
        $display("\n[Layer 1 Triggered] -> Hardware is computing...");
        
        // Wait a few cycles to simulate CNN core latency
        repeat(10) @(posedge clk);
        
        // Reply with core_done (CNN finished Layer 1)
        @(negedge clk);
        core_done = 1;
        @(negedge clk);
        core_done = 0;

        // Wait for it to hit the second WAIT_CORE trigger (Layer 2)
        wait(csr_wr_addr == 8'h00 && csr_wr_en == 1'b1);
        $display("\n[Layer 2 Triggered] -> Hardware is computing...");

        // Simulate CNN core latency
        repeat(10) @(posedge clk);

        // Reply with core_done (CNN finished Layer 2)
        @(negedge clk);
        core_done = 1;
        @(negedge clk);
        core_done = 0;

        // Wait for the final sequencer DONE flag
        wait(seq_done == 1'b1);
        
        // Validation Check
        if (writes_captured != 10) begin
            $error("FAIL! Expected 10 total CSR writes for 2 layers. Caught: %0d", writes_captured);
            error_count++;
        end

        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] SEQUENCER EXECUTED BOTH LAYERS FLAWLESSLY! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] SEQUENCER FAILED! \n==============================================\n");

        $stop;
    end
endmodule