`timescale 1ns / 1ps

module spi_fifo (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       push,
    input  logic [7:0] push_data,
    input  logic       pop,
    output logic [7:0] front_data,
    output logic [2:0] level
);
    logic [7:0] entries [0:3];
    logic [1:0] write_ptr;
    logic [1:0] read_ptr;
    logic       push_accepted;
    logic       pop_accepted;

    assign push_accepted = push && (level != 3'd4);
    assign pop_accepted  = pop && (level != 3'd0);
    assign front_data    = (level == 3'd0) ? 8'd0 : entries[read_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr  <= '0;
            level     <= '0;
        end else begin
            if (push_accepted) begin
                entries[write_ptr] <= push_data;
                write_ptr          <= write_ptr + 2'd1;
            end

            if (pop_accepted)
                read_ptr <= read_ptr + 2'd1;

            case ({push_accepted, pop_accepted})
                2'b10: level <= level + 3'd1;
                2'b01: level <= level - 3'd1;
                default: ;
            endcase
        end
    end
endmodule
