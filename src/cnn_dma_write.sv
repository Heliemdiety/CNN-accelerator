`timescale 1ns / 1ps

module cnn_dma_write #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BRAM_ADDR_WIDTH = 10
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      start,
    input  logic [AXI_ADDR_WIDTH-1:0] base_addr,
    input  logic [7:0]                burst_len, 
    output logic                      done,

    output logic [BRAM_ADDR_WIDTH-1:0] bram_addr,
    input  logic [AXI_DATA_WIDTH-1:0]  bram_dout,

    // AXI4 Write Address (AW)
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,

    // AXI4 Write Data (W)
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]                m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,

    // AXI4 Write Response (B)
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready
);

    assign m_axi_awsize  = 3'b010; 
    assign m_axi_awburst = 2'b01;  
    assign m_axi_wstrb   = 4'b1111; 

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        ISSUE_AW  = 3'b001,
        WAIT_BRAM = 3'b010, // Allows BRAM 1 cycle to output data
        FETCH_MEM = 3'b011, // Latches data from BRAM
        PUSH_AXI  = 3'b100, // Handshakes with the bus
        WAIT_RESP = 3'b101
    } state_t;

    state_t state;
    logic [BRAM_ADDR_WIDTH-1:0] local_addr_ptr;
    logic [7:0] words_sent;

    assign bram_addr = local_addr_ptr;

    // THE FIX: Monolithic Single-Block FSM
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            m_axi_awvalid  <= 1'b0;
            m_axi_awaddr   <= '0;
            m_axi_awlen    <= '0;
            m_axi_wvalid   <= 1'b0;
            m_axi_wdata    <= '0;
            m_axi_wlast    <= 1'b0;
            m_axi_bready   <= 1'b0;
            local_addr_ptr <= '0;
            words_sent     <= '0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0; // Default clear

            case (state)
                IDLE: begin
                    if (start) begin
                        m_axi_awvalid  <= 1'b1;
                        m_axi_awaddr   <= base_addr;
                        m_axi_awlen    <= burst_len;
                        local_addr_ptr <= '0; // Point to Word 0
                        words_sent     <= '0;
                        state          <= ISSUE_AW;
                    end
                end
                
                ISSUE_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        state         <= WAIT_BRAM;
                    end
                end
                
                WAIT_BRAM: begin
                    // The BRAM is currently fetching the data at local_addr_ptr.
                    // We wait 1 clock cycle for the data to arrive on bram_dout.
                    state <= FETCH_MEM;
                end

                FETCH_MEM: begin
                    // Data is valid. Lock it into the AXI holding register.
                    m_axi_wdata  <= bram_dout;
                    m_axi_wvalid <= 1'b1;
                    m_axi_wlast  <= (words_sent == burst_len);
                    state        <= PUSH_AXI;
                end
                
                PUSH_AXI: begin
                    // Wait for the Slave to accept the locked data
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        
                        if (words_sent == burst_len) begin
                            m_axi_bready <= 1'b1;
                            state        <= WAIT_RESP;
                        end else begin
                            local_addr_ptr <= local_addr_ptr + 1'b1;
                            words_sent     <= words_sent + 1'b1;
                            state          <= WAIT_BRAM; // Loop for next word
                        end
                    end
                end
                
                WAIT_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        done         <= 1'b1;
                        state        <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule