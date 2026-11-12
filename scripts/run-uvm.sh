#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build="$root/build/uvm"
: "${UVM_HOME:?Set UVM_HOME to the Accellera UVM 2020.3.2 source directory}"
uvm_src=$(cd -- "$UVM_HOME/src" && pwd)
verilator=${VERILATOR:-verilator}

mkdir -p "$build"
"$verilator" --binary --timing -Wno-fatal -j "${JOBS:-2}" \
    --top-module apb_spi_uvm_tb --Mdir "$build/obj" -o simv \
    +define+UVM_NO_DPI "+incdir+$uvm_src" "$uvm_src/uvm_pkg.sv" \
    "$root/tb/uvm/apb_spi_if.sv" "$root/tb/uvm/apb_spi_pkg.sv" \
    "$root/rtl/spi_fifo.sv" "$root/rtl/spi_mode0_frame.sv" "$root/rtl/apb_spi.sv" \
    "$root/tb/uvm/apb_spi_uvm_tb.sv" 2>&1 | tee "$build/build.log"

"$build/obj/simv" 2>&1 | tee "$build/sim.log"
grep -qx 'PASS apb_spi_uvm' "$build/sim.log"
