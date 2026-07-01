`timescale 1ns / 1ps

module cnn_post_process
    import cnn_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,
    
    // Inputs from Systolic Array & Memory
    input  psum_t       i_psum,
    input  psum_t       i_bias,
    input  logic [4:0]  i_shift, // Dynamic shift value for scaling
    
    // Output back to Memory
    output act_t        o_act
);

    // Pipeline Registers
    psum_t biased_psum;
    act_t  final_act;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            biased_psum <= '0;
            final_act   <= '0;
        end else if (en) begin
            
            // --- Stage 1: Bias Addition ---
            biased_psum <= i_psum + i_bias;
            
            // --- Stage 2: ReLU, Shift, and Saturation ---
            // If the 31st bit (Sign Bit) is 1, the number is negative.
            if (biased_psum[31]) begin
                final_act <= '0; // ReLU: Negative becomes 0
            end else begin
                // It's positive. Shift it down to scale it.
                logic [31:0] shifted_val;
                shifted_val = biased_psum >> i_shift;
                
                // Saturation: If it's larger than what an 8-bit signed integer can hold (127), clamp it.
                if (shifted_val > 32'd127) begin
                    final_act <= 8'd127;
                end else begin
                    final_act <= shifted_val[7:0];
                end
            end
            
        end
    end

    assign o_act = final_act;

endmodule