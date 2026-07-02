`timescale 1ns / 1ps

module cnn_top_tb;

    localparam int CLK_PERIOD_NS   = 10;
    localparam int AXI_ADDR_WIDTH  = 32;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int BRAM_ADDR_WIDTH = 10;
    localparam int ROWS            = 9;
    localparam int COLS            = 1;
    localparam int LANES_PER_WORD  = AXI_DATA_WIDTH / 8;
    localparam int ACT_WORDS       = (ROWS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int WGT_WORDS       = (ROWS * COLS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int OUT_WORDS       = (COLS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int TIMEOUT_CYCLES  = 2000;

    localparam logic [31:0] ACT_BASE = 32'h0000_1000;
    localparam logic [31:0] WGT_BASE = 32'h0000_2000;
    localparam logic [31:0] OUT_BASE = 32'h0000_3000;

    // 3x3 valid convolution test:
    // image  = [ 1 2 3 ; 4 5 6 ; 7 8 9 ]
    // kernel = [-1 0 1 ;-1 0 1 ;-1 0 1 ]
    // raw sum = (-1+3) + (-4+6) + (-7+9) = 6
    // post process: (raw + bias 4) >> shift 1 = 5
    localparam int signed EXPECTED_RAW_SUM = 6;
    localparam logic [31:0] QUANT_REG      = 32'h0004_0001;
    localparam logic [31:0] EXPECTED_WORD  = 32'h0000_0005;

    logic clk;
    logic rst_n;

    logic        cpu_wr_en;
    logic [7:0]  cpu_wr_addr;
    logic [31:0] cpu_wr_data;
    logic        cpu_rd_en;
    logic [7:0]  cpu_rd_addr;
    logic [31:0] cpu_rd_data;

    logic seq_start;
    logic seq_done;
    logic core_busy;
    logic core_done;

    logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]                m_axi_arlen;
    logic [2:0]                m_axi_arsize;
    logic [1:0]                m_axi_arburst;
    logic                      m_axi_arvalid;
    logic                      m_axi_arready;

    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0]                m_axi_rresp;
    logic                      m_axi_rlast;
    logic                      m_axi_rvalid;
    logic                      m_axi_rready;

    logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]                m_axi_awlen;
    logic [2:0]                m_axi_awsize;
    logic [1:0]                m_axi_awburst;
    logic                      m_axi_awvalid;
    logic                      m_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    logic [3:0]                m_axi_wstrb;
    logic                      m_axi_wlast;
    logic                      m_axi_wvalid;
    logic                      m_axi_wready;

    logic [1:0]                m_axi_bresp;
    logic                      m_axi_bvalid;
    logic                      m_axi_bready;

    logic signed [7:0] image_px [0:ROWS-1];
    logic signed [7:0] kernel_w [0:ROWS*COLS-1];

    logic [31:0] act_words [0:ACT_WORDS-1];
    logic [31:0] wgt_words [0:WGT_WORDS-1];
    logic [31:0] out_words [0:OUT_WORDS-1];

    int error_count;
    int output_write_count;

    logic        rd_active;
    logic [31:0] rd_base;
    int unsigned rd_len;
    int unsigned rd_beat;

    logic        wr_active;
    logic [31:0] wr_base;
    int unsigned wr_len;
    int unsigned wr_beat;

    cnn_top #(
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .BRAM_ADDR_WIDTH (BRAM_ADDR_WIDTH),
        .ROWS            (ROWS),
        .COLS            (COLS)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .cpu_wr_en     (cpu_wr_en),
        .cpu_wr_addr   (cpu_wr_addr),
        .cpu_wr_data   (cpu_wr_data),
        .cpu_rd_en     (cpu_rd_en),
        .cpu_rd_addr   (cpu_rd_addr),
        .cpu_rd_data   (cpu_rd_data),
        .seq_start     (seq_start),
        .seq_done      (seq_done),
        .core_busy     (core_busy),
        .core_done     (core_done),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    function automatic logic [31:0] read_payload_word(
        input logic [31:0] base_addr,
        input int unsigned beat
    );
        read_payload_word = 32'hDEAD_BEEF;

        if (base_addr == ACT_BASE) begin
            if (beat < ACT_WORDS) begin
                read_payload_word = act_words[beat];
            end else begin
                $error("AXI read beat %0d exceeds activation payload size", beat);
            end
        end else if (base_addr == WGT_BASE) begin
            if (beat < WGT_WORDS) begin
                read_payload_word = wgt_words[beat];
            end else begin
                $error("AXI read beat %0d exceeds weight payload size", beat);
            end
        end else begin
            $error("Unexpected AXI read base address 0x%08h", base_addr);
        end
    endfunction

    function automatic int signed compute_reference_sum();
        int i;
        int signed sum;

        sum = 0;
        for (i = 0; i < ROWS; i++) begin
            sum += int'($signed(image_px[i])) * int'($signed(kernel_w[i]));
        end

        return sum;
    endfunction

    task automatic initialize_vectors();
        int i;

        image_px[0] = 8'sd1;
        image_px[1] = 8'sd2;
        image_px[2] = 8'sd3;
        image_px[3] = 8'sd4;
        image_px[4] = 8'sd5;
        image_px[5] = 8'sd6;
        image_px[6] = 8'sd7;
        image_px[7] = 8'sd8;
        image_px[8] = 8'sd9;

        kernel_w[0] = -8'sd1;
        kernel_w[1] =  8'sd0;
        kernel_w[2] =  8'sd1;
        kernel_w[3] = -8'sd1;
        kernel_w[4] =  8'sd0;
        kernel_w[5] =  8'sd1;
        kernel_w[6] = -8'sd1;
        kernel_w[7] =  8'sd0;
        kernel_w[8] =  8'sd1;

        for (i = 0; i < ACT_WORDS; i++) begin
            act_words[i] = '0;
        end

        for (i = 0; i < WGT_WORDS; i++) begin
            wgt_words[i] = '0;
        end

        for (i = 0; i < OUT_WORDS; i++) begin
            out_words[i] = '0;
        end

        for (i = 0; i < ROWS; i++) begin
            act_words[i / LANES_PER_WORD][(i % LANES_PER_WORD) * 8 +: 8] = image_px[i];
        end

        for (i = 0; i < ROWS * COLS; i++) begin
            wgt_words[i / LANES_PER_WORD][(i % LANES_PER_WORD) * 8 +: 8] = kernel_w[i];
        end
    endtask

    task automatic initialize_bus_signals();
        clk                = 1'b0;
        rst_n              = 1'b0;
        cpu_wr_en          = 1'b0;
        cpu_wr_addr        = '0;
        cpu_wr_data        = '0;
        cpu_rd_en          = 1'b0;
        cpu_rd_addr        = '0;
        seq_start          = 1'b0;
        m_axi_arready      = 1'b0;
        m_axi_rdata        = '0;
        m_axi_rresp        = 2'b00;
        m_axi_rlast        = 1'b0;
        m_axi_rvalid       = 1'b0;
        m_axi_awready      = 1'b0;
        m_axi_wready       = 1'b0;
        m_axi_bresp        = 2'b00;
        m_axi_bvalid       = 1'b0;
        rd_active          = 1'b0;
        rd_base            = '0;
        rd_len             = 0;
        rd_beat            = 0;
        wr_active          = 1'b0;
        wr_base            = '0;
        wr_len             = 0;
        wr_beat            = 0;
        error_count        = 0;
        output_write_count = 0;
    endtask

    task automatic csr_write(input logic [7:0] addr, input logic [31:0] data);
        @(negedge clk);
        cpu_wr_en   = 1'b1;
        cpu_wr_addr = addr;
        cpu_wr_data = data;

        @(negedge clk);
        cpu_wr_en   = 1'b0;
        cpu_wr_addr = '0;
        cpu_wr_data = '0;
    endtask

    task automatic wait_for_core_done();
        int cycle;
        bit done_seen;

        done_seen = 1'b0;
        for (cycle = 0; cycle < TIMEOUT_CYCLES; cycle++) begin
            @(posedge clk);
            if (core_done) begin
                done_seen = 1'b1;
                break;
            end
        end

        if (!done_seen) begin
            $fatal(1, "Timeout waiting for cnn_top core_done after %0d cycles", TIMEOUT_CYCLES);
        end
    endtask

    task automatic check_results();
        int i;

        if (output_write_count != OUT_WORDS) begin
            $error("Expected %0d AXI output word(s), got %0d", OUT_WORDS, output_write_count);
            error_count++;
        end

        if (out_words[0] !== EXPECTED_WORD) begin
            $error("Output mismatch: expected 0x%08h, got 0x%08h", EXPECTED_WORD, out_words[0]);
            error_count++;
        end

        for (i = 1; i < OUT_WORDS; i++) begin
            if (out_words[i] !== 32'd0) begin
                $error("Unexpected nonzero extra output word[%0d] = 0x%08h", i, out_words[i]);
                error_count++;
            end
        end

        if (error_count == 0) begin
            $display("======================================");
            $display(" CNN ACCELERATOR VERIFICATION PASSED ");
            $display("======================================");
            $display("Expected raw convolution sum = %0d", EXPECTED_RAW_SUM);
            $display("Expected quantized output    = %0d", EXPECTED_WORD[7:0]);
            $display("Captured AXI output word     = 0x%08h", out_words[0]);
        end else begin
            $display("======================================");
            $display(" CNN ACCELERATOR VERIFICATION FAILED ");
            $display("======================================");
            $fatal(1, "Detected %0d verification error(s)", error_count);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rdata   <= '0;
            m_axi_rresp   <= 2'b00;
            m_axi_rlast   <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            rd_active     <= 1'b0;
            rd_base       <= '0;
            rd_len        <= 0;
            rd_beat       <= 0;
        end else begin
            m_axi_arready <= !rd_active && !m_axi_rvalid;

            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_arburst !== 2'b01 || m_axi_arsize !== 3'b010) begin
                    $error("Unexpected AXI read attributes: arburst=%0b arsize=%0b", m_axi_arburst, m_axi_arsize);
                    error_count++;
                end

                rd_active <= 1'b1;
                rd_base   <= m_axi_araddr;
                rd_len    <= m_axi_arlen;
                rd_beat   <= 0;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast) begin
                    m_axi_rvalid <= 1'b0;
                    m_axi_rlast  <= 1'b0;
                    rd_active    <= 1'b0;
                    rd_beat      <= 0;
                end else begin
                    rd_beat      <= rd_beat + 1;
                    m_axi_rdata  <= read_payload_word(rd_base, rd_beat + 1);
                    m_axi_rlast  <= ((rd_beat + 1) == rd_len);
                    m_axi_rvalid <= 1'b1;
                end
            end else if (rd_active && !m_axi_rvalid) begin
                m_axi_rdata  <= read_payload_word(rd_base, 0);
                m_axi_rresp  <= 2'b00;
                m_axi_rlast  <= (rd_len == 0);
                m_axi_rvalid <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awready      <= 1'b0;
            m_axi_wready       <= 1'b0;
            m_axi_bresp        <= 2'b00;
            m_axi_bvalid       <= 1'b0;
            wr_active          <= 1'b0;
            wr_base            <= '0;
            wr_len             <= 0;
            wr_beat            <= 0;
            output_write_count <= 0;
        end else begin
            m_axi_awready <= !wr_active;
            m_axi_wready  <= wr_active && !m_axi_bvalid;

            if (m_axi_awvalid && m_axi_awready) begin
                if (m_axi_awaddr !== OUT_BASE) begin
                    $error("Unexpected AXI write base address: expected 0x%08h, got 0x%08h", OUT_BASE, m_axi_awaddr);
                    error_count++;
                end

                if (m_axi_awburst !== 2'b01 || m_axi_awsize !== 3'b010) begin
                    $error("Unexpected AXI write attributes: awburst=%0b awsize=%0b", m_axi_awburst, m_axi_awsize);
                    error_count++;
                end

                wr_active <= 1'b1;
                wr_base   <= m_axi_awaddr;
                wr_len    <= m_axi_awlen;
                wr_beat   <= 0;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (m_axi_wstrb !== 4'hF) begin
                    $error("Unexpected AXI write strobe 0x%0h", m_axi_wstrb);
                    error_count++;
                end

                if (wr_beat < OUT_WORDS) begin
                    out_words[wr_beat] <= m_axi_wdata;
                end else begin
                    $error("Received unexpected extra AXI output beat %0d", wr_beat);
                    error_count++;
                end

                output_write_count <= output_write_count + 1;

                if (m_axi_wlast !== (wr_beat == wr_len)) begin
                    $error("AXI WLAST mismatch at beat %0d, len %0d", wr_beat, wr_len);
                    error_count++;
                end

                if (m_axi_wlast) begin
                    wr_active    <= 1'b0;
                    wr_beat      <= 0;
                    m_axi_bresp  <= 2'b00;
                    m_axi_bvalid <= 1'b1;
                end else begin
                    wr_beat <= wr_beat + 1;
                end
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    initial begin
        initialize_vectors();
        initialize_bus_signals();

        if (compute_reference_sum() != EXPECTED_RAW_SUM) begin
            $fatal(1, "Internal testbench reference mismatch: expected raw %0d, computed %0d",
                   EXPECTED_RAW_SUM, compute_reference_sum());
        end

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        csr_write(8'h08, ACT_BASE);
        csr_write(8'h0C, WGT_BASE);
        csr_write(8'h10, OUT_BASE);
        csr_write(8'h14, QUANT_REG);
        csr_write(8'h00, 32'h0000_0001);

        wait_for_core_done();
        repeat (5) @(posedge clk);
        check_results();

        $finish;
    end

endmodule
