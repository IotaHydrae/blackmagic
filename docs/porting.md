# Porting the PPVision Custom Board to Upstream (blackpill-f411ce-ppvision)

How the PPVision clone board support was implemented as a new platform on top
of the current upstream tree, and how to maintain it.

## 1. Background

Two source trees exist in the workspace:

| Tree | Role |
|---|---|
| `blackmagic/` | Official upstream (reference only, do not modify) |
| `blackmagic_copy/` | Vendor (PPVision) fork of upstream, ~2 years old |
| `blackmagic_fork/` | **This fork**: upstream + PPVision hardware adaptation |

The vendor board is an STM32F411CEU6 BlackPill clone. Compared to the stock
WeAct F411CE BlackPill it differs in:

- Status LEDs wired to **PB13/PB14/PB15** (instead of PC13/14/15)
- UART activity LED on **PC13 / PC1** (instead of PA4/PA1)
- **TRST not routed out**
- nRST handled by dynamic pin reconfiguration

The upstream `common/blackpill-f4` code is shared by all four blackpill
variants (f401cc/f401cd/f401ce/f411ce) and has since gained many features
(SWO, 3 alternative pinouts, SHIELD, on-carrier-board, …). Therefore the port
was done as a **new platform alias** that reuses the common code and selects
the different hardware via a compile-time macro, instead of overwriting the
shared files.

## 2. Design: new platform + `PPVISION_COPY` macro

- New probe id: **`blackpill-f411ce-ppvision`**
- Reuses `src/platforms/common/blackpill-f4/` sources via the probe alias map
- Compile definition **`PPVISION_COPY`** is added only for this probe;
  `#ifdef PPVISION_COPY` branches in `blackpill-f4.h/.c` carry the board
  differences. All other variants are untouched.

### Probe identity / clock

`src/platforms/common/blackpill-f4/meson.build`:

```meson
probe_blackpill_variant = probe.split('-')[1].to_upper()   # F411CE
probe_blackpill_ppvision = probe == 'blackpill-f411ce-ppvision'

# PLATFORM_IDENT: "(BlackPill-F411CE-PPVision) "
# PLATFORM_CLOCK_FREQ: RCC_CLOCK_3V3_96MHZ (same as f411ce)
```

The variant is now taken from the part after the first dash (`[1]`), which is
robust for names with extra suffixes (`-ppvision`).

## 3. File changes

| File | Change |
|---|---|
| `meson_options.txt` | Add `'blackpill-f411ce-ppvision'` to the `probe` choices |
| `src/platforms/meson.build` | Map `'blackpill-f411ce-ppvision'` → `'common/blackpill-f4'` |
| `src/platforms/common/blackpill-f4/meson.build` | Variant extraction, `PPVISION_COPY` define, PPVision ident/clock |
| `src/platforms/common/blackpill-f4/blackpill-f4.h` | `#ifdef PPVISION_COPY` LED pin definitions |
| `src/platforms/common/blackpill-f4/blackpill-f4.c` | `#ifndef PPVISION_COPY` TRST/nRST init; dynamic nRST in `platform_nrst_set_val` |
| `src/platforms/common/blackpill-f4/blackpill-f411ce-ppvision.ld` | Linker script copy (512K rom / 128K ram) |
| `cross-file/blackpill-f411ce-ppvision.ini` | Meson cross file: `probe = 'blackpill-f411ce-ppvision'` |
| `src/platforms/blackpill-f411ce-ppvision/` | Static `platform.h` + `README.md` |

### blackpill-f4.h — LED pins

```c
#ifdef PPVISION_COPY
#define LED_PORT       GPIOB      /* PB13/PB14/PB15 status LEDs */
#define LED_IDLE_RUN   GPIO13
#define LED_ERROR      GPIO14
#define LED_BOOTLOADER GPIO15
#define LED_PORT_UART GPIOC       /* UART LED: PC13, or PC1 on pinout 1 */
#define LED_UART      PINOUT_SWITCH(GPIO13, GPIO1)
#else
  /* stock: LED_PORT=GPIOC, LED_PORT_UART=GPIOA, LED_UART=PINOUT_SWITCH(GPIO4,GPIO1,GPIO4) */
#endif
```

The LED polarity macros (`SET_IDLE_STATE` = `!state`, `SET_ERROR_STATE` =
`state`) are **not changed** — the vendor kept the stock polarity and only
moved the pins, so the port keeps exactly the vendor's behaviour.

### blackpill-f4.c — TRST / nRST

```c
#ifndef PPVISION_COPY
    /* configure TRST and nRST pins statically (stock behaviour) */
#endif

void platform_nrst_set_val(bool assert)
{
#ifdef PPVISION_COPY
    /* dynamic pin configuration (vendor behaviour) */
    if (assert) { gpio_mode_setup(NRST_PORT, OUTPUT, ...); gpio_clear(...); }
    else        { gpio_mode_setup(NRST_PORT, INPUT, ...);  gpio_set(...); }
#else
    gpio_set_val(NRST_PORT, NRST_PIN, !assert);
#endif
}
```

## 4. Boot button / DFU

The vendor fork inverted the BOOT-button DFU logic (`#ifndef BMP_BOOTLOADER`
→ `#ifdef BMP_BOOTLOADER`), which meant pressing PA0 no longer entered DFU.
This port **restores the stock logic** (`#ifndef BMD_BOOTLOADER`), so holding
BOOT (PA0) at power-up enters the ST system bootloader / BMP DFU again.

## 5. Building

```bash
cd /home/developer/sources/bmd/blackmagic_fork
bash build.sh            # meson setup + ninja; artifacts copied to release/
bash build.sh clean      # full rebuild from scratch
```

Cross file: `cross-file/blackpill-f411ce-ppvision.ini` (bmd_bootloader=true →
dual-image: bootloader at 0x08000000, firmware at 0x08004000).

## 6. Maintaining the port

- **Keep changes minimal and macro-gated.** New board differences should be
  added as `#ifdef PPVISION_COPY` branches in the shared files, or as new
  files — never by replacing the shared `blackpill-f4` sources.
- **Merging upstream:** run `bmd-sync.sh` (fetch `upstream`, merge into
  `main`). Conflicts are likely in `blackpill-f4.h/.c` and the meson files.
  Resolution rule: keep upstream features, keep the `PPVISION_COPY` branches,
  merge overlapping lines by hand.
- **After every merge:** rebuild (`bash build.sh`) and re-verify flashing.

## 7. Tooling

BMP-specific scripts live in `tools/` with a `bmd-` prefix (they are not
generic):

- `tools/bmd-flash.sh` — flash an ELF to a target (`SWD_FREQ` tunable)
- `tools/bmd-gdb.sh` — GDB TUI launcher (regs + src/asm split layout)
- `tools/bmd-udev.sh` — install/check udev rules
- `bmd-sync.sh` — upstream sync (`--push` to push to origin)
- `bmd-test.sh` — probe firmware smoke test
- `build.sh` — firmware build (generic name, not BMP-specific)
