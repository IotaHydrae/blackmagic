# Documentation

Index of the Black Magic Probe fork documentation.

## Table of contents

| Document | Contents |
|---|---|
| [`flashing.md`](flashing.md) | How to flash / restore the BMP probe firmware itself (STM32F411CEU6 PPVision board): DFU, SWD (CMSIS-DAP/openocd), UART ISP, and the release image layout |
| [`flash-speed.md`](flash-speed.md) | Flash programming speed measurements and bottleneck analysis (SWD frequency vs QSPI page-program latency) |
| [`rp2350-flashing.md`](rp2350-flashing.md) | How the BMP firmware flashes an RP2350 target: GDB load path, target_flash machinery, SPI flash driver internals, erase/write flow |
| [`porting.md`](porting.md) | How the PPVision custom board port (`blackpill-f411ce-ppvision`) was implemented on top of upstream, and how to maintain it |
| [`hardware-replica.md`](hardware-replica.md) | How to replicate the hardware: full BOM (from the vendor KiCad ibom), schematic pin tables, board differences vs stock BlackPill |
| `99-blackmagic.rules` | Udev rules for non-root access to the probe (installed via `tools/bmd-udev.sh`) |

## Tool scripts

All BMP-specific tooling lives in `tools/` (see `porting.md` for the full list):

- `tools/bmd-flash.sh` — flash an ELF to a target via GDB (`SWD_FREQ` to tune speed)
- `tools/bmd-gdb.sh` — one-shot GDB launcher with recommended TUI layout
- `tools/bmd-udev.sh` — install / uninstall / check udev rules
- `build.sh` — build the firmware (generic, not BMP-specific)
- `bmd-sync.sh` — sync the fork with upstream
- `bmd-test.sh` — verify the probe firmware over GDB

## Platform summary

- Board: PPVision clone of WeAct BlackPill, MCU **STM32F411CEU6** (512 KB Flash / 128 KB RAM)
- Fork platform: `blackpill-f411ce-ppvision` (probe identity `BlackPill-F411CE-PPVision`)
- Upstream base: `cc4e0849` (2026-09-09), meson build system
