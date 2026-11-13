`timescale 1ns / 1ps

module apb_spi_smoke;
    localparam logic [7:0] TXDATA = 8'h00;
    localparam logic [7:0] CTRL   = 8'h04;
    localparam logic [7:0] STATUS = 8'h08;
    localparam logic [7:0] RXDATA = 8'h0c;
    localparam logic [7:0] TXFIFO = 8'h10;
    localparam logic [7:0] RXFIFO = 8'h14;
    localparam logic [7:0] FIFO_LEVEL = 8'h18;

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
    apb_spi_assertions protocol_checks (.*);

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

    task automatic spi_device (
        input int          length,
        input logic [31:0] expected_mosi,
        input logic [31:0] response
    );
        logic [31:0] received;
        time last_sck_rise;

        received = '0;
        last_sck_rise = 0;

        @(negedge spi_cs_n);
        for (int bit_number = 31; bit_number >= 32 - 8 * length; bit_number--) begin
            spi_miso = response[bit_number];
            @(posedge spi_sck or posedge spi_cs_n);
            if (spi_cs_n !== 1'b0 || spi_sck !== 1'b1)
                $fatal(1, "SPI frame ended early at bit %0d", bit_number);
            if (last_sck_rise != 0 && ($time - last_sck_rise) != 80)
                $fatal(1, "Unexpected SCK period at bit %0d", bit_number);
            last_sck_rise = $time;
            received[bit_number] = spi_mosi;
            @(negedge spi_sck);
        end

        if (received !== expected_mosi)
            $fatal(1, "SPI MOSI: expected %h, got %h", expected_mosi, received);

        @(posedge spi_cs_n or posedge spi_sck);
        if (spi_cs_n !== 1'b1 || spi_sck !== 1'b0)
            $fatal(1, "Expected chip select to rise with SCK idle after %0d bytes", length);
    endtask

    task automatic run_transfer (input logic [7:0] transmit, input logic [7:0] response);
        apb_access(1'b1, TXDATA, {24'b0, transmit}, 1'b0, read_data);
        check_register(TXDATA, {24'b0, transmit});

        fork
            spi_device(1, {transmit, 24'b0}, {response, 24'b0});
            begin
                apb_access(1'b1, CTRL, 32'h1, 1'b0, read_data);
                check_register(STATUS, 32'h1);
                apb_access(1'b1, CTRL, 32'h1, 1'b1, read_data);
            end
        join

        check_register(STATUS, 32'h2);
        check_register(RXDATA, {24'b0, response});
        check_register(RXDATA, {24'b0, response});
        check_register(FIFO_LEVEL, '0);
        $display("PASS SPI transfer: MOSI=%h MISO=%h", transmit, response);
    endtask

    task automatic enqueue (input logic [7:0] data);
        apb_access(1'b1, TXFIFO, {24'b0, data}, 1'b0, read_data);
    endtask

    task automatic check_fifos_and_frames;
        enqueue(8'hc1);
        apb_access(1'b1, CTRL, 32'hb, 1'b1, read_data);
        check_register(STATUS, 32'h2);
        check_register(FIFO_LEVEL, 32'h01);

        enqueue(8'h3e);
        enqueue(8'h84);
        enqueue(8'h51);
        apb_access(1'b1, TXFIFO, 32'hff, 1'b1, read_data);
        check_register(FIFO_LEVEL, 32'h04);

        fork
            spi_device(2, 32'hc13e0000, 32'h56b90000);
            begin
                apb_access(1'b1, CTRL, 32'hb, 1'b0, read_data);
                check_register(STATUS, 32'h1);
                apb_access(1'b1, CTRL, 32'h9, 1'b1, read_data);
                enqueue(8'h96);
            end
        join
        enqueue(8'h2b);
        check_register(FIFO_LEVEL, 32'h24);

        apb_access(1'b1, CTRL, 32'hf, 1'b1, read_data);
        check_register(STATUS, 32'h2);
        check_register(FIFO_LEVEL, 32'h24);
        check_register(RXFIFO, 32'h56);
        check_register(RXFIFO, 32'hb9);

        fork
            spi_device(4, 32'h8451962b, 32'hda29e473);
            apb_access(1'b1, CTRL, 32'hf, 1'b0, read_data);
        join
        check_register(STATUS, 32'h2);
        check_register(FIFO_LEVEL, 32'h40);
        check_register(RXDATA, 32'h73);
        check_register(RXFIFO, 32'hda);
        check_register(RXFIFO, 32'h29);
        check_register(RXFIFO, 32'he4);
        check_register(FIFO_LEVEL, 32'h10);
        $display("PASS FIFO admission, full-write protection, wraparound and continuous frames");

        enqueue(8'h6a);
        fork
            spi_device(1, 32'h6a000000, 32'hac000000);
            begin
                apb_access(1'b1, CTRL, 32'h9, 1'b0, read_data);
                repeat (8) @(posedge spi_sck);
                // The APB completion edge then coincides with the eighth falling SCK edge.
                repeat (2) @(posedge pclk);
                check_register(RXFIFO, 32'h73);
            end
        join
        check_register(FIFO_LEVEL, 32'h10);
        check_register(RXFIFO, 32'hac);
        apb_access(1'b0, RXFIFO, '0, 1'b1, read_data);
        check_register(FIFO_LEVEL, '0);
        $display("PASS simultaneous RX FIFO push and pop");
    endtask

    task automatic check_reset_during_frame;
        enqueue(8'h81);
        enqueue(8'hfe);
        apb_access(1'b1, CTRL, 32'hb, 1'b0, read_data);
        repeat (9) @(posedge spi_sck);
        check_register(FIFO_LEVEL, 32'h10);

        @(negedge pclk);
        preset_n = 1'b0;
        repeat (3) @(negedge pclk);
        if (spi_cs_n !== 1'b1 || spi_sck !== 1'b0)
            $fatal(1, "Reset did not return the SPI pins to idle");
        preset_n = 1'b1;

        check_register(STATUS, '0);
        check_register(TXDATA, '0);
        check_register(RXDATA, '0);
        check_register(FIFO_LEVEL, '0);
        apb_access(1'b0, RXFIFO, '0, 1'b1, read_data);
        $display("PASS reset during an active FIFO frame");
    endtask

    initial begin
        repeat (3) @(negedge pclk);
        preset_n = 1'b1;

        check_register(STATUS, '0);
        check_register(RXDATA, '0);
        apb_access(1'b0, 8'h1c, '0, 1'b1, read_data);
        apb_access(1'b1, RXDATA, 32'hff, 1'b1, read_data);
        check_register(RXDATA, '0);
        $display("PASS APB reset and error responses");

        run_transfer(8'ha6, 8'h3b);
        check_fifos_and_frames();
        check_reset_during_frame();
        run_transfer(8'h19, 8'hd2);

        $display("PASS apb_spi_smoke");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Timed out waiting for APB or SPI activity");
    end
endmodule
