`timescale 1ns / 1ps

module mac_pe
    import cnn_pkg::*;
(
    input  logic    clk,
    input  logic    rst_n,
    input  logic    en,             
    input  logic    setup_mode,     
    input  act_t    i_act,          
    input  weight_t i_weight,       
    input  psum_t   i_psum,         
    
    output act_t    o_act,          
    output psum_t   o_psum          
);

    // DSP48 mapped registers
    weight_t            weight_reg;
    act_t               act_reg;
    logic signed [15:0] mult_reg;
    psum_t              psum_reg;
    
    // Delay registers to align i_psum with the multiplier latency
    psum_t              psum_delay1;
    psum_t              psum_delay2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_reg  <= '0;
            act_reg     <= '0;
            mult_reg    <= '0;
            psum_reg    <= '0;
            psum_delay1 <= '0;
            psum_delay2 <= '0;
        end else if (en) begin
            // Setup Mode
            if (setup_mode) begin
                weight_reg <= i_weight;
            end
            
            //  Stage 1 (Maps to AREG and CREG-stage-1) 
            act_reg     <= i_act;
            psum_delay1 <= i_psum; 
            
            // Stage 2 (Maps to MREG and CREG-stage-2) 
            mult_reg    <= act_reg * weight_reg;
            psum_delay2 <= psum_delay1;
            
            // Stage 3 (Maps to PREG)
            psum_reg    <= psum_delay2 + mult_reg;
        end
    end

    assign o_act  = act_reg;
    assign o_psum = psum_reg;

endmodule