`timescale 1ns / 1ps

module tb_cnn_dma_write();

    logic        clk;
    logic        rst_n;
    logic        start;
    logic [31:0] base_addr;
    logic [7:0]  burst_len;
    logic        done;

    logic [9:0]  bram_addr;
    logic [31:0] bram_dout;

    // AXI Bus
    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic        m_axi_awvalid;
    logic        m_axi_awready;

    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;

    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    int error_count = 0;
    int words_received = 0;

    cnn_dma_write dut (.*);

    always #5 clk = ~clk;

    // --- Fake BRAM (Strict Posedge) ---
    always_ff @(posedge clk) begin
        bram_dout <= 32'hDA7A_0000 + bram_addr;
    end

    // --- Fake AXI Slave (Strict Negedge Pacing) ---
    initial begin
        m_axi_awready = 0;
        m_axi_wready  = 0;
        m_axi_bvalid  = 0;
        m_axi_bresp   = 0;
        
        forever begin
            @(posedge clk);
            
            // 1. Handshake AW Channel
            if (m_axi_awvalid && !m_axi_awready) begin
                @(negedge clk);
                m_axi_awready = 1;
                @(negedge clk);
                m_axi_awready = 0;
            end
            
            // 2. Handshake W Channel
            if (m_axi_wvalid && !m_axi_wready) begin
                @(negedge clk);
                // random slave stalling to test the hardware
                if ($urandom_range(0, 1)) begin
                    repeat(2) @(negedge clk); 
                end
                
                m_axi_wready = 1;
                
                // Wait for the master to lock it on the posedge
                wait(m_axi_wvalid == 1'b1);
                
                $display("T=%0t | [AXI Slave] Caught WDATA: %h (WLAST: %b)", $time, m_axi_wdata, m_axi_wlast);
                words_received++;
                
                if (m_axi_wdata !== (32'hDA7A_0000 + (words_received - 1))) begin
                    $error("FAIL! Corrupt data over AXI. Got: %h", m_axi_wdata);
                    error_count++;
                end
                
                // If it's the last word, fire the B channel response
                if (m_axi_wlast) begin
                    @(negedge clk); 
                    m_axi_wready = 0;
                    repeat(2) @(negedge clk); // Simulate slave thinking
                    m_axi_bvalid = 1;
                    
                    while (m_axi_bready == 1'b0) @(negedge clk);
                    
                    @(negedge clk); 
                    m_axi_bvalid = 0;
                end else begin
                    @(negedge clk);
                    m_axi_wready = 0;
                end
            end
        end
    end

    // --- Main Test Sequence ---
    initial begin
        clk = 0; rst_n = 0; start = 0; base_addr = 0; burst_len = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;

        @(negedge clk);
        base_addr = 32'h9000_1000;
        burst_len = 8'd4; // 5 words
        start = 1;
        
        @(negedge clk);
        start = 0;

        // Watchdog Timeout
        fork
            begin
                wait(done == 1'b1);
            end
            begin
                #1000;
                $display("FATAL: Watchdog Timeout! System Hung.");
                $stop;
            end
        join_any
        
        if (words_received != 5) begin
            $error("FAIL! Expected 5 words, Slave caught %0d", words_received);
            error_count++;
        end

        if (error_count == 0)
            $display("\n==============================================\n  [SUCCESS] DMA WRITE PUSHED DATA TO DDR4! \n==============================================\n");
        else
            $display("\n==============================================\n  [FATAL] DMA WRITE FAILED! \n==============================================\n");

        $stop;
    end
endmodule