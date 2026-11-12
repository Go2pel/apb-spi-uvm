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

    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic       busy;
    logic       done;
    logic       start;
    logic       transfer;

    assign pready   = 1'b1;
    assign transfer = psel && penable && pready;
    assign start    = transfer && pwrite && (paddr == CTRL) && pwdata[0] && !busy;

    always_comb begin
        prdata  = '0;
        pslverr = 1'b0;

        if (transfer) begin
            case (paddr)
                TXDATA: prdata = {24'b0, tx_data};
                CTRL:   pslverr = pwrite && pwdata[0] && busy;
                STATUS: begin
                    prdata  = {30'b0, done, busy};
                    pslverr = pwrite;
                end
                RXDATA: begin
                    prdata  = {24'b0, rx_data};
                    pslverr = pwrite;
                end
                default: pslverr = 1'b1;
            endcase
        end
    end

    always_ff @(posedge pclk or negedge preset_n) begin
        if (!preset_n)
            tx_data <= '0;
        else if (transfer && pwrite && (paddr == TXDATA))
            tx_data <= pwdata[7:0];
    end

    spi_mode0_byte spi_byte (
        .clk       (pclk),
        .rst_n     (preset_n),
        .start     (start),
        .tx_data   (tx_data),
        .rx_data   (rx_data),
        .busy      (busy),
        .done      (done),
        .spi_cs_n  (spi_cs_n),
        .spi_sck   (spi_sck),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)
    );
endmodule
