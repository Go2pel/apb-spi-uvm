`timescale 1ns / 1ps

package apb_spi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam logic [7:0] TXDATA = 8'h00;
    localparam logic [7:0] CTRL   = 8'h04;
    localparam logic [7:0] STATUS = 8'h08;
    localparam logic [7:0] RXDATA = 8'h0c;
    localparam logic [7:0] TXFIFO = 8'h10;
    localparam logic [7:0] RXFIFO = 8'h14;
    typedef logic [7:0] spi_byte_t;
    typedef enum {BUSY_START, FIFO_START, TX_FULL, RX_EMPTY} apb_error_t;

    class apb_item extends uvm_sequence_item;
        `uvm_object_utils(apb_item)

        bit          is_write;
        logic [7:0]  addr;
        logic [31:0] data;
        logic        error;

        function new(string name = "apb_item");
            super.new(name);
        endfunction
    endclass

    class apb_driver extends uvm_driver #(apb_item);
        `uvm_component_utils(apb_driver)

        virtual apb_if bus;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_bus", bus))
                `uvm_fatal("APB_DRIVER", "APB interface was not configured")
        endfunction

        task run_phase(uvm_phase phase);
            apb_item request;
            apb_item response;

            wait (bus.preset_n === 1'b1);
            forever begin
                seq_item_port.get_next_item(request);
                @(negedge bus.pclk);
                bus.psel    = 1'b1;
                bus.penable = 1'b0;
                bus.pwrite  = request.is_write;
                bus.paddr   = request.addr;
                bus.pwdata  = request.data;

                @(negedge bus.pclk);
                bus.penable = 1'b1;
                do @(posedge bus.pclk); while (bus.pready !== 1'b1);

                response = apb_item::type_id::create("response");
                response.set_id_info(request);
                response.is_write = request.is_write;
                response.addr     = request.addr;
                response.data     = bus.prdata;
                response.error    = bus.pslverr;

                @(negedge bus.pclk);
                bus.psel    = 1'b0;
                bus.penable = 1'b0;
                seq_item_port.item_done(response);
            end
        endtask
    endclass

    class apb_monitor extends uvm_monitor;
        `uvm_component_utils(apb_monitor)

        virtual apb_if bus;
        uvm_analysis_port #(apb_item) observed;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            observed = new("observed", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_bus", bus))
                `uvm_fatal("APB_MONITOR", "APB interface was not configured")
        endfunction

        task run_phase(uvm_phase phase);
            apb_item item;

            forever begin
                @(posedge bus.pclk);
                if (bus.preset_n && bus.psel && bus.penable && bus.pready) begin
                    item = apb_item::type_id::create("observed_transfer");
                    item.is_write = bus.pwrite;
                    item.addr     = bus.paddr;
                    item.data     = bus.pwrite ? bus.pwdata : bus.prdata;
                    item.error    = bus.pslverr;
                    observed.write(item);
                end
            end
        endtask
    endclass

    class apb_agent extends uvm_agent;
        `uvm_component_utils(apb_agent)

        uvm_sequencer #(apb_item) sequencer;
        apb_driver driver;
        apb_monitor monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = new("sequencer", this);
            driver = apb_driver::type_id::create("driver", this);
            monitor = apb_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class spi_sample extends uvm_object;
        bit        frame_end;
        spi_byte_t mosi;
        spi_byte_t miso;

        function new(string name = "spi_sample");
            super.new(name);
        endfunction
    endclass

    class spi_monitor extends uvm_monitor;
        `uvm_component_utils(spi_monitor)

        virtual spi_if bus;
        uvm_analysis_port #(spi_sample) observed;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            observed = new("observed", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual spi_if)::get(this, "", "spi_bus", bus))
                `uvm_fatal("SPI_MONITOR", "SPI interface was not configured")
        endfunction

        task run_phase(uvm_phase phase);
            spi_sample sample;
            spi_byte_t mosi_shift;
            spi_byte_t miso_shift;
            int bit_count;

            forever begin
                @(negedge bus.cs_n);
                mosi_shift = '0;
                miso_shift = '0;
                bit_count = 0;

                while (!bus.cs_n) begin
                    @(posedge bus.sck or posedge bus.cs_n);
                    if (bus.cs_n) break;
                    mosi_shift = {mosi_shift[6:0], bus.mosi};
                    miso_shift = {miso_shift[6:0], bus.miso};
                    bit_count++;

                    // The DUT makes a byte available to APB on the eighth falling edge.
                    @(negedge bus.sck or posedge bus.cs_n);
                    if (bus.cs_n) break;
                    if (bit_count == 8) begin
                        sample = new();
                        sample.mosi = mosi_shift;
                        sample.miso = miso_shift;
                        observed.write(sample);
                        bit_count = 0;
                    end
                end

                if (bit_count != 0)
                    `uvm_error("SPI_MONITOR", "Chip select rose before a byte completed")
                sample = new();
                sample.frame_end = 1'b1;
                observed.write(sample);
            end
        endtask
    endclass

    `uvm_analysis_imp_decl(_apb)
    `uvm_analysis_imp_decl(_spi)

    class apb_spi_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(apb_spi_scoreboard)

        uvm_analysis_imp_apb #(apb_item, apb_spi_scoreboard) apb_in;
        uvm_analysis_imp_spi #(spi_sample, apb_spi_scoreboard) spi_in;
        spi_byte_t tx_queue[$];
        spi_byte_t expected_mosi[$];
        spi_byte_t expected_rx_fifo[$];
        spi_byte_t tx_register = '0;
        spi_byte_t last_rx_register = '0;
        spi_byte_t frame_miso = '0;
        bit frame_active;
        bit fifo_mode;
        bit done;
        int frame_length;
        int frames_checked;
        int bytes_checked;

        covergroup frame_coverage with function sample(bit use_fifo, int length);
            option.per_instance = 1;
            mode_cp: coverpoint use_fifo {
                bins register_mode = {0};
                bins fifo_mode = {1};
            }
            fifo_length_cp: coverpoint length iff (use_fifo) {
                bins lengths[] = {[1:4]};
            }
        endgroup

        covergroup error_coverage with function sample(apb_error_t reason);
            option.per_instance = 1;
            reason_cp: coverpoint reason;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            apb_in = new("apb_in", this);
            spi_in = new("spi_in", this);
            frame_coverage = new();
            error_coverage = new();
        endfunction

        function void start_frame(logic [31:0] control);
            if (frame_active) begin
                `uvm_error("SCOREBOARD", "APB accepted START during an active frame")
                return;
            end

            fifo_mode = control[3];
            frame_length = fifo_mode ? int'(control[2:1]) + 1 : 1;
            frame_active = 1;
            done = 0;
            if (fifo_mode) begin
                if (tx_queue.size() < frame_length) begin
                    `uvm_error("SCOREBOARD", "APB accepted START with too few queued bytes")
                    return;
                end
                repeat (frame_length)
                    expected_mosi.push_back(tx_queue.pop_front());
            end else begin
                expected_mosi.push_back(tx_register);
            end
        endfunction

        function void write_apb(apb_item item);
            logic [31:0] expected;

            if (item.error === 1'b1) begin
                case (item.addr)
                    CTRL:   if (item.is_write && item.data[0])
                                error_coverage.sample(frame_active ? BUSY_START : FIFO_START);
                    TXFIFO: if (item.is_write) error_coverage.sample(TX_FULL);
                    RXFIFO: if (!item.is_write) error_coverage.sample(RX_EMPTY);
                    default: ;
                endcase
                return;
            end
            if (item.is_write) begin
                case (item.addr)
                    TXDATA: tx_register = item.data[7:0];
                    TXFIFO: tx_queue.push_back(item.data[7:0]);
                    CTRL:   if (item.data[0]) start_frame(item.data);
                    default: ;
                endcase
            end else begin
                case (item.addr)
                    TXDATA: expected = {24'b0, tx_register};
                    RXDATA: expected = {24'b0, last_rx_register};
                    STATUS: expected = {30'b0, done, frame_active};
                    RXFIFO: begin
                        if (expected_rx_fifo.size() == 0) begin
                            `uvm_error("SCOREBOARD", "APB accepted an empty RXFIFO read")
                            return;
                        end
                        expected = {24'b0, expected_rx_fifo.pop_front()};
                    end
                    default: return;
                endcase
                if (item.data !== expected)
                    `uvm_error("SCOREBOARD", $sformatf("APB read 0x%02h: expected %08h, got %08h",
                                                        item.addr, expected, item.data))
            end
        endfunction

        function void write_spi(spi_sample sample);
            spi_byte_t expected;

            if (!frame_active) begin
                `uvm_error("SCOREBOARD", "SPI activity without an accepted APB START")
                return;
            end

            if (sample.frame_end) begin
                if (expected_mosi.size() != 0)
                    `uvm_error("SCOREBOARD", "Chip select rose with transmit bytes pending")
                else
                    frame_coverage.sample(fifo_mode, frame_length);
                expected_mosi.delete();
                frame_active = 0;
                done = 1;
                last_rx_register = frame_miso;
                frames_checked++;
                return;
            end

            if (expected_mosi.size() == 0) begin
                `uvm_error("SCOREBOARD", "SPI clocked more bytes than requested")
                return;
            end
            expected = expected_mosi.pop_front();
            if (sample.mosi !== expected)
                `uvm_error("SCOREBOARD", $sformatf("MOSI: expected %02h, got %02h",
                                                    expected, sample.mosi))
            frame_miso = sample.miso;
            if (fifo_mode)
                expected_rx_fifo.push_back(sample.miso);
            bytes_checked++;
        endfunction

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (frame_active || expected_mosi.size() != 0 || tx_queue.size() != 0 ||
                expected_rx_fifo.size() != 0)
                `uvm_error("SCOREBOARD", "Transactions remained pending at end of test")
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("FUNCTIONAL_COVERAGE",
                      $sformatf("Frame modes and lengths: %0.1f%%, APB errors: %0.1f%%",
                                frame_coverage.get_inst_coverage(),
                                error_coverage.get_inst_coverage()), UVM_LOW)
        endfunction
    endclass

    class apb_spi_env extends uvm_env;
        `uvm_component_utils(apb_spi_env)

        apb_agent apb;
        spi_monitor spi;
        apb_spi_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            apb = apb_agent::type_id::create("apb", this);
            spi = spi_monitor::type_id::create("spi", this);
            scoreboard = apb_spi_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            apb.monitor.observed.connect(scoreboard.apb_in);
            spi.observed.connect(scoreboard.spi_in);
        endfunction
    endclass

    class apb_spi_sequence extends uvm_sequence #(apb_item);
        `uvm_object_utils(apb_spi_sequence)

        int unsigned random_frames;
        int unsigned random_bytes;

        function new(string name = "apb_spi_sequence");
            super.new(name);
        endfunction

        task access(
            input bit is_write, input logic [7:0] addr, input logic [31:0] data,
            input bit expected_error, output logic [31:0] read_data
        );
            apb_item request;
            apb_item response;

            request = apb_item::type_id::create("request");
            start_item(request);
            request.is_write = is_write;
            request.addr = addr;
            request.data = data;
            finish_item(request);
            get_response(response);
            if (response.error !== expected_error)
                `uvm_error("SEQUENCE", $sformatf("APB %s at 0x%02h: expected PSLVERR=%b, got %b",
                                                 is_write ? "write" : "read", addr,
                                                 expected_error, response.error))
            read_data = response.data;
        endtask

        task wait_for_done();
            logic [31:0] status;

            repeat (100) begin
                access(0, STATUS, '0, 0, status);
                if (status[1] === 1'b1) return;
            end
            `uvm_fatal("SEQUENCE", "Timed out polling STATUS.DONE")
        endtask

        task drain_frame(input bit use_fifo, input int length);
            logic [31:0] ignored;

            wait_for_done();
            access(0, RXDATA, '0, 0, ignored);
            if (use_fifo) begin
                repeat (length) access(0, RXFIFO, '0, 0, ignored);
                access(0, RXFIFO, '0, 1, ignored);
            end
        endtask

        task run_random_frames();
            logic [31:0] ignored;
            bit use_fifo;
            int length;

            repeat (random_frames) begin
                use_fifo = ($urandom_range(1) == 1);
                length = use_fifo ? int'($urandom_range(4, 1)) : 1;
                repeat (length)
                    access(1, use_fifo ? TXFIFO : TXDATA, $urandom_range(255), 0, ignored);
                access(1, CTRL, use_fifo ? (32'h9 | ((length - 1) << 1)) : 32'h1, 0, ignored);
                drain_frame(use_fifo, length);
                random_bytes += length;
            end
        endtask

        task body();
            logic [31:0] ignored;
            spi_byte_t tx_byte;

            access(0, STATUS, '0, 0, ignored);
            access(0, RXDATA, '0, 0, ignored);
            access(0, RXFIFO, '0, 1, ignored);
            access(1, CTRL, 32'h9, 1, ignored);

            access(1, TXDATA, 32'h96, 0, ignored);
            access(0, TXDATA, '0, 0, ignored);
            access(1, CTRL, 32'h1, 0, ignored);
            access(1, CTRL, 32'h1, 1, ignored);
            drain_frame(0, 1);

            for (int length = 1; length <= 4; length++) begin
                for (int index = 0; index < length; index++) begin
                    tx_byte = 8'h35 ^ spi_byte_t'(length * 17 + index * 29);
                    access(1, TXFIFO, {24'b0, tx_byte}, 0, ignored);
                end
                if (length == 4)
                    access(1, TXFIFO, 32'hff, 1, ignored);
                access(1, CTRL, 32'h9 | ((length - 1) << 1), 0, ignored);
                drain_frame(1, length);
            end

            run_random_frames();
        endtask
    endclass

    class apb_spi_test extends uvm_test;
        `uvm_component_utils(apb_spi_test)

        apb_spi_env env;
        int unsigned random_frames;
        int unsigned random_bytes;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = apb_spi_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            apb_spi_sequence stimulus = apb_spi_sequence::type_id::create("stimulus");
            phase.raise_objection(this);
            void'(uvm_config_db#(int unsigned)::get(this, "", "random_frames", random_frames));
            if (random_frames > 128)
                `uvm_fatal("TEST", "random_frames must be between 0 and 128")
            stimulus.random_frames = random_frames;
            stimulus.start(env.apb.sequencer);
            random_bytes = stimulus.random_bytes;
            phase.drop_objection(this);
        endtask

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (env.scoreboard.frames_checked != 5 + random_frames ||
                env.scoreboard.bytes_checked != 11 + random_bytes)
                `uvm_error("TEST", $sformatf("Expected %0d frames and %0d bytes, observed %0d and %0d",
                                             5 + random_frames, 11 + random_bytes,
                                             env.scoreboard.frames_checked,
                                             env.scoreboard.bytes_checked))
        endfunction

        function void report_phase(uvm_phase phase);
            uvm_report_server server = uvm_report_server::get_server();
            super.report_phase(phase);
            `uvm_info("TEST_TOTALS",
                      $sformatf("Checked %0d frames and %0d bytes (%0d randomized frames)",
                                env.scoreboard.frames_checked, env.scoreboard.bytes_checked,
                                random_frames), UVM_LOW)
            if (server.get_severity_count(UVM_ERROR) == 0 &&
                server.get_severity_count(UVM_FATAL) == 0)
                $display("PASS apb_spi_uvm");
        endfunction
    endclass
endpackage
