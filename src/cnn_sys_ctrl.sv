`timescale 1ns / 1ps

module cnn_sys_ctrl #(
    parameter int PIPELINE_DEPTH = 5 
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // External Control
    input  logic        start,
    output logic        sys_done,
    
    // Datapath Control
    output logic        array_en,
    output logic        setup_mode,
    
    // Address Generator Control
    output logic        start_act_read,
    input  logic        act_read_done
);

    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        SETUP   = 3'b001, 
        COMPUTE = 3'b010, 
        DRAIN   = 3'b011, 
        DONE    = 3'b100
    } state_t;

    state_t state, next_state;
    logic [7:0] drain_counter;

    // 1. State Register
    always_ff @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // 2. Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (start) next_state = SETUP;
            SETUP:   next_state = COMPUTE; 
            COMPUTE: if (act_read_done) next_state = DRAIN;
            DRAIN:   if (drain_counter == PIPELINE_DEPTH) next_state = DONE;
            DONE:    next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // 3. Datapath Outputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            array_en       <= 1'b0;
            setup_mode     <= 1'b0;
            start_act_read <= 1'b0;
            sys_done       <= 1'b0;
            drain_counter  <= '0;
        end else begin
            // Default assignments
            start_act_read <= 1'b0;
            sys_done       <= 1'b0;
            
            case (next_state)
                IDLE: begin
                    array_en      <= 1'b0;
                    setup_mode    <= 1'b0;
                    drain_counter <= '0;
                end
                SETUP: begin
                    array_en   <= 1'b1;
                    setup_mode <= 1'b1;
                end
                COMPUTE: begin
                    array_en   <= 1'b1;
                    setup_mode <= 1'b0;
                    // Fire the 1-cycle pulse precisely on entry to COMPUTE
                    if (state == SETUP) begin
                        start_act_read <= 1'b1;
                    end
                end
                DRAIN: begin
                    array_en <= 1'b1;
                    // Start counting on entry, keep incrementing while inside
                    if (state != DRAIN) drain_counter <= 8'd1;
                    else                drain_counter <= drain_counter + 1'b1;
                end
                DONE: begin
                    array_en <= 1'b0;
                    sys_done <= 1'b1;
                end
            endcase
        end
    end
endmodule