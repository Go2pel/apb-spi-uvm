`timescale 1ns / 1ps

module spi_mode0_frame (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    input  logic [2:0] byte_count,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       rx_byte_valid,
    output logic       load_next_byte,
    output logic       frame_complete,
    output logic       busy,
    output logic       done,
    output logic       spi_cs_n,
    output logic       spi_sck,
    output logic       spi_mosi,
    input  logic       spi_miso
);
    typedef enum logic [1:0] {IDLE, TRANSFER, CS_HOLD} state_t;
    state_t state;

    // Four PCLK cycles per SCK half-period.
    localparam logic [1:0] HALF_PERIOD_LAST = 2'd3;

    logic [1:0] divider;
    logic [2:0] bit_index;
    logic [2:0] bytes_remaining;
    logic [7:0] tx_shift;
    logic [7:0] rx_shift;

    assign busy           = (state != IDLE);
    assign spi_cs_n       = !busy;
    assign spi_mosi       = busy && tx_shift[7];
    assign rx_data        = rx_shift;
    assign rx_byte_valid  = (state == TRANSFER) && (divider == HALF_PERIOD_LAST)
                            && spi_sck && (bit_index == 3'd7);
    assign load_next_byte = rx_byte_valid && (bytes_remaining > 3'd1);
    assign frame_complete = (state == CS_HOLD) && (divider == HALF_PERIOD_LAST);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            divider         <= '0;
            bit_index       <= '0;
            bytes_remaining <= '0;
            tx_shift        <= '0;
            rx_shift        <= '0;
            spi_sck         <= 1'b0;
            done            <= 1'b0;
        end else if (state == IDLE) begin
            if (start) begin
                state           <= TRANSFER;
                divider         <= '0;
                bit_index       <= '0;
                bytes_remaining <= byte_count;
                tx_shift        <= tx_data;
                rx_shift        <= '0;
                done            <= 1'b0;
            end
        end else if (divider == HALF_PERIOD_LAST) begin
            divider <= '0;

            if (state == CS_HOLD) begin
                state   <= IDLE;
                done    <= 1'b1;
            end else if (!spi_sck) begin
                spi_sck  <= 1'b1;
                rx_shift <= {rx_shift[6:0], spi_miso};
            end else begin
                spi_sck <= 1'b0;

                if (load_next_byte) begin
                    bytes_remaining <= bytes_remaining - 3'd1;
                    tx_shift        <= tx_data;
                    bit_index       <= '0;
                end else if (rx_byte_valid) begin
                    state <= CS_HOLD;
                end else begin
                    tx_shift  <= {tx_shift[6:0], 1'b0};
                    bit_index <= bit_index + 3'd1;
                end
            end
        end else begin
            divider <= divider + 2'd1;
        end
    end
endmodule
