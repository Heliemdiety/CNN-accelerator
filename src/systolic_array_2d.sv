`timescale 1ns / 1ps

module systolic_array_2d
    import cnn_pkg::*;
#(
    parameter int ROWS = 2, //for easy simulation
    parameter int COLS = 2
)(
    input  logic                                clk,
    input  logic                                rst_n,
    input  logic                                en,
    input  logic                                setup_mode,
    
    // // Inputs entering the edges of the array
    // input  act_t    [ROWS-1:0]                  i_act_left,
    // input  weight_t [ROWS-1:0][COLS-1:0]        i_weight_matrix,
    // input  psum_t   [COLS-1:0]                  i_psum_top,
    
    // // Outputs exiting the edges of the array
    // output act_t    [ROWS-1:0]                  o_act_right,
    // output psum_t   [COLS-1:0]                  o_psum_bottom

    input  act_vector_t  i_act_left,
    input  wgt_matrix_t  i_weight_matrix,
    input  psum_vector_t i_psum_top,
    
    output act_vector_t  o_act_right,
    output psum_vector_t o_psum_bottom


);

    // Internal interconnect wires connecting the PEs
    act_t  act_wire  [ROWS-1:0][COLS:0];
    psum_t psum_wire [ROWS:0][COLS-1:0];

    // Bind inputs to the edges of the internal wire mesh
    genvar r, c;
    generate
        // Connect left-side activations
        for (r = 0; r < ROWS; r++) begin : gen_act_inputs
            assign act_wire[r][0] = i_act_left[r];
        end
        // Connect top-side partial sums
        for (c = 0; c < COLS; c++) begin : gen_psum_inputs
            assign psum_wire[0][c] = i_psum_top[c];
        end
    endgenerate

    // Generate the 2D Grid of PEs
    generate
        for (r = 0; r < ROWS; r++) begin : row_gen
            for (c = 0; c < COLS; c++) begin : col_gen
                
                mac_pe u_pe (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .en         (en),
                    .setup_mode (setup_mode),
                    
                    // Inputs from Left and Top
                    .i_act      (act_wire[r][c]),
                    .i_weight   (i_weight_matrix[r][c]),
                    .i_psum     (psum_wire[r][c]),
                    
                    // Outputs to Right and Bottom
                    .o_act      (act_wire[r][c+1]),
                    .o_psum     (psum_wire[r+1][c])
                );
                
            end
        end
    endgenerate

    // Bind outputs from the edges of the internal wire mesh
    generate
        // Connect right-side activations
        for (r = 0; r < ROWS; r++) begin : gen_act_outputs
            assign o_act_right[r] = act_wire[r][COLS];
        end
        // Connect bottom-side partial sums
        for (c = 0; c < COLS; c++) begin : gen_psum_outputs
            assign o_psum_bottom[c] = psum_wire[ROWS][c];
        end
    endgenerate

endmodule