`timescale 1ns / 1ps

module apb_spi_smoke;
    localparam logic [7:0] TXDATA = 8'h00;
    localparam logic [7:0] CTRL   = 8'h04;
    localparam logic [7:0] STATUS = 8'h08;
    localparam logic [7:0] RXDATA = 8'h0c;

    logic        pclk = 1'b0;
    logic        preset_n = 1'b0;
    logic        psel = 1'b0;
    logic        penable = 1'b0;
    logic        pwrite = 1'b0;
    logic [7:0]  paddr = '0;
    logic [31:0] pwdata = '0;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;
    logic        spi_cs_n;
    logic        spi_sck;
    logic        spi_mosi;
    logic        spi_miso = 1'b0;
    logic [31:0] read_data;

    apb_spi dut (.*);

    always #5 pclk = !pclk;

    task automatic apb_access (
        input  logic        write_access,
        input  logic [7:0]  address,
        input  logic [31:0] write_data,
        input  logic        expected_error,
        output logic [31:0] data
    );
        @(negedge pclk);
        psel    = 1'b1;
        penable = 1'b0;
        pwrite  = write_access;
        paddr   = address;
        pwdata  = write_data;

        @(posedge pclk);
        if (pslverr !== 1'b0)
            $fatal(1, "Unexpected APB error in setup at %h", address);

        @(negedge pclk);
        penable = 1'b1;

        @(posedge pclk);
        while (pready !== 1'b1)
            @(posedge pclk);

        if (pslverr !== expected_error)
            $fatal(1, "APB error at %h: expected %b, got %b", address, expected_error, pslverr);
        data = prdata;

        @(negedge pclk);
        psel    = 1'b0;
        penable = 1'b0;
    endtask

    task automatic check_register (input logic [7:0] address, input logic [31:0] expected);
        logic [31:0] actual;

        apb_access(1'b0, address, '0, 1'b0, actual);
        if (actual !== expected)
            $fatal(1, "APB read at %h: expected %h, got %h", address, expected, actual);
    endtask

    task automatic spi_device (input logic [7:0] expected_mosi, input logic [7:0] response);
        logic [7:0] received;

        @(negedge spi_cs_n);
        for (int bit_number = 7; bit_number >= 0; bit_number--) begin
            spi_miso = response[bit_number];
            @(posedge spi_sck);
            if (spi_cs_n !== 1'b0)
                $fatal(1, "SPI clocked a bit outside chip select");
            received[bit_number] = spi_mosi;
            @(negedge spi_sck);
        end

        if (received !== expected_mosi)
            $fatal(1, "SPI MOSI: expected %h, got %h", expected_mosi, received);

        @(posedge spi_cs_n or posedge spi_sck);
        if (spi_cs_n !== 1'b1 || spi_sck !== 1'b0)
            $fatal(1, "Expected chip select to rise with SCK idle after eight bits");
    endtask

    task automatic run_transfer (input logic [7:0] transmit, input logic [7:0] response);
        apb_access(1'b1, TXDATA, {24'b0, transmit}, 1'b0, read_data);
        check_register(TXDATA, {24'b0, transmit});

        fork
            spi_device(transmit, response);
            begin
                apb_access(1'b1, CTRL, 32'h1, 1'b0, read_data);
                check_register(STATUS, 32'h1);
                apb_access(1'b1, CTRL, 32'h1, 1'b1, read_data);
            end
        join

        check_register(STATUS, 32'h2);
        check_register(RXDATA, {24'b0, response});
        $display("PASS SPI transfer: MOSI=%h MISO=%h", transmit, response);
    endtask

    initial begin
        repeat (3) @(negedge pclk);
        preset_n = 1'b1;

        check_register(STATUS, '0);
        check_register(RXDATA, '0);
        apb_access(1'b0, 8'h10, '0, 1'b1, read_data);
        apb_access(1'b1, RXDATA, 32'hff, 1'b1, read_data);
        check_register(RXDATA, '0);
        $display("PASS APB reset and error responses");

        run_transfer(8'ha6, 8'h3b);
        run_transfer(8'h19, 8'hd2);

        $display("PASS apb_spi_smoke");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Timed out waiting for APB or SPI activity");
    end
endmodule
