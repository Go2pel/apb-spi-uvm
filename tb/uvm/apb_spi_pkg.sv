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
    localparam logic [7:0] FIFO_LEVEL = 8'h18;
    localparam int FIFO_DEPTH = 4;
    typedef logic [7:0] spi_byte_t;
    typedef enum {START_OK, BUSY_START, TX_SHORT, RX_SHORT, TX_FULL, RX_EMPTY} apb_result_t;

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

                while (!bus.cs_n && bus.preset_n) begin
                    @(posedge bus.sck or posedge bus.cs_n or negedge bus.preset_n);
                    if (bus.cs_n || !bus.preset_n) break;
                    mosi_shift = {mosi_shift[6:0], bus.mosi};
                    miso_shift = {miso_shift[6:0], bus.miso};
                    bit_count++;

                    // The DUT makes a byte available to APB on the eighth falling edge.
                    @(negedge bus.sck or posedge bus.cs_n or negedge bus.preset_n);
                    if (bus.cs_n || !bus.preset_n) break;
                    if (bit_count == 8) begin
                        sample = new();
                        sample.mosi = mosi_shift;
                        sample.miso = miso_shift;
                        observed.write(sample);
                        bit_count = 0;
                    end
                end

                if (!bus.preset_n) continue;
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
        virtual apb_if bus;
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
        int frames_aborted;

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

        covergroup error_coverage with function sample(apb_result_t reason);
            option.per_instance = 1;
            reason_cp: coverpoint reason {
                bins busy_start = {BUSY_START};
                bins tx_short = {TX_SHORT};
                bins rx_short = {RX_SHORT};
                bins tx_full = {TX_FULL};
                bins rx_empty = {RX_EMPTY};
            }
        endgroup

        covergroup start_coverage with function sample(bit exact_fit);
            option.per_instance = 1;
            rx_space_cp: coverpoint exact_fit {
                bins extra_space = {0};
                bins exact_fit = {1};
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            apb_in = new("apb_in", this);
            spi_in = new("spi_in", this);
            frame_coverage = new();
            error_coverage = new();
            start_coverage = new();
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_bus", bus))
                `uvm_fatal("SCOREBOARD", "APB interface was not configured")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(negedge bus.preset_n);
                if (frame_active) frames_aborted++;
                tx_queue.delete();
                expected_mosi.delete();
                expected_rx_fifo.delete();
                tx_register = '0;
                last_rx_register = '0;
                frame_miso = '0;
                frame_active = 0;
                fifo_mode = 0;
                done = 0;
                frame_length = 0;
            end
        endtask

        function void start_frame(bit use_fifo, int length);
            fifo_mode = use_fifo;
            frame_length = length;
            frame_active = 1;
            done = 0;
            if (fifo_mode) begin
                for (int index = 0; index < length; index++)
                    expected_mosi.push_back(tx_queue[index]);
                void'(tx_queue.pop_front());
            end else begin
                expected_mosi.push_back(tx_register);
            end
        endfunction

        function void check_start(apb_item item);
            apb_result_t result = START_OK;
            bit use_fifo = item.data[3];
            int length = use_fifo ? int'(item.data[2:1]) + 1 : 1;
            int rx_free = FIFO_DEPTH - expected_rx_fifo.size();

            // The APB monitor calls this at the completion edge, before the SPI updates.
            if (frame_active) result = BUSY_START;
            else if (use_fifo && tx_queue.size() < length) result = TX_SHORT;
            else if (use_fifo && rx_free < length) result = RX_SHORT;

            if (item.error !== (result != START_OK)) begin
                `uvm_error("SCOREBOARD",
                           $sformatf("START len=%0d TX=%0d RX free=%0d: expected %s, got PSLVERR=%b",
                                     length, tx_queue.size(), rx_free, result.name(), item.error))
                return;
            end
            if (result != START_OK) begin
                error_coverage.sample(result);
                return;
            end
            if (use_fifo) start_coverage.sample(rx_free == length);
            start_frame(use_fifo, length);
        endfunction

        function void write_apb(apb_item item);
            logic [31:0] expected;

            if (item.is_write && item.addr == CTRL && item.data[0]) begin
                check_start(item);
                return;
            end

            if (item.error === 1'b1) begin
                case (item.addr)
                    TXFIFO: if (item.is_write && tx_queue.size() == FIFO_DEPTH)
                                error_coverage.sample(TX_FULL);
                    RXFIFO: if (!item.is_write && expected_rx_fifo.size() == 0)
                                error_coverage.sample(RX_EMPTY);
                    default: ;
                endcase
                return;
            end
            if (item.is_write) begin
                case (item.addr)
                    TXDATA: tx_register = item.data[7:0];
                    TXFIFO: tx_queue.push_back(item.data[7:0]);
                    default: ;
                endcase
            end else begin
                case (item.addr)
                    TXDATA: expected = {24'b0, tx_register};
                    RXDATA: expected = {24'b0, last_rx_register};
                    STATUS: expected = {30'b0, done, frame_active};
                    FIFO_LEVEL: expected = (expected_rx_fifo.size() << 4) | tx_queue.size();
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
            if (fifo_mode) begin
                expected_rx_fifo.push_back(sample.miso);
                // The next queued byte is loaded on the same falling edge as RX push.
                if (expected_mosi.size() != 0) void'(tx_queue.pop_front());
            end
            bytes_checked++;
        endfunction

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (frame_active || expected_mosi.size() != 0 || tx_queue.size() != 0 ||
                expected_rx_fifo.size() != 0)
                `uvm_error("SCOREBOARD", "Transactions remained pending at end of test")
            if (frame_coverage.get_inst_coverage() < 100.0 ||
                start_coverage.get_inst_coverage() < 100.0 ||
                error_coverage.get_inst_coverage() < 100.0)
                `uvm_error("SCOREBOARD", "Required functional coverage bins were not all hit")
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("FUNCTIONAL_COVERAGE",
                      $sformatf("Frame modes and lengths: %0.1f%%, FIFO start space: %0.1f%%, APB errors: %0.1f%%",
                                frame_coverage.get_inst_coverage(),
                                start_coverage.get_inst_coverage(),
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
        virtual apb_if apb_bus;
        virtual spi_if spi_bus;

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

        task check_read(logic [7:0] addr, logic [31:0] expected);
            logic [31:0] actual;

            access(0, addr, '0, 0, actual);
            if (actual !== expected)
                `uvm_error("SEQUENCE",
                           $sformatf("Read 0x%02h: expected %08h, got %08h", addr, expected, actual))
        endtask

        task check_rx_space_retry();
            logic [31:0] ignored;

            access(1, TXFIFO, 32'h81, 0, ignored);
            access(1, TXFIFO, 32'h42, 0, ignored);
            access(1, TXFIFO, 32'h63, 0, ignored);
            access(1, CTRL, 32'hd, 0, ignored);
            wait_for_done();

            access(1, TXFIFO, 32'ha5, 0, ignored);
            access(1, TXFIFO, 32'h3c, 0, ignored);
            check_read(FIFO_LEVEL, 32'h32);
            access(1, CTRL, 32'hb, 1, ignored);
            check_read(FIFO_LEVEL, 32'h32);
            check_read(STATUS, 32'h2);
            if (spi_bus.cs_n !== 1'b1)
                `uvm_error("RX_SPACE", "Rejected START did not leave chip select idle")

            access(0, RXFIFO, '0, 0, ignored);
            check_read(FIFO_LEVEL, 32'h22);
            access(1, CTRL, 32'hb, 0, ignored);
            wait_for_done();
            check_read(FIFO_LEVEL, 32'h40);
            access(0, RXDATA, '0, 0, ignored);
            repeat (4) access(0, RXFIFO, '0, 0, ignored);
            check_read(FIFO_LEVEL, '0);
            access(0, RXFIFO, '0, 1, ignored);
        endtask

        task check_reset_recovery();
            logic [31:0] ignored;

            access(1, TXDATA, 32'h9b, 0, ignored);
            access(1, TXFIFO, 32'h11, 0, ignored);
            access(1, TXFIFO, 32'h22, 0, ignored);
            access(1, TXFIFO, 32'h33, 0, ignored);
            access(1, CTRL, 32'hd, 0, ignored);
            repeat (9) @(posedge spi_bus.sck);
            check_read(FIFO_LEVEL, 32'h11);
            if (spi_bus.cs_n !== 1'b0)
                `uvm_fatal("RESET_RECOVERY", "Expected an active SPI frame before reset")

            // No APB request is outstanding when reset aborts the partially shifted byte.
            @(negedge apb_bus.pclk);
            apb_bus.preset_n = 1'b0;
            repeat (2) @(negedge apb_bus.pclk);
            if (spi_bus.cs_n !== 1'b1 || spi_bus.sck !== 1'b0)
                `uvm_error("RESET_RECOVERY", "SPI pins did not return to idle during reset")
            apb_bus.preset_n = 1'b1;

            check_read(STATUS, '0);
            check_read(TXDATA, '0);
            check_read(RXDATA, '0);
            check_read(FIFO_LEVEL, '0);
            access(0, RXFIFO, '0, 1, ignored);

            access(1, TXFIFO, 32'h4e, 0, ignored);
            access(1, CTRL, 32'h9, 0, ignored);
            drain_frame(1, 1);
            check_read(FIFO_LEVEL, '0);
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

            check_rx_space_retry();
            check_reset_recovery();
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
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_bus", stimulus.apb_bus) ||
                !uvm_config_db#(virtual spi_if)::get(this, "", "spi_bus", stimulus.spi_bus))
                `uvm_fatal("TEST", "APB or SPI interface was not configured")
            stimulus.random_frames = random_frames;
            stimulus.start(env.apb.sequencer);
            random_bytes = stimulus.random_bytes;
            phase.drop_objection(this);
        endtask

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (env.scoreboard.frames_checked != 8 + random_frames ||
                env.scoreboard.bytes_checked != 18 + random_bytes ||
                env.scoreboard.frames_aborted != 1)
                `uvm_error("TEST", $sformatf("Expected %0d frames, %0d bytes and one reset abort; observed %0d, %0d and %0d",
                                             8 + random_frames, 18 + random_bytes,
                                             env.scoreboard.frames_checked,
                                             env.scoreboard.bytes_checked,
                                             env.scoreboard.frames_aborted))
        endfunction

        function void report_phase(uvm_phase phase);
            uvm_report_server server = uvm_report_server::get_server();
            super.report_phase(phase);
            `uvm_info("TEST_TOTALS",
                      $sformatf("Checked %0d completed frames and %0d bytes (%0d randomized frames, %0d reset abort)",
                                env.scoreboard.frames_checked, env.scoreboard.bytes_checked,
                                random_frames, env.scoreboard.frames_aborted), UVM_LOW)
            if (server.get_severity_count(UVM_ERROR) == 0 &&
                server.get_severity_count(UVM_FATAL) == 0)
                $display("PASS apb_spi_uvm");
        endfunction
    endclass
endpackage
