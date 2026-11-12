`timescale 1ns / 1ps

interface apb_if (input logic pclk);
    logic        preset_n = 1'b0;
    logic        psel = 1'b0;
    logic        penable = 1'b0;
    logic        pwrite = 1'b0;
    logic [7:0]  paddr = '0;
    logic [31:0] pwdata = '0;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;
endinterface

interface spi_if;
    logic cs_n;
    logic sck;
    logic mosi;
    logic miso = 1'b0;
endinterface
