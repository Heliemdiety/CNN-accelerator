`timescale 1ns / 1ps

module tb_cnn_dma();

    logic        clk;
    logic        rst_n;
    logic        start;
    logic [31:0] base_addr;
    logic [7:0]  burst_len;
    logic        done;

    logic        bram_we;
    logic [9:0]  bram_addr;
    logic [31:0] bram_din;

    // AXI Bus
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid;
    logic        m_axi_arready;

    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    int error_count = 0;
    int words_written = 0;

    // Instantiate DUT
    cnn_dma_read dut (.*);

    always #5 clk = ~clk;

    // --- FAKE AXI SLAVE (Strict Negedge Paced) ---
    initial begin
        m_axi_arready = 0;
        m_axi_rdata = 0;
        m_axi_rvalid = 0;
        m_axi_rlast = 0;
        m_axi_rresp = 0;
        
        forever begin
            @(posedge clk);
            if (m_axi_arvalid && !m_axi_arready) begin
                $display("T=%0t | [AXI Slave] Received Read Req for Addr: %h, Len: %0d", $time, m_axi_araddr, m_axi_arlen);
                
                repeat(3) @(posedge clk);
                m_axi_arready = 1;
                @(posedge clk);
                m_axi_arready = 0;
                
                for (int i = 0; i <= m_axi_arlen; i++) begin
                    @(negedge clk); 
                    // Safely wait for master to be ready
                    while (m_axi_rready == 1'b0) @(negedge clk);
                    
                    m_axi_rvalid = 1;
                    m_axi_rdata  = 32'hBEEF_0000 + i; 
                    m_axi_rlast  = (i == m_axi_arlen);
                end
                
                @(negedge clk); 
                m_axi_rvalid = 0;
                m_axi_rlast  = 0;
                $display("T=%0t | [AXI Slave] Finished sending burst.", $time);
            end
        end
    end

    // ---  BRAM Monitor (Strict Posedge Sample) ---
    // Physical BRAM writes on the posedge. We monitor exactly when it writes.
    always @(posedge clk) begin
        if (bram_we) begin
            words_written++;
            if (bram_din !== (32'hBEEF_0000 + bram_addr)) begin
                $error("FAIL! BRAM Data mismatch at Addr %0d. Got: %h, Expected: %h", bram_addr, bram_din, 32'hBEEF_0000 + bram_addr);
                error_count++;
            end else begin
                $display("PASS -> Word %0d caught perfectly at Addr %0d", words_written, bram_addr);
            end
        end
    end

    // --- Main Test Sequence ---
    initial begin
        clk = 0; rst_n = 0; start = 0; base_addr = 0; burst_len = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;

        @(negedge clk);
        base_addr = 32'h1000_2000;
        burst_len = 8'd3; 
        start = 1;
        @(negedge clk);
        start = 0;

        // timeout to prevent silent hanging
        fork
            begin
                wait(done == 1'b1);
            end
            begin
                #500;
                $display("FATAL: Watchdog Timeout! System Hung.");
                $stop;
            end
        join_any
        
        if (words_written != 4) begin
            $error("FAIL! DMA did not write the correct number of words to BRAM. Got: %0d, Exp: 4", words_written);
            error_count++;
        end

        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] DMA BURST TRANSFER COMPLETE! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] DMA TRANSFER FAILED! \n==============================================\n");

        $stop;
    end
endmodule