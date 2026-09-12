# RP2350 Flashing Logic (BMP firmware side)

How the Black Magic Probe firmware programs an RP2350 (Pico 2) target over SWD.
Companion to [`flash-speed.md`](flash-speed.md) which has the measured numbers.

## 1. Overall flash path

```
GDB  "load" (up to 795 B chunks over USB)
  └─ target_flash_write()            src/target/target_flash.c
       └─ flash->write()  = bmp_spi_flash_write()   src/target/spi.c
            └─ SPI page-program (256 B/page) via rp2350_spi_write()
                 └─ poll BUSY status until flash internal write completes
```

The RP2350 boots from an external QSPI NOR flash (XIP at `0x10000000`).
The probe drives that flash over the RP2350's QSPI pads (`rp2350_spi_*`
functions in `src/target/rp2350.c`), not via a dedicated flash programmer.

## 2. Flash registration (rp2350.c)

`rp2350_add_flash()` does:

1. Read the JEDEC ID over QSPI (`0x9F` command).
2. If a valid flash is present, call
   `bmp_spi_add_flash(target, RP2350_XIP_FLASH_BASE, min(capacity, RP2350_XIP_FLASH_SIZE),
   rp2350_spi_read, rp2350_spi_write, rp2350_spi_run_command)`.
3. The flash region is published at the XIP base `0x10000000`.

## 3. SPI flash driver (spi.c)

`bmp_spi_add_flash()` builds a `target_flash_s` and discovers parameters via **SFDP**
(Serial Flash Discoverable Parameters, JEDEC JESD216):

- `page_size`  = 256 B  (page-program granularity)
- `sector_size` = 4096 B (erase granularity)
- `sector_erase_opcode` = `0x20` (4K sector erase)

If SFDP fails, it falls back to the same defaults (256/4096, `0x20`).

Key settings:

```c
flash->blocksize  = spi_parameters.sector_size;   // 4096
flash->write      = bmp_spi_flash_write;
flash->erase      = bmp_spi_flash_erase;
flash->mass_erase = bmp_spi_mass_erase;
flash->erased     = 0xffU;
spi_flash->page_size = 256U;
```

`target_add_flash()` (src/target/target.c) then fills in the write-buffer size:
if `writesize == 0` it defaults to `blocksize` (4096), and the GDB-side transfer
chunk is bounded by `FLASH_WRITE_BUFFER_CEILING` — this is the ~795 B seen in
GDB output.

## 4. Write flow (bmp_spi_flash_write)

```c
for (offset = 0; offset < length; offset += page_size) {   // 256 B per page
    spi_flash->write(... PAGE_PROGRAM ...)                  // 0x02, 256 B
    while (bmp_spi_read_status(...) & BUSY) {}              // poll status reg
}
```

Every 256 B page costs one page-program command plus a BUSY poll.
Page-program on typical QSPI NOR flash takes ~3-5 ms — this is **physical
latency** and does not depend on the SWD clock.

## 5. Erase flow

- `bmp_spi_flash_erase()` — sector erase (`0x20`, 4 KB) with BUSY poll.
- `bmp_spi_mass_erase()` — full chip erase (`0xC7`) with progress printing.
- `target_flash_erase()` (target_flash.c) decides between mass erase and
  per-sector erase: if the erase range covers the whole flash region and
  `mass_erase` exists, it uses mass erase; otherwise it erases aligned
  `blocksize` (4 KB) sectors.

GDB `load` itself only *writes*; erase is triggered separately
(`monitor erase` / BMDA `-E`, or the probe erases sectors as needed).
In practice the dominant cost during `load` is the page-program BUSY polling.

## 6. Why 8 KB/s is the ceiling (short version)

- 256 B page-program + BUSY poll ≈ 30 ms per page (measured path).
- `256 B / 30 ms ≈ 8.5 KB/s` — matches observed `8 KB/sec`.
- SWD frequency above ~10 MHz no longer matters: the flash itself is the
  bottleneck, not the debug link.

## 7. Relevant source files

| File | Role |
|---|---|
| `src/target/rp2350.c` | RP2350 target: QSPI flash attach, `rp2350_spi_*` low-level access |
| `src/target/spi.c` | Generic SPI flash driver: SFDP discovery, page write, sector/mass erase |
| `src/target/target_flash.c` | Flash abstraction: `target_flash_write/erase`, buffer sizing |
| `src/target/target.c` | `target_add_flash()` write-buffer sizing |

## 8. Related GDB caveat

Flashing through GDB triggers the known GDB bug
[gdb/28874](https://sourceware.org/bugzilla/show_bug.cgi?id=28874)
(`inferior_thread` assertion) when GEF/.gdbinit event hooks are loaded.
`tools/bmd-flash.sh` runs GDB with `-nx` to disable them; flashing then
succeeds on the first attempt.
