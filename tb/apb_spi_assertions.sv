`timescale 1ns / 1ps

module apb_spi_assertions (
    input logic        pclk,
    input logic        preset_n,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [7:0]  paddr,
    input logic [31:0] pwdata,
    input logic        pready,
    input logic        pslverr,
    input logic        spi_cs_n,
    input logic        spi_sck,
    input logic        spi_mosi
);
    apb_setup_to_access: assert property (
        @(posedge pclk) disable iff (!preset_n)
        psel && !penable |=> psel && penable && $stable({paddr, pwrite}) &&
                            (!pwrite || $stable(pwdata))
    ) else $fatal(1, "APB setup must be followed by access with stable request signals");

    apb_zero_wait: assert property (
        @(posedge pclk) disable iff (!preset_n)
        psel && penable |-> pready
    ) else $fatal(1, "This APB peripheral must complete every access without a wait state");

    apb_error_on_completion: assert property (
        @(posedge pclk) disable iff (!preset_n)
        pslverr |-> psel && penable && pready
    ) else $fatal(1, "PSLVERR was asserted outside a completed APB access");

    spi_clock_idle: assert property (
        @(posedge pclk) disable iff (!preset_n)
        spi_cs_n |-> !spi_sck
    ) else $fatal(1, "Mode 0 SCK was high while chip select was inactive");

    spi_select_before_clock: assert property (
        @(posedge pclk) disable iff (!preset_n)
        $fell(spi_cs_n) |-> !spi_sck
    ) else $fatal(1, "Mode 0 SCK must be low when chip select falls");

    spi_data_on_sample: assert property (
        @(posedge pclk) disable iff (!preset_n)
        !spi_cs_n && $rose(spi_sck) |-> $stable(spi_mosi)
    ) else $fatal(1, "MOSI changed on a Mode 0 sampling edge");
endmodule
