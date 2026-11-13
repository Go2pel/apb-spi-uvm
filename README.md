# APB3 SPI Controller and UVM Verification

SystemVerilog learning project for a memory-mapped SPI host and its verification. The controller supports SPI Mode 0 and FIFO-backed frames of one to four bytes. The repository includes a directed SystemVerilog smoke test and a UVM end-to-end regression.

## Register interface

The APB3 peripheral completes each access with `PREADY=1`. A transaction takes effect on a rising `PCLK` edge with `PSEL`, `PENABLE` and `PREADY` high. The SPI engine uses the same internal clock, emits one chip select and runs `SCK` at `PCLK/8`. It samples MISO on rising SCK edges and shifts MOSI on falling edges, MSB first.

| Offset | Register | Access | Behavior |
| --- | --- | --- | --- |
| `0x00` | `TXDATA` | RW | Low byte to transmit in single-byte register mode. Start snapshots the byte. |
| `0x04` | `CTRL` | RW | Write bit 0 to start. Bit 3 selects FIFO mode. In FIFO mode, bits `[2:1]` encode length minus one. Reads return zero. |
| `0x08` | `STATUS` | RO | Bit 0 is `BUSY`. Bit 1 is `DONE`, cleared by a successful start or reset. |
| `0x0c` | `RXDATA` | RO | Low byte holds the final received byte of the last completed frame. Reading it has no side effect. |
| `0x10` | `TXFIFO` | WO | Writing the low byte enqueues it. A write to a full FIFO returns `PSLVERR`. |
| `0x14` | `RXFIFO` | RO | A read returns and consumes the oldest received byte. Reading an empty FIFO returns `PSLVERR`. |
| `0x18` | `FIFO_LEVEL` | RO | TX count in `[2:0]` and RX count in `[6:4]`. Both count from zero to four. |

Write `CTRL=0x01` for single-byte register mode. For a two-byte FIFO frame, write two bytes to `TXFIFO`, write `CTRL=0x0b`, wait for `DONE`, then read `RXFIFO` twice. A FIFO frame starts only if all its TX bytes are queued and there are enough free RX slots for the complete frame. Chip select remains low across byte boundaries. Each RX byte enters its FIFO after its eighth falling SCK edge.

An attempt to start while busy or without enough FIFO capacity returns `PSLVERR` and preserves the current transfer and `DONE`. A read of a write-only register, a write to a read-only register or an unmapped access also returns `PSLVERR`. FIFO full and empty decisions use occupancy before the APB completion edge. At intermediate occupancy, a same-edge push and pop advance both pointers and keep the count unchanged. Reset aborts the current frame, clears the registers and empties both FIFOs.

## Run the smoke test

On Windows, use Vivado Simulator from PowerShell. Supply the Vivado `bin` directory if `xvlog.bat` is absent from `PATH`.

```powershell
.\scripts\run-xsim.ps1 -VivadoBin 'C:\Xilinx\2025.1\Vivado\bin'
```

The script prints the build and log directory. A successful run ends with `PASS apb_spi_smoke`. The SPI device model checks pin data, the SCK period and chip select independently. The test covers single-byte register accesses, two- and four-byte FIFO frames, rejection of insufficient TX or RX capacity, full and empty FIFO errors, pointer wraparound, simultaneous push and pop, and reset during a frame.

## Run the UVM regression

On Linux or WSL, use Verilator 5.054 or newer and the [Accellera UVM 2020.3.2 reference implementation](https://www.accellera.org/downloads/standards/uvm). Set `UVM_HOME` to the extracted directory that contains `src/uvm_pkg.sv`. The runner uses `verilator` from `PATH` unless `VERILATOR` is set.

```sh
UVM_HOME=/path/to/1800.2-2020.3.2 bash scripts/run-uvm.sh
```

The APB agent drives transactions and independently observes completed transfers. A separate SPI monitor reconstructs MOSI and MISO bytes from the pins. The scoreboard predicts MOSI from accepted APB writes and checks APB receive reads against observed MISO. It also checks frame boundaries, `BUSY` and `DONE`. The sequence checks expected `PSLVERR` responses.

The directed run checks five frames and eleven bytes across register mode and all four FIFO lengths. The runner then repeats the directed tests and adds 24 randomized frames per seed for seeds 1, 17 and 42. Random stimulus varies register or FIFO mode, FIFO length, MOSI payload and MISO response. To reproduce one seed or run only the directed test, use:

```sh
UVM_HOME=/path/to/1800.2-2020.3.2 bash scripts/run-uvm.sh 17
RANDOM_FRAMES=0 UVM_HOME=/path/to/1800.2-2020.3.2 bash scripts/run-uvm.sh
```

A successful run prints `PASS apb_spi_uvm`. Logs and Verilator coverage data go to `build/uvm/`, with one pair of files per run. Functional coverage samples completed frame modes and FIFO lengths, plus APB error responses for a busy start, an inadmissible FIFO start, a full TX FIFO write and an empty RX FIFO read. The reported percentages apply to these bins. The runner compiles with `UVM_NO_DPI`.

Both testbenches instantiate protocol assertions for the APB setup-to-access transition, zero-wait completion, error timing and SPI Mode 0 pin behavior. The UVM run resets before stimulus. The standalone smoke test covers reset during a frame and simultaneous FIFO push and pop.

For the first exercise, draw the APB write of `TXDATA` and the SPI rising edge that samples bit 7 of `0xa6`. Then trace why the second `START` write produces `PSLVERR` while the first byte still reaches the SPI device.

References: [Arm AMBA specifications](https://www.arm.com/architecture/system-architectures/amba/amba-specifications), [Nandland SPI Master](https://github.com/nandland/spi-master), [OpenTitan SPI host verification](https://opentitan.org/book/hw/ip/spi_host/dv/index.html).

The starter SPI byte engine is original project code. See [LICENSE](LICENSE).
