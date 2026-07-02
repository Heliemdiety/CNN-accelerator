`timescale 1ns / 1ps

module cnn_top_tb_8x8_robust;

    // --- System Parameters ---
    localparam int CLK_PERIOD_NS   = 10;
    localparam int AXI_ADDR_WIDTH  = 32;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int BRAM_ADDR_WIDTH = 10;
    
    // --- Accelerator Parameters ---
    localparam int ROWS            = 8;
    localparam int COLS            = 8;
    localparam int LANES_PER_WORD  = AXI_DATA_WIDTH / 8;
    localparam int ACT_WORDS       = (ROWS + LANES_PER_WORD - 1) / LANES_PER_WORD;       // 2
    localparam int WGT_WORDS       = (ROWS * COLS + LANES_PER_WORD - 1) / LANES_PER_WORD; // 16
    localparam int OUT_WORDS       = (COLS + LANES_PER_WORD - 1) / LANES_PER_WORD;       // 2
    
    localparam int TIMEOUT_CYCLES  = 5000;

    // --- Memory Map ---
    localparam logic [31:0] ACT_BASE = 32'h0000_1000;
    localparam logic [31:0] WGT_BASE = 32'h0000_2000;
    localparam logic [31:0] OUT_BASE = 32'h0000_3000;
    
    // Quantization: Bias = 10 (16-bit), Shift = 1 (5-bit)
    localparam logic [31:0] QUANT_REG = 32'h000A_0001; 

    // --- Signals ---
    logic clk, rst_n;
    logic        cpu_wr_en, cpu_rd_en;
    logic [7:0]  cpu_wr_addr, cpu_rd_addr;
    logic [31:0] cpu_wr_data;
    logic [31:0] cpu_rd_data;
    logic        seq_start, seq_done, core_busy, core_done;

    // AXI Bus
    logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr, m_axi_awaddr;
    logic [7:0]                m_axi_arlen, m_axi_awlen;
    logic [2:0]                m_axi_arsize, m_axi_awsize;
    logic [1:0]                m_axi_arburst, m_axi_awburst, m_axi_rresp, m_axi_bresp;
    logic                      m_axi_arvalid, m_axi_arready, m_axi_rvalid, m_axi_rready, m_axi_rlast;
    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata, m_axi_wdata;
    logic [3:0]                m_axi_wstrb;
    logic                      m_axi_awvalid, m_axi_awready, m_axi_wvalid, m_axi_wready, m_axi_wlast, m_axi_bvalid, m_axi_bready;

    // --- Testbench Datasets ---
    logic signed [7:0] image_px [0:ROWS-1];
    logic signed [7:0] kernel_w [0:ROWS*COLS-1];
    logic [31:0]       act_words [0:ACT_WORDS-1];
    logic [31:0]       wgt_words [0:WGT_WORDS-1];
    logic [31:0]       out_words [0:OUT_WORDS-1];       // Actual captured from DUT
    logic [31:0]       expected_words [0:OUT_WORDS-1];  // Golden reference

    int error_count, output_write_count;
    logic rd_active, wr_active;
    logic [31:0] rd_base, wr_base;
    int unsigned rd_len, wr_len, rd_beat, wr_beat;

    // --- DUT Instantiation ---
    cnn_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH), 
        .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH), .ROWS(ROWS), .COLS(COLS)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_wr_en(cpu_wr_en), .cpu_wr_addr(cpu_wr_addr), .cpu_wr_data(cpu_wr_data),
        .cpu_rd_en(cpu_rd_en), .cpu_rd_addr(cpu_rd_addr), .cpu_rd_data(cpu_rd_data),
        .seq_start(seq_start), .seq_done(seq_done), .core_busy(core_busy), .core_done(core_done),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // --- Dynamic C-Like Reference Model ---
    task automatic compute_reference_model();
        int r, c;
        int signed raw_sum;
        int signed bias;
        int shift;
        int signed shifted_val;
        logic [7:0] final_val;
        
        bias = int'($signed(QUANT_REG[31:16]));
        shift = int'(QUANT_REG[4:0]);

        for (int i = 0; i < OUT_WORDS; i++) expected_words[i] = '0;

        for (c = 0; c < COLS; c++) begin
            raw_sum = 0;
            // 1. Matrix Multiplication
            for (r = 0; r < ROWS; r++) begin
                raw_sum += int'($signed(image_px[r])) * int'($signed(kernel_w[r * COLS + c]));
            end
            
            // 2. Post-Processing (Bias, ReLU, Shift, Saturation)
            raw_sum = raw_sum + bias;
            if (raw_sum < 0) begin
                final_val = 8'd0; // ReLU
            end else begin
                shifted_val = raw_sum >> shift;
                if (shifted_val > 127) final_val = 8'd127; // Saturation
                else final_val = shifted_val[7:0];
            end
            
            // 3. Pack into Expected Words Array
            expected_words[c / LANES_PER_WORD][(c % LANES_PER_WORD) * 8 +: 8] = final_val;
        end
    endtask

    // --- Payload Initialization ---
    task automatic initialize_vectors();
        int i;
        
        // Load Input Activations [1 to 8]
        for(i = 0; i < ROWS; i++) image_px[i] = 8'sd1 + i;
        
        // Load Weights (Identity Matrix)
        for(i = 0; i < ROWS*COLS; i++) kernel_w[i] = '0;
        for(i = 0; i < ROWS; i++) kernel_w[i*COLS + i] = 8'sd1;

        // Clear Memory
        for (i = 0; i < ACT_WORDS; i++) act_words[i] = '0;
        for (i = 0; i < WGT_WORDS; i++) wgt_words[i] = '0;
        for (i = 0; i < OUT_WORDS; i++) out_words[i] = '0;

        // Pack AXI Payload Arrays
        for (i = 0; i < ROWS; i++) 
            act_words[i / LANES_PER_WORD][(i % LANES_PER_WORD) * 8 +: 8] = image_px[i];
            
        for (i = 0; i < ROWS * COLS; i++) 
            wgt_words[i / LANES_PER_WORD][(i % LANES_PER_WORD) * 8 +: 8] = kernel_w[i];
    endtask

    // --- Strict Memory Emulation (Read) ---
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arready <= 0; m_axi_rvalid <= 0; rd_active <= 0; rd_beat <= 0;
        end else begin
            m_axi_arready <= !rd_active && !m_axi_rvalid;
            
            // Catch AR Protocol Violations
            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_arburst !== 2'b01 || m_axi_arsize !== 3'b010) begin
                    $error("VIOLATION: Invalid AXI Read Attributes (burst=%0b, size=%0b)", m_axi_arburst, m_axi_arsize);
                    error_count++;
                end
                rd_active <= 1'b1; rd_base <= m_axi_araddr; rd_len <= m_axi_arlen; rd_beat <= 0;
            end
            
            // Drive R Channel
            if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast) begin
                    m_axi_rvalid <= 1'b0; rd_active <= 1'b0; m_axi_rlast <= 1'b0;
                end else begin
                    rd_beat++;
                    m_axi_rlast <= ((rd_beat + 1) == rd_len);
                    m_axi_rdata <= (rd_base == ACT_BASE) ? act_words[rd_beat + 1] : wgt_words[rd_beat + 1];
                end
            end else if (rd_active && !m_axi_rvalid) begin
                m_axi_rvalid <= 1'b1; m_axi_rlast <= (rd_len == 0); m_axi_rresp <= 2'b00;
                m_axi_rdata <= (rd_base == ACT_BASE) ? act_words[0] : wgt_words[0];
            end
        end
    end

    // --- Strict Memory Emulation (Write) ---
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awready <= 0; m_axi_wready <= 0; m_axi_bvalid <= 0; wr_active <= 0; output_write_count <= 0;
        end else begin
            m_axi_awready <= !wr_active; 
            m_axi_wready <= wr_active && !m_axi_bvalid;

            // Catch AW Protocol Violations
            if (m_axi_awvalid && m_axi_awready) begin
                if (m_axi_awaddr !== OUT_BASE) begin
                    $error("VIOLATION: Bad Write Address 0x%08h", m_axi_awaddr);
                    error_count++;
                end
                if (m_axi_awburst !== 2'b01 || m_axi_awsize !== 3'b010) begin
                    $error("VIOLATION: Invalid AXI Write Attributes (burst=%0b, size=%0b)", m_axi_awburst, m_axi_awsize);
                    error_count++;
                end
                wr_active <= 1'b1; wr_len <= m_axi_awlen; wr_beat <= 0;
            end

            // Drive W Channel and Catch W Violations
            if (m_axi_wvalid && m_axi_wready) begin
                if (m_axi_wstrb !== 4'hF) begin
                    $error("VIOLATION: Invalid Write Strobe 0x%0h", m_axi_wstrb);
                    error_count++;
                end
                if (wr_beat < OUT_WORDS) out_words[wr_beat] <= m_axi_wdata;
                else begin
                    $error("VIOLATION: Received unexpected extra AXI W beat %0d", wr_beat);
                    error_count++;
                end
                
                output_write_count++;
                
                if (m_axi_wlast !== (wr_beat == wr_len)) begin
                    $error("VIOLATION: AXI WLAST mismatch at beat %0d, len %0d", wr_beat, wr_len);
                    error_count++;
                end

                if (m_axi_wlast) begin
                    wr_active <= 1'b0; m_axi_bvalid <= 1'b1; m_axi_bresp <= 2'b00;
                end else begin
                    wr_beat++;
                end
            end
            if (m_axi_bvalid && m_axi_bready) m_axi_bvalid <= 1'b0;
        end
    end

    // --- Control Tasks ---
    task automatic csr_write(input logic [7:0] addr, input logic [31:0] data);
        @(negedge clk); cpu_wr_en = 1'b1; cpu_wr_addr = addr; cpu_wr_data = data;
        @(negedge clk); cpu_wr_en = 1'b0;
    endtask

    task automatic wait_for_core_done();
        int cycle;
        bit done_seen = 0;
        for (cycle = 0; cycle < TIMEOUT_CYCLES; cycle++) begin
            @(posedge clk);
            if (core_done) begin
                done_seen = 1'b1;
                break;
            end
        end
        if (!done_seen) $fatal(1, "FATAL: Accelerator hung! core_done not asserted after %0d cycles", TIMEOUT_CYCLES);
    endtask

    // --- Main Verification Sequence ---
    initial begin
        clk = 0; rst_n = 0; cpu_wr_en = 0; cpu_rd_en = 0; error_count = 0;
        // m_axi_bready = 1'b1; m_axi_rready = 1'b1; 
        
        $display("Initializing Vectors and Golden Reference Model...");
        initialize_vectors();
        compute_reference_model();

        repeat (8) @(posedge clk); rst_n = 1'b1; repeat (4) @(posedge clk);

        $display("Programming CSRs...");
        csr_write(8'h08, ACT_BASE);
        csr_write(8'h0C, WGT_BASE);
        csr_write(8'h10, OUT_BASE);
        csr_write(8'h14, QUANT_REG);
        
        $display("Firing Core Start...");
        csr_write(8'h00, 32'h0000_0001);

        wait_for_core_done();
        repeat (10) @(posedge clk); // Allow DMA writes to fully drain

        // --- Post-Run Verification ---
        $display("\n--- Checking Data Payloads ---");
        if (output_write_count != OUT_WORDS) begin
            $error("FAIL: Expected %0d AXI output words, got %0d", OUT_WORDS, output_write_count);
            error_count++;
        end

        for (int i = 0; i < OUT_WORDS; i++) begin
            if (out_words[i] !== expected_words[i]) begin
                $error("FAIL: Output Word %0d mismatch. Expected 0x%08h, Got 0x%08h", i, expected_words[i], out_words[i]);
                error_count++;
            end else begin
                $display("PASS: Output Word %0d matches (0x%08h)", i, out_words[i]);
            end
        end

        if (error_count == 0) begin
            $display("==================================================");
            $display(" VERIFICATION PASSED: ZERO PROTOCOL OR DATA ERRORS");
            $display("==================================================");
        end else begin
            $fatal(1, "VERIFICATION FAILED: Detected %0d errors.", error_count);
        end
        $finish;
    end

endmodule