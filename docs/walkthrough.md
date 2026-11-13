# APB–SPI verification walkthrough

## 1. Follow a transfer through the RTL

The APB bus gives software access to the controller. A write to address `0x10` puts its low byte in the TX FIFO. During setup, `PSEL=1` and `PENABLE=0`. During access, both are high. This peripheral ties `PREADY` high, so the write takes effect on the rising `PCLK` edge in access.

Software writes `0x0B` to `CTRL` at address `0x04` to start a two-byte frame. Bit 0 requests START, bit 3 selects FIFO mode, and bits `[2:1]` encode length minus one. The controller checks that it is idle, two TX bytes are queued and two RX slots are free. If the request passes, the first TX byte loads on the APB completion edge and chip select falls. [APB decoder and start logic](../rtl/apb_spi.sv)

The SPI engine divides the internal clock by eight. It presents MOSI MSB first, samples MISO on each rising SCK edge and shifts MOSI on each falling edge. The eighth falling edge commits one RX byte to the FIFO and, if another byte is due, loads the next TX byte under the same chip select. Each FIFO uses separate two-bit read and write pointers and a three-bit occupancy counter. [SPI engine](../rtl/spi_mode0_frame.sv) · [FIFO](../rtl/spi_fifo.sv)

## 2. Follow the same transfer through UVM

The sequence tells the APB driver which transfers to perform. The APB monitor samples the pins at the completion edge and sends the observed address, data and response to the scoreboard. The SPI monitor reconstructs the two serial streams using chip select and SCK. Its MOSI observations are compared against bytes predicted from accepted APB writes. Its MISO observations become the expected data for later APB reads.

The scoreboard predicts the START outcome from its own busy state and FIFO model. It samples the functional coverage only when that prediction matches the observed response. For a refused start, the sequence also reads the FIFO levels and status. A later successful transfer checks that the queued bytes survived and still emerge in order. [UVM package](../tb/uvm/apb_spi_pkg.sv)

## 3. Reproduce the RX-space boundary

Run the directed waveform command from the [README](../README.md#run-the-uvm-regression). Find the `0x0B` write to `CTRL` with `PSLVERR=1`. The register-mode busy START in the same trace writes `0x01`. The earlier TX-short START writes `0x09`.

| Checkpoint | Expected result |
| --- | --- |
| Previous frame sent `81 42 63` | The fixed directed SPI model returned `D2 6C B7`. All three bytes remain in RX. |
| Queue `A5 3C` for the next frame | `FIFO_LEVEL=0x32` means TX has two bytes and RX holds three. |
| Attempt a two-byte START | `PSLVERR=1`, `FIFO_LEVEL=0x32`, `STATUS=0x02`. Chip select stays high. |
| Read one RX byte and retry | The read returns `D2`. `FIFO_LEVEL=0x22` before the retry. START now succeeds. |
| Observe the retried frame | One low chip-select interval contains MOSI `A5 3C`. RX fills to four bytes. |
| Drain RX | The APB reads return `6C B7 D2 6C`. The first two bytes are from the earlier frame. The last two are from the retry. `FIFO_LEVEL` returns to zero. |

Add `pclk`, `psel`, `penable`, `pready`, `pwrite`, `paddr`, `pwdata`, `prdata`, `pslverr`, `spi_cs_n`, `spi_sck`, `spi_mosi` and `spi_miso` to the waveform view. Start at the rising `PCLK` edge that completes the rejected write. Follow the next RX read and then the successful START. During the accepted SPI frame, read MOSI on the rising SCK edges, eight bits per byte.

In the directed Verilator 5.054 run, the rejected write completed at **10,795 ns**, the retry completed at **10,945 ns**, and chip select rose at **12,265 ns**. The trace showed `start=0` and `tx_pop=0` at the rejected completion edge, with TX level 2, RX level 3 and DONE high.

## 4. Explain the evidence

In an interview, lead with the contract. START requires space for the entire RX frame. Explain how three unread bytes in a depth-four FIFO create a one-slot shortage for a two-byte transfer. The error response confirms rejection, the status and occupancy reads check immediate side effects, and the successful retry checks retained data and ordering.

The reset case covers a different boundary. The sequence aborts during the second byte, after the first byte already reached RX. The SPI monitor discards the partial byte, the scoreboard clears pending state, and the next frame checks that the controller can start cleanly. A coverage bin records that a scenario occurred. The scoreboard and assertions decide whether the behavior was correct.
