`timescale 1ns / 1ps

module cnn_top
    import cnn_pkg::*;
#(
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int BRAM_ADDR_WIDTH = 10,
    parameter int ROWS            = ARRAY_ROWS,
    parameter int COLS            = ARRAY_COLS
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Generic CPU/host CSR bus
    input  logic                      cpu_wr_en,
    input  logic [7:0]                cpu_wr_addr,
    input  logic [31:0]               cpu_wr_data,
    input  logic                      cpu_rd_en,
    input  logic [7:0]                cpu_rd_addr,
    output logic [31:0]               cpu_rd_data,

    // Optional microcode layer sequencer trigger
    input  logic                      seq_start,
    output logic                      seq_done,

    // Top-level status pulses
    output logic                      core_busy,
    output logic                      core_done,

    // AXI4-Full Read Address (AR)
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,

    // AXI4-Full Read Data (R)
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready,

    // AXI4-Full Write Address (AW)
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,

    // AXI4-Full Write Data (W)
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]                m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,

    // AXI4-Full Write Response (B)
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready
);

    localparam int LANES_PER_WORD        = AXI_DATA_WIDTH / 8;
    localparam int ACT_WORDS             = (ROWS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int WEIGHT_WORDS          = (ROWS * COLS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int OUT_WORDS             = (COLS + LANES_PER_WORD - 1) / LANES_PER_WORD;
    localparam int MAC_PIPELINE_GAP      = 3;
    // localparam int MAC_RESULT_LATENCY    = 2;
    localparam int MAC_RESULT_LATENCY = 3;
    localparam int POST_PIPELINE_LATENCY = 2;
    localparam int LAST_SKEW_CYCLE       = (ROWS - 1) * MAC_PIPELINE_GAP;
    localparam int LAST_CAPTURE_CYCLE    = LAST_SKEW_CYCLE + (COLS - 1) + MAC_RESULT_LATENCY;
    localparam int SYS_DRAIN_CYCLES      = LAST_CAPTURE_CYCLE + POST_PIPELINE_LATENCY + 4;
    localparam int COMP_COUNTER_W        = (SYS_DRAIN_CYCLES < 2) ? 1 : $clog2(SYS_DRAIN_CYCLES + 1);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_RD_ACT_START,
        ST_RD_ACT_WAIT,
        ST_SWAP_ACT,
        ST_RD_WGT_START,
        ST_RD_WGT_WAIT,
        ST_SWAP_WGT,
        ST_WGT_RD_REQ,
        ST_WGT_RD_CAP,
        ST_COMPUTE_START,
        ST_COMPUTE_WAIT,
        ST_STORE_OUT,
        ST_WR_OUT_START,
        ST_WR_OUT_WAIT,
        ST_DONE
    } top_state_t;

    typedef enum logic {
        TARGET_ACT,
        TARGET_WGT
    } read_target_t;

    function automatic logic [7:0] axi_len_from_words(input int unsigned words);
        if (words <= 1) begin
            axi_len_from_words = 8'd0;
        end else begin
            axi_len_from_words = words[7:0] - 8'd1;
        end
    endfunction

    function automatic logic [BRAM_ADDR_WIDTH-1:0] bram_addr_from_int(input int unsigned value);
        bram_addr_from_int = value[BRAM_ADDR_WIDTH-1:0];
    endfunction

    top_state_t  state, next_state;
    read_target_t read_target;

    logic core_rst_n;
    logic core_soft_rst;
    assign core_rst_n = rst_n & ~core_soft_rst;

    // CSR and layer-sequencer wiring
    logic        csr_wr_en_mux;
    logic [7:0]  csr_wr_addr_mux;
    logic [31:0] csr_wr_data_mux;
    logic        seq_csr_wr_en;
    logic [7:0]  seq_csr_wr_addr;
    logic [31:0] seq_csr_wr_data;

    logic        core_start;
    // logic        core_soft_rst;
    logic [31:0] act_base_ptr;
    logic [31:0] wt_base_ptr;
    logic [31:0] out_base_ptr;
    logic [31:0] bias_val;
    logic [4:0]  shift_val;

    assign csr_wr_en_mux   = seq_csr_wr_en | cpu_wr_en;
    assign csr_wr_addr_mux = seq_csr_wr_en ? seq_csr_wr_addr : cpu_wr_addr;
    assign csr_wr_data_mux = seq_csr_wr_en ? seq_csr_wr_data : cpu_wr_data;

    assign core_busy = (state != ST_IDLE);
    assign core_done = (state == ST_DONE);

    cnn_csr u_csr (
        .clk           (clk),
        .rst_n         (rst_n),
        .wr_en         (csr_wr_en_mux),
        .wr_addr       (csr_wr_addr_mux),
        .wr_data       (csr_wr_data_mux),
        .rd_en         (cpu_rd_en),
        .rd_addr       (cpu_rd_addr),
        .rd_data       (cpu_rd_data),
        .core_start    (core_start),
        .core_soft_rst (core_soft_rst),
        .act_base_ptr  (act_base_ptr),
        .wt_base_ptr   (wt_base_ptr),
        .out_base_ptr  (out_base_ptr),
        .bias_val      (bias_val),
        .shift_val     (shift_val),
        .core_done     (core_done),
        .core_busy     (core_busy)
    );

    layer_sequencer u_layer_sequencer (
        .clk         (clk),
        .rst_n       (rst_n),
        .seq_start   (seq_start),
        .seq_done    (seq_done),
        .core_done   (core_done),
        .csr_wr_en   (seq_csr_wr_en),
        .csr_wr_addr (seq_csr_wr_addr),
        .csr_wr_data (seq_csr_wr_data)
    );

    // Shared AXI read DMA, routed to activation or weight ping-pong BRAMs.
    logic                       dma_rd_start;
    logic [AXI_ADDR_WIDTH-1:0]  dma_rd_base_addr;
    logic [7:0]                 dma_rd_burst_len;
    logic                       dma_rd_done;
    logic                       dma_rd_bram_we;
    logic [BRAM_ADDR_WIDTH-1:0] dma_rd_bram_addr;
    logic [AXI_DATA_WIDTH-1:0]  dma_rd_bram_din;

    assign dma_rd_start = (state == ST_RD_ACT_START) || (state == ST_RD_WGT_START);

    always_comb begin
        dma_rd_base_addr = wt_base_ptr;
        dma_rd_burst_len = axi_len_from_words(WEIGHT_WORDS);

        case (state)
            ST_RD_ACT_START,
            ST_RD_ACT_WAIT: begin
                dma_rd_base_addr = act_base_ptr;
                dma_rd_burst_len = axi_len_from_words(ACT_WORDS);
            end

            ST_RD_WGT_START,
            ST_RD_WGT_WAIT: begin
                dma_rd_base_addr = wt_base_ptr;
                dma_rd_burst_len = axi_len_from_words(WEIGHT_WORDS);
            end

            default: begin
                if (read_target == TARGET_ACT) begin
                    dma_rd_base_addr = act_base_ptr;
                    dma_rd_burst_len = axi_len_from_words(ACT_WORDS);
                end
            end
        endcase
    end

    cnn_dma_read #(
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .BRAM_ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_dma_read (
        .clk           (clk),
        .rst_n         (core_rst_n),
        .start         (dma_rd_start),
        .base_addr     (dma_rd_base_addr),
        .burst_len     (dma_rd_burst_len),
        .done          (dma_rd_done),
        .bram_we       (dma_rd_bram_we),
        .bram_addr     (dma_rd_bram_addr),
        .bram_din      (dma_rd_bram_din),
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
        .m_axi_rready  (m_axi_rready)
    );

    logic                       act_swap;
    logic                       act_core_re;
    logic [BRAM_ADDR_WIDTH-1:0] act_core_addr;
    logic [AXI_DATA_WIDTH-1:0]  act_core_dout;

    logic                       wgt_swap;
    logic                       wgt_core_re;
    logic [BRAM_ADDR_WIDTH-1:0] wgt_core_addr;
    logic [AXI_DATA_WIDTH-1:0]  wgt_core_dout;

    assign act_swap = (state == ST_SWAP_ACT);
    assign wgt_swap = (state == ST_SWAP_WGT);

    ping_pong_bram #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_act_ping_pong (
        .clk       (clk),
        .rst_n     (core_rst_n),
        .swap      (act_swap),
        .ext_we    (dma_rd_bram_we && (read_target == TARGET_ACT)),
        .ext_addr  (dma_rd_bram_addr),
        .ext_din   (dma_rd_bram_din),
        .core_re   (act_core_re),
        .core_addr (act_core_addr),
        .core_dout (act_core_dout)
    );

    ping_pong_bram #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_wgt_ping_pong (
        .clk       (clk),
        .rst_n     (core_rst_n),
        .swap      (wgt_swap),
        .ext_we    (dma_rd_bram_we && (read_target == TARGET_WGT)),
        .ext_addr  (dma_rd_bram_addr),
        .ext_din   (dma_rd_bram_din),
        .core_re   (wgt_core_re),
        .core_addr (wgt_core_addr),
        .core_dout (wgt_core_dout)
    );

    // Weight matrix load from packed 32-bit local memory words.
    // weight_t weight_matrix [ROWS-1:0][COLS-1:0];
    // weight_t [ROWS-1:0][COLS-1:0] weight_matrix;
    wgt_matrix_t  weight_matrix;

    logic [BRAM_ADDR_WIDTH-1:0] weight_word_idx;

    assign wgt_core_re   = (state == ST_WGT_RD_REQ);
    assign wgt_core_addr = weight_word_idx;

    always_ff @(posedge clk) begin : weight_load_proc
        int lane_i;
        int flat_i;
        int row_i;
        int col_i;

        if (!core_rst_n) begin
            for (row_i = 0; row_i < ROWS; row_i++) begin
                for (col_i = 0; col_i < COLS; col_i++) begin
                    weight_matrix[row_i][col_i] <= '0;
                end
            end
        end else if (state == ST_WGT_RD_CAP) begin
            for (lane_i = 0; lane_i < LANES_PER_WORD; lane_i++) begin
                flat_i = (weight_word_idx * LANES_PER_WORD) + lane_i;
                if (flat_i < (ROWS * COLS)) begin
                    weight_matrix[flat_i / COLS][flat_i % COLS] <= weight_t'(wgt_core_dout[(lane_i * 8) +: 8]);
                end
            end
        end
    end

    // Compute control, activation address generation, and activation skew.
    logic                       sys_start;
    logic                       sys_done;
    logic                       sys_array_en;
    logic                       sys_setup_mode;
    logic                       sys_start_act_read;
    logic                       act_addrgen_done;
    logic                       act_addrgen_rd_en;
    logic [BRAM_ADDR_WIDTH-1:0] act_addrgen_rd_addr;
    logic [BRAM_ADDR_WIDTH-1:0] act_addrgen_burst_length;

    assign sys_start                = (state == ST_COMPUTE_START);
    assign act_addrgen_burst_length = bram_addr_from_int(ACT_WORDS);

    cnn_sys_ctrl #(
        .PIPELINE_DEPTH (SYS_DRAIN_CYCLES)
    ) u_sys_ctrl (
        .clk            (clk),
        .rst_n          (core_rst_n),
        .start          (sys_start),
        .sys_done       (sys_done),
        .array_en       (sys_array_en),
        .setup_mode     (sys_setup_mode),
        .start_act_read (sys_start_act_read),
        .act_read_done  (act_addrgen_done)
    );

    address_gen #(
        .ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_act_address_gen (
        .clk          (clk),
        .rst_n        (core_rst_n),
        .start        (sys_start_act_read),
        .burst_length (act_addrgen_burst_length),
        .done         (act_addrgen_done),
        .rd_en        (act_addrgen_rd_en),
        .rd_addr      (act_addrgen_rd_addr)
    );

    assign act_core_re   = act_addrgen_rd_en;
    assign act_core_addr = act_addrgen_rd_addr;

    // act_t  act_vector [ROWS-1:0];
    // act_t  array_act_left [ROWS-1:0];
    // act_t  array_act_right [ROWS-1:0];
    // psum_t array_psum_top [COLS-1:0];
    // psum_t array_psum_bottom [COLS-1:0];
    // psum_t result_psum [COLS-1:0];


    // // packed array representation 
    // act_t  [ROWS-1:0] act_vector;
    // act_t  [ROWS-1:0] array_act_left;
    // act_t  [ROWS-1:0] array_act_right;
    // psum_t [COLS-1:0] array_psum_top;
    // psum_t [COLS-1:0] array_psum_bottom;
    // psum_t [COLS-1:0] result_psum;


    act_vector_t  act_vector;
    act_vector_t  array_act_left;
    act_vector_t  array_act_right;
    psum_vector_t array_psum_top;
    psum_vector_t array_psum_bottom;
    psum_vector_t result_psum;
    


    logic                       act_rd_en_d;
    logic [BRAM_ADDR_WIDTH-1:0] act_rd_addr_d;
    logic                       act_vector_valid;
    logic                       skew_active;
    logic [COMP_COUNTER_W-1:0]  skew_counter;
    logic                       capture_active;
    logic [COMP_COUNTER_W-1:0]  capture_counter;
    logic                       compute_capture_done;

    always_comb begin : act_skew_mux
        int row_i;

        for (row_i = 0; row_i < ROWS; row_i++) begin
            array_act_left[row_i] = '0;
        end

        if (skew_active) begin
            for (row_i = 0; row_i < ROWS; row_i++) begin
                if (skew_counter == (row_i * MAC_PIPELINE_GAP)) begin
                    array_act_left[row_i] = act_vector[row_i];
                end
            end
        end
    end

    genvar psum_col;
    generate
        for (psum_col = 0; psum_col < COLS; psum_col++) begin : gen_psum_top_zero
            assign array_psum_top[psum_col] = '0;
        end
    endgenerate

    always_ff @(posedge clk) begin : activation_and_capture_proc
        int lane_i;
        int flat_i;
        int row_i;
        int col_i;

        if (!core_rst_n) begin
            act_rd_en_d          <= 1'b0;
            act_rd_addr_d        <= '0;
            act_vector_valid     <= 1'b0;
            skew_active          <= 1'b0;
            skew_counter         <= '0;
            capture_active       <= 1'b0;
            capture_counter      <= '0;
            compute_capture_done <= 1'b0;

            for (row_i = 0; row_i < ROWS; row_i++) begin
                act_vector[row_i] <= '0;
            end

            for (col_i = 0; col_i < COLS; col_i++) begin
                result_psum[col_i] <= '0;
            end
        end else begin
            act_vector_valid <= 1'b0;
            act_rd_en_d      <= act_addrgen_rd_en;
            act_rd_addr_d    <= act_addrgen_rd_addr;

            if (state == ST_COMPUTE_START) begin
                act_rd_en_d          <= 1'b0;
                act_rd_addr_d        <= '0;
                act_vector_valid     <= 1'b0;
                skew_active          <= 1'b0;
                skew_counter         <= '0;
                capture_active       <= 1'b0;
                capture_counter      <= '0;
                compute_capture_done <= 1'b0;

                for (row_i = 0; row_i < ROWS; row_i++) begin
                    act_vector[row_i] <= '0;
                end

                for (col_i = 0; col_i < COLS; col_i++) begin
                    result_psum[col_i] <= '0;
                end
            end else begin
                if (act_rd_en_d) begin
                    for (lane_i = 0; lane_i < LANES_PER_WORD; lane_i++) begin
                        flat_i = (act_rd_addr_d * LANES_PER_WORD) + lane_i;
                        if (flat_i < ROWS) begin
                            act_vector[flat_i] <= act_t'(act_core_dout[(lane_i * 8) +: 8]);
                        end
                    end

                    if (act_rd_addr_d == bram_addr_from_int(ACT_WORDS - 1)) begin
                        act_vector_valid <= 1'b1;
                    end
                end

                if (act_vector_valid) begin
                    skew_active     <= 1'b1;
                    skew_counter    <= '0;
                    capture_active  <= 1'b1;
                    capture_counter <= '0;
                end else begin
                    if (skew_active) begin
                        if (skew_counter == LAST_SKEW_CYCLE) begin
                            skew_active <= 1'b0;
                        end else begin
                            skew_counter <= skew_counter + 1'b1;
                        end
                    end

                    if (capture_active) begin
                        for (col_i = 0; col_i < COLS; col_i++) begin
                            if (capture_counter == (LAST_SKEW_CYCLE + col_i + MAC_RESULT_LATENCY)) begin
                                result_psum[col_i] <= array_psum_bottom[col_i];
                            end
                        end

                        if (capture_counter == (LAST_CAPTURE_CYCLE + POST_PIPELINE_LATENCY)) begin
                            capture_active       <= 1'b0;
                            compute_capture_done <= 1'b1;
                        end else begin
                            capture_counter <= capture_counter + 1'b1;
                        end
                    end
                end
            end
        end
    end

    systolic_array_2d #(
        .ROWS (ROWS),
        .COLS (COLS)
    ) u_systolic_array (
        .clk             (clk),
        .rst_n           (core_rst_n),
        .en              (sys_array_en),
        .setup_mode      (sys_setup_mode),
        .i_act_left      (array_act_left),
        .i_weight_matrix (weight_matrix),
        .i_psum_top      (array_psum_top),
        .o_act_right     (array_act_right),
        .o_psum_bottom   (array_psum_bottom)
    );

    // Scalar post-processors are replicated once per output column.
    act_t post_act [COLS-1:0];
    logic post_en;

    assign post_en = capture_active;

    genvar post_col;
    generate
        for (post_col = 0; post_col < COLS; post_col++) begin : gen_post_process
            cnn_post_process u_post_process (
                .clk     (clk),
                .rst_n   (core_rst_n),
                .en      (post_en),
                .i_psum  (result_psum[post_col]),
                .i_bias  (psum_t'(bias_val)),
                .i_shift (shift_val),
                .o_act   (post_act[post_col])
            );
        end
    endgenerate

    // Output BRAM and AXI writeback.
    logic                       out_bram_we_a;
    logic [BRAM_ADDR_WIDTH-1:0] out_store_idx;
    logic [AXI_DATA_WIDTH-1:0]  out_bram_din_a;
    logic [AXI_DATA_WIDTH-1:0]  out_bram_dout_a;
    logic [BRAM_ADDR_WIDTH-1:0] dma_wr_bram_addr;
    logic [AXI_DATA_WIDTH-1:0]  dma_wr_bram_dout;
    logic                       dma_wr_start;
    logic                       dma_wr_done;

    assign out_bram_we_a = (state == ST_STORE_OUT);

    always_comb begin : out_pack_proc
        int lane_i;
        int flat_i;

        out_bram_din_a = '0;
        for (lane_i = 0; lane_i < LANES_PER_WORD; lane_i++) begin
            flat_i = (out_store_idx * LANES_PER_WORD) + lane_i;
            if (flat_i < COLS) begin
                out_bram_din_a[(lane_i * 8) +: 8] = post_act[flat_i];
            end
        end
    end

    dp_bram #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_out_bram (
        .clk    (clk),
        .we_a   (out_bram_we_a),
        .addr_a (out_store_idx),
        .din_a  (out_bram_din_a),
        .dout_a (out_bram_dout_a),
        .we_b   (1'b0),
        .addr_b (dma_wr_bram_addr),
        .din_b  ('0),
        .dout_b (dma_wr_bram_dout)
    );

    assign dma_wr_start = (state == ST_WR_OUT_START);

    cnn_dma_write #(
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .BRAM_ADDR_WIDTH (BRAM_ADDR_WIDTH)
    ) u_dma_write (
        .clk           (clk),
        .rst_n         (core_rst_n),
        .start         (dma_wr_start),
        .base_addr     (out_base_ptr),
        .burst_len     (axi_len_from_words(OUT_WORDS)),
        .done          (dma_wr_done),
        .bram_addr     (dma_wr_bram_addr),
        .bram_dout     (dma_wr_bram_dout),
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

    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (core_start) begin
                    next_state = ST_RD_ACT_START;
                end
            end

            ST_RD_ACT_START: begin
                next_state = ST_RD_ACT_WAIT;
            end

            ST_RD_ACT_WAIT: begin
                if (dma_rd_done) begin
                    next_state = ST_SWAP_ACT;
                end
            end

            ST_SWAP_ACT: begin
                next_state = ST_RD_WGT_START;
            end

            ST_RD_WGT_START: begin
                next_state = ST_RD_WGT_WAIT;
            end

            ST_RD_WGT_WAIT: begin
                if (dma_rd_done) begin
                    next_state = ST_SWAP_WGT;
                end
            end

            ST_SWAP_WGT: begin
                next_state = ST_WGT_RD_REQ;
            end

            ST_WGT_RD_REQ: begin
                next_state = ST_WGT_RD_CAP;
            end

            ST_WGT_RD_CAP: begin
                if (weight_word_idx == bram_addr_from_int(WEIGHT_WORDS - 1)) begin
                    next_state = ST_COMPUTE_START;
                end else begin
                    next_state = ST_WGT_RD_REQ;
                end
            end

            ST_COMPUTE_START: begin
                next_state = ST_COMPUTE_WAIT;
            end

            ST_COMPUTE_WAIT: begin
                if (sys_done && compute_capture_done) begin
                    next_state = ST_STORE_OUT;
                end
            end

            ST_STORE_OUT: begin
                if (out_store_idx == bram_addr_from_int(OUT_WORDS - 1)) begin
                    next_state = ST_WR_OUT_START;
                end
            end

            ST_WR_OUT_START: begin
                next_state = ST_WR_OUT_WAIT;
            end

            ST_WR_OUT_WAIT: begin
                if (dma_wr_done) begin
                    next_state = ST_DONE;
                end
            end

            ST_DONE: begin
                next_state = ST_IDLE;
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!core_rst_n) begin
            state           <= ST_IDLE;
            read_target     <= TARGET_ACT;
            weight_word_idx <= '0;
            out_store_idx   <= '0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    if (core_start) begin
                        read_target     <= TARGET_ACT;
                        weight_word_idx <= '0;
                        out_store_idx   <= '0;
                    end
                end

                ST_RD_ACT_START: begin
                    read_target <= TARGET_ACT;
                end

                ST_RD_WGT_START: begin
                    read_target <= TARGET_WGT;
                end

                ST_WGT_RD_CAP: begin
                    if (weight_word_idx == bram_addr_from_int(WEIGHT_WORDS - 1)) begin
                        weight_word_idx <= '0;
                    end else begin
                        weight_word_idx <= weight_word_idx + 1'b1;
                    end
                end

                ST_STORE_OUT: begin
                    if (out_store_idx == bram_addr_from_int(OUT_WORDS - 1)) begin
                        out_store_idx <= '0;
                    end else begin
                        out_store_idx <= out_store_idx + 1'b1;
                    end
                end

                ST_DONE: begin
                    read_target <= TARGET_ACT;
                end

                default: begin
                    // Hold registered control values.
                end
            endcase
        end
    end

endmodule
