`timescale 1ns / 1ps

module cnn_csr (
    input  logic        clk,
    input  logic        rst_n,

    // CPU Bus Interface (Generic Memory Mapped)
    input  logic        wr_en,
    input  logic [7:0]  wr_addr, 
    input  logic [31:0] wr_data,
    
    input  logic        rd_en,
    input  logic [7:0]  rd_addr,
    output logic [31:0] rd_data,

    // Hardware Interface (Outputs to the rest of the CNN Core)
    output logic        core_start,
    output logic        core_soft_rst,
    output logic [31:0] act_base_ptr,
    output logic [31:0] wt_base_ptr,
    output logic [31:0] out_base_ptr,
    output logic [31:0] bias_val,
    output logic [4:0]  shift_val,
    
    // Hardware Interface (Inputs from the CNN Core)
    input  logic        core_done,
    input  logic        core_busy
);

    // Register Storage
    logic [31:0] reg_ctrl;
    logic [31:0] reg_act_base;
    logic [31:0] reg_wt_base;
    logic [31:0] reg_out_base;
    logic [31:0] reg_quant;

    // Output assignments to hardware
    assign core_start    = reg_ctrl[0];
    assign core_soft_rst = reg_ctrl[1];
    assign act_base_ptr  = reg_act_base;
    assign wt_base_ptr   = reg_wt_base;
    assign out_base_ptr  = reg_out_base;
    assign bias_val      = reg_quant[31:16];
    assign shift_val     = reg_quant[4:0];

    // --- Write Logic ---
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_ctrl     <= '0;
            reg_act_base <= '0;
            reg_wt_base  <= '0;
            reg_out_base <= '0;
            reg_quant    <= '0;
        end else begin
            // Self-clearing start bit (so the CPU doesn't have to write 0 to stop it)
            if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0; 
            
            // CPU Write Operations
            if (wr_en) begin
                case (wr_addr)
                    8'h00: reg_ctrl     <= wr_data;
                    8'h08: reg_act_base <= wr_data;
                    8'h0C: reg_wt_base  <= wr_data;
                    8'h10: reg_out_base <= wr_data;
                    8'h14: reg_quant    <= wr_data;
                    default: ; // Do nothing for invalid addresses
                endcase
            end
        end
    end

    // --- Read Logic (Combinatorial for zero-latency bus response) ---
    always_comb begin
        rd_data = 32'd0;
        if (rd_en) begin
            case (rd_addr)
                8'h00: rd_data = reg_ctrl;
                8'h04: rd_data = {30'd0, core_busy, core_done}; // Live status from hardware
                8'h08: rd_data = reg_act_base;
                8'h0C: rd_data = reg_wt_base;
                8'h10: rd_data = reg_out_base;
                8'h14: rd_data = reg_quant;
                default: rd_data = 32'd0;
            endcase
        end
    end

endmodule