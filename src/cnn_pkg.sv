package cnn_pkg;
    // Data Types: Strict INT8 quantization
    typedef logic signed [7:0]  act_t;
    typedef logic signed [7:0]  weight_t;
    typedef logic signed [31:0] psum_t;
    
    // Array Dimensions (Parameterized for scalability)
    localparam int ARRAY_ROWS = 8;
    localparam int ARRAY_COLS = 8;

    // THE ARCHITECTURE UPGRADE: 
    // Lock every single array structure globally.
    typedef act_t    [ARRAY_ROWS-1:0]                   act_vector_t;
    typedef psum_t   [ARRAY_COLS-1:0]                   psum_vector_t;
    typedef weight_t [ARRAY_ROWS-1:0][ARRAY_COLS-1:0]   wgt_matrix_t;


endpackage