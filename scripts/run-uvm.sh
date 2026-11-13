#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build="$root/build/uvm"
: "${UVM_HOME:?Set UVM_HOME to the Accellera UVM 2020.3.2 source directory}"
uvm_src=$(cd -- "$UVM_HOME/src" && pwd)
verilator=${VERILATOR:-verilator}
random_frames=${RANDOM_FRAMES:-24}
trace=${TRACE:-0}

if [[ ! $random_frames =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((random_frames > 128)); then
    echo 'RANDOM_FRAMES must be between 0 and 128' >&2
    exit 2
fi
if [[ $trace != 0 && $trace != 1 ]]; then
    echo 'TRACE must be 0 or 1' >&2
    exit 2
fi
if (($# == 0)); then
    set -- 1 17 42
fi
for seed in "$@"; do
    if [[ ! $seed =~ ^[1-9][0-9]{0,9}$ ]] || ((seed > 2147483647)); then
        printf 'Invalid simulation seed: %s\n' "$seed" >&2
        exit 2
    fi
done

mkdir -p "$build"
trace_options=()
if [[ $trace == 1 ]]; then
    trace_options=(--trace-vcd --trace-depth 3)
fi
"$verilator" --binary --timing --assert --coverage-user -Wno-fatal -j "${JOBS:-2}" \
    "${trace_options[@]}" \
    --top-module apb_spi_uvm_tb --Mdir "$build/obj" -o simv \
    +define+UVM_NO_DPI "+incdir+$uvm_src" "$uvm_src/uvm_pkg.sv" \
    "$root/tb/uvm/apb_spi_if.sv" "$root/tb/uvm/apb_spi_pkg.sv" \
    "$root/rtl/spi_fifo.sv" "$root/rtl/spi_mode0_frame.sv" "$root/rtl/apb_spi.sv" \
    "$root/tb/apb_spi_assertions.sv" \
    "$root/tb/uvm/apb_spi_uvm_tb.sv" 2>&1 | tee "$build/build.log"

run_sim() {
    local name=$1
    shift
    if [[ $trace == 1 ]]; then
        set -- "$@" "+vcd=$build/$name.vcd"
    fi
    "$build/obj/simv" "+verilator+coverage+file+$build/$name.dat" "$@" \
        2>&1 | tee "$build/$name.log"
    grep -qx 'PASS apb_spi_uvm' "$build/$name.log"
}

run_sim sim
if ((random_frames > 0)); then
    for seed in "$@"; do
        printf 'Running seed %s with %s randomized frames\n' "$seed" "$random_frames"
        run_sim "seed-$seed" "+verilator+seed+$seed" "+random_frames=$random_frames"
    done
fi
