`timescale 1ns / 1ps

module apb_spi_uvm_tb;
    import uvm_pkg::*;
    import apb_spi_pkg::*;

    localparam logic [31:0] SPI_RESPONSE = 32'hd26cb705;
    logic pclk = 1'b0;
    int unsigned response_index = 0;
    int unsigned random_frames = 0;
    logic [31:0] response_word = SPI_RESPONSE;

    apb_if apb_bus(pclk);
    spi_if spi_bus(apb_bus.preset_n);

    apb_spi dut (
        .pclk      (pclk),
        .preset_n  (apb_bus.preset_n),
        .psel      (apb_bus.psel),
        .penable   (apb_bus.penable),
        .pwrite    (apb_bus.pwrite),
        .paddr     (apb_bus.paddr),
        .pwdata    (apb_bus.pwdata),
        .prdata    (apb_bus.prdata),
        .pready    (apb_bus.pready),
        .pslverr   (apb_bus.pslverr),
        .spi_cs_n  (spi_bus.cs_n),
        .spi_sck   (spi_bus.sck),
        .spi_mosi  (spi_bus.mosi),
        .spi_miso  (spi_bus.miso)
    );

    apb_spi_assertions protocol_checks (
        .pclk      (pclk),
        .preset_n  (apb_bus.preset_n),
        .psel      (apb_bus.psel),
        .penable   (apb_bus.penable),
        .pwrite    (apb_bus.pwrite),
        .paddr     (apb_bus.paddr),
        .pwdata    (apb_bus.pwdata),
        .pready    (apb_bus.pready),
        .pslverr   (apb_bus.pslverr),
        .spi_cs_n  (spi_bus.cs_n),
        .spi_sck   (spi_bus.sck),
        .spi_mosi  (spi_bus.mosi)
    );

    always #5 pclk = !pclk;

    // A Mode 0 slave presents its first bit at CS assertion and changes data on SCK falls.
    always @(spi_bus.cs_n or negedge spi_bus.sck or negedge apb_bus.preset_n) begin
        if (!apb_bus.preset_n || spi_bus.cs_n) begin
            response_index <= 0;
            spi_bus.miso <= 1'b0;
        end else if (response_index == 0) begin
            logic [31:0] next_response;
            next_response = (random_frames != 0) ? $urandom() : SPI_RESPONSE;
            response_word <= next_response;
            spi_bus.miso <= next_response[31];
            response_index <= 1;
        end else if (response_index < 32) begin
            spi_bus.miso <= response_word[31 - response_index];
            response_index <= response_index + 1;
        end
    end

    initial begin
        repeat (3) @(negedge pclk);
        apb_bus.preset_n = 1'b1;
    end

    initial begin
        void'($value$plusargs("random_frames=%d", random_frames));
        uvm_config_db#(virtual apb_if)::set(null, "*", "apb_bus", apb_bus);
        uvm_config_db#(virtual spi_if)::set(null, "*", "spi_bus", spi_bus);
        uvm_config_db#(int unsigned)::set(null, "uvm_test_top", "random_frames", random_frames);
        run_test("apb_spi_test");
    end

    initial begin
        #500000;
        $fatal(1, "UVM testbench watchdog expired");
    end
endmodule
