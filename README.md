# APB3 SPI Controller and UVM Verification

SystemVerilog learning project for a memory-mapped SPI host and its verification. The first milestone is a one-byte SPI Mode 0 transfer with a self-checking testbench. The UVM environment is a later milestone.

## First milestone

The APB3 peripheral completes each access with `PREADY=1`. A transaction takes effect on a rising `PCLK` edge with `PSEL`, `PENABLE` and `PREADY` high. The SPI engine uses the same internal clock, emits one chip select and runs `SCK` at `PCLK/8`. It samples MISO on rising SCK edges and shifts MOSI on falling edges, MSB first.

| Offset | Register | Access | Behavior |
| --- | --- | --- | --- |
| `0x00` | `TXDATA` | RW | Low byte to transmit. A successful start snapshots the byte. |
| `0x04` | `CTRL` | RW | Write bit 0 to start. Reads return zero. Starting while busy returns `PSLVERR`. |
| `0x08` | `STATUS` | RO | Bit 0 is `BUSY`. Bit 1 is `DONE`, cleared by a successful start or reset. |
| `0x0c` | `RXDATA` | RO | Low byte holds the most recent completed transfer. Reading it has no side effect. |

All registers reset to zero. Upper bits read as zero. Writes to read-only registers and accesses to unmapped offsets return `PSLVERR` in the access phase.

## Run the smoke test

On Windows, use Vivado Simulator from PowerShell. Supply the Vivado `bin` directory if `xvlog.bat` is absent from `PATH`.

```powershell
.\scripts\run-xsim.ps1 -VivadoBin 'C:\Xilinx\2025.1\Vivado\bin'
```

The script prints the build and log directory. A successful run ends with `PASS apb_spi_smoke`. The SPI device model checks MOSI pin data independently and drives a separate MISO response. The test reads back RXDATA over APB and checks two transfers, reset values, an invalid address, a write to a read-only register and a start request while busy.

## Next milestones

1. Add TX/RX FIFOs and a bounded multi-byte transfer. Specify the full, empty and reset behavior before writing RTL.
2. Build a UVM APB agent and an independent SPI monitor. Connect both monitors to an end-to-end scoreboard.
3. Add protocol assertions, seeded regressions and functional coverage.

For the first exercise, draw the APB write of `TXDATA` and the SPI rising edge that samples bit 7 of `0xa6`. Then trace why the second `START` write produces `PSLVERR` while the first byte still reaches the SPI device.

References: [Arm AMBA specifications](https://www.arm.com/architecture/system-architectures/amba/amba-specifications), [Nandland SPI Master](https://github.com/nandland/spi-master), [OpenTitan SPI host verification](https://opentitan.org/book/hw/ip/spi_host/dv/index.html).

The starter SPI byte engine is original project code. See [LICENSE](LICENSE).
