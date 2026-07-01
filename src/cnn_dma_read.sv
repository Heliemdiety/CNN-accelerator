`timescale 1ns / 1ps

module cnn_dma_read #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BRAM_ADDR_WIDTH = 10
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Control Interface
    input  logic                      start,
    input  logic [AXI_ADDR_WIDTH-1:0] base_addr,
    input  logic [7:0]                burst_len,
    output logic                      done,

    // BRAM Write Interface
    output logic                      bram_we,
    output logic [BRAM_ADDR_WIDTH-1:0] bram_addr,
    output logic [AXI_DATA_WIDTH-1:0]  bram_din,

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
    output logic                      m_axi_rready
);

    assign m_axi_arsize  = 3'b010; // 4 bytes per beat
    assign m_axi_arburst = 2'b01;  // INCR mode

    typedef enum logic [1:0] {
        IDLE       = 2'b00,
        ISSUE_ADDR = 2'b01,
        BURST_READ = 2'b10
    } state_t;

    state_t state;
    logic [BRAM_ADDR_WIDTH-1:0] local_addr_ptr;

    // Combinatorial BRAM wiring (Directly hooked to AXI handshake)
    assign bram_we   = m_axi_rvalid && m_axi_rready;
    assign bram_addr = local_addr_ptr;
    assign bram_din  = m_axi_rdata;

    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            m_axi_arvalid  <= 1'b0;
            m_axi_araddr   <= '0;
            m_axi_arlen    <= '0;
            m_axi_rready   <= 1'b0;
            local_addr_ptr <= '0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0; // Default clear

            case (state)
                IDLE: begin
                    local_addr_ptr <= '0;
                    if (start) begin
                        m_axi_arvalid <= 1'b1;
                        m_axi_araddr  <= base_addr;
                        m_axi_arlen   <= burst_len;
                        state         <= ISSUE_ADDR;
                    end
                end
                
                ISSUE_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1; 
                        state         <= BURST_READ;
                    end
                end
                
                BURST_READ: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        local_addr_ptr <= local_addr_ptr + 1'b1;
                        
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            done         <= 1'b1; 
                            state        <= IDLE; 
                        end
                    end
                end
            endcase
        end
    end
endmodule