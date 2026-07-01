`timescale 1ns / 1ps

module address_gen #(
    parameter int ADDR_WIDTH = 10
)(
    input  logic                  clk,
    input  logic                  rst_n,
    
    // Control Interface
    input  logic                  start,
    input  logic [ADDR_WIDTH-1:0] burst_length,
    output logic                  done,
    
    // Memory Interface
    output logic                  rd_en,
    output logic [ADDR_WIDTH-1:0] rd_addr
);

    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        READING = 2'b01,
        DONE    = 2'b10
    } state_t;

    state_t state, next_state;
    logic [ADDR_WIDTH-1:0] counter;

    // FSM State Register
    always_ff @(posedge clk) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // FSM Next State Logic
    always_comb begin
        next_state = state; 
        case (state)
            IDLE:    if (start) next_state = READING;
            READING: if (counter == burst_length - 1) next_state = DONE;
            DONE:    next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Datapath (Address Counter)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            counter <= '0;
            rd_en   <= 1'b0;
            done    <= 1'b0;
        end else begin
            // Default assignments
            rd_en <= 1'b0;
            done  <= 1'b0;
            
            // THE FIX: Switch strictly on current state to protect the counter
            case (state) 
                IDLE: begin
                    counter <= '0;
                    if (start) rd_en <= 1'b1; // Prep first read for next cycle
                end
                READING: begin
                    if (counter == burst_length - 1) begin
                        done <= 1'b1;
                    end else begin
                        rd_en <= 1'b1;
                        counter <= counter + 1'b1;
                    end
                end
                DONE: begin
                    // Wait for state to auto-clear back to IDLE
                end
            endcase
        end
    end

    assign rd_addr = counter;

endmodule