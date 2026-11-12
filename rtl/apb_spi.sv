`timescale 1ns / 1ps

module apb_spi (
    input  logic        pclk,
    input  logic        preset_n,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    output logic        spi_cs_n,
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso
);
    localparam logic [7:0] TXDATA = 8'h00;
    localparam logic [7:0] CTRL   = 8'h04;
    localparam logic [7:0] STATUS = 8'h08;
    localparam logic [7:0] RXDATA = 8'h0c;
    localparam logic [7:0] TXFIFO = 8'h10;
    localparam logic [7:0] RXFIFO = 8'h14;
    localparam logic [7:0] FIFO_LEVEL = 8'h18;

    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic       busy;
    logic       done;
    logic       start;
    logic       transfer;
    logic       fifo_requested;
    logic       fifo_active;
    logic       start_allowed;
    logic [2:0] frame_bytes;

    logic [7:0] tx_fifo_data;
    logic [7:0] rx_fifo_data;
    logic [2:0] tx_level;
    logic [2:0] rx_level;
    logic       tx_full;
    logic       rx_empty;
    logic       tx_push;
    logic       tx_pop;
    logic       rx_push;
    logic       rx_pop;

    logic [7:0] spi_tx_data;
    logic [7:0] spi_rx_data;
    logic       rx_byte_valid;
    logic       load_next_byte;
    logic       frame_complete;

    assign pready   = 1'b1;
    assign transfer = psel && penable && pready;
    assign fifo_requested = pwdata[3];
    assign frame_bytes = fifo_requested ? ({1'b0, pwdata[2:1]} + 3'd1) : 3'd1;

    // Reserve enough RX slots for the whole frame before lowering CS.
    assign start_allowed = !busy && (!fifo_requested ||
                           ((tx_level >= frame_bytes) && ((3'd4 - rx_level) >= frame_bytes)));
    assign start = transfer && pwrite && (paddr == CTRL) && pwdata[0] && start_allowed;

    assign tx_full = (tx_level == 3'd4);
    assign rx_empty = (rx_level == 3'd0);
    assign tx_push = transfer && pwrite && (paddr == TXFIFO) && !tx_full;
    assign tx_pop = (start && fifo_requested) || (load_next_byte && fifo_active);
    assign rx_push = rx_byte_valid && fifo_active;
    assign rx_pop = transfer && !pwrite && (paddr == RXFIFO) && !rx_empty;
    assign spi_tx_data = (start && !fifo_requested) ? tx_data : tx_fifo_data;

    always_comb begin
        prdata  = '0;
        pslverr = 1'b0;

        if (transfer) begin
            case (paddr)
                TXDATA: prdata = {24'b0, tx_data};
                CTRL:   pslverr = pwrite && pwdata[0] && !start_allowed;
                STATUS: begin
                    prdata  = {30'b0, done, busy};
                    pslverr = pwrite;
                end
                RXDATA: begin
                    prdata  = {24'b0, rx_data};
                    pslverr = pwrite;
                end
                TXFIFO: pslverr = !pwrite || tx_full;
                RXFIFO: begin
                    prdata  = {24'b0, rx_fifo_data};
                    pslverr = pwrite || rx_empty;
                end
                FIFO_LEVEL: begin
                    prdata  = {25'b0, rx_level, 1'b0, tx_level};
                    pslverr = pwrite;
                end
                default: pslverr = 1'b1;
            endcase
        end
    end

    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            tx_data     <= '0;
            rx_data     <= '0;
            fifo_active <= 1'b0;
        end else begin
            if (transfer && pwrite && (paddr == TXDATA))
                tx_data <= pwdata[7:0];

            if (start)
                fifo_active <= fifo_requested;

            if (frame_complete)
                rx_data <= spi_rx_data;
        end
    end

    spi_fifo tx_fifo (
        .clk        (pclk),
        .rst_n      (preset_n),
        .push       (tx_push),
        .push_data  (pwdata[7:0]),
        .pop        (tx_pop),
        .front_data (tx_fifo_data),
        .level      (tx_level)
    );

    spi_fifo rx_fifo (
        .clk        (pclk),
        .rst_n      (preset_n),
        .push       (rx_push),
        .push_data  (spi_rx_data),
        .pop        (rx_pop),
        .front_data (rx_fifo_data),
        .level      (rx_level)
    );

    spi_mode0_frame spi_frame (
        .clk            (pclk),
        .rst_n          (preset_n),
        .start          (start),
        .byte_count     (frame_bytes),
        .tx_data        (spi_tx_data),
        .rx_data        (spi_rx_data),
        .rx_byte_valid  (rx_byte_valid),
        .load_next_byte (load_next_byte),
        .frame_complete (frame_complete),
        .busy           (busy),
        .done           (done),
        .spi_cs_n       (spi_cs_n),
        .spi_sck        (spi_sck),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso)
    );
endmodule
