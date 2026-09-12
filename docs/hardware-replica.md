# Replicating the PPVision BMP Hardware (My_BlackMagic)

How to replicate the PPVision clone board — an STM32F411CEU6 BlackPill-style
Black Magic Probe. Everything below is derived from:

1. The vendor's KiCad project data (`docs/ibom.html` in `blackmagic_copy/`,
   project name **My_BlackMagic**, dated 2024-05-30)
2. The firmware pin definitions (`src/platforms/common/blackpill-f4/blackpill-f4.h`)
3. The stock WeAct F411CE BlackPill reference design (public)

## 1. Board summary

- MCU: **STM32F411CEU6** (UFQFPN-48, 512 KB Flash / 128 KB RAM)
- External SPI Flash: **W25Q128JVPIQ** (16 MB) — onboard flash / XIP
- USB: **USB Type-C** (16-pin, with TPD2E001DRLR ESD protection)
- Power: **ME6211C33M5G-N** LDO (3.3 V)
- Clocks: 25 MHz HSE + 32.768 kHz LSE
- Buttons: **BOOT** (PA0) and **RESET**
- LEDs: 5× 0402 (PB13/14/15 status, PC13 UART, plus D1 = USB power?)
- Header: 2× 5-pin 2.54 mm (J5/J6)

## 2. Full BOM (45 footprints)

Values confirmed from the KiCad BOM:

| Ref | Value | Footprint / Package |
|---|---|---|
| U2 | STM32F411CEU6 | UFQFPN-48 7.0×7.0 P0.50 |
| U4 | W25Q128JVPIQ | WSON-8 5.0×6.0 P1.27 |
| U1 | TPD2E001DRLR | SOT-553-5 (USB ESD) |
| LDO1 | ME6211C33M5G-N | SOT-23-5 (3.3 V LDO) |
| USB1 | USB Type-C 16-pin 2MD | TYPE-C-6PIN-2MD C2765186 |
| X1 | 25 MHz | 3225 SMD crystal |
| X2 | 32.768 kHz | SMD 3215 crystal (RTC) |
| SW1 | BTN_BOOT | 4-pin SMD tactile (4.2×3.2) |
| SW3 | BTN_RESET | 4-pin SMD tactile |
| D1..D8 | LED (5 used) | LED 0402 |
| R1..R15 | 1K / 5.1K / 10K | R 0402 |
| C1..C16 | 0.1uF / 1uF / 10uF 16V / 22pF / 5pF / 4.7uF | C 0402 |
| J5, J6 | Conn 1×5 (2.54 mm) | P2.5 5p header |

Note: refs D1/D2/D3/D6/D7/D8 = LED array; the firmware uses 5 of them
(LED_IDLE_RUN, LED_ERROR, LED_BOOTLOADER on PB13/14/15, LED_UART on PC13,
and one power LED).

## 3. Schematic (pin connections from firmware)

### 3.1 MCU power / clocks

```
3V3 ── C1(0.1uF) ── VDD pins  ── GND
3V3 ── C2(0.1uF) ── VDDA pin
25MHz X1 ── PH0-OSC_IN / PH1-OSC_OUT (with C15/C16 = 22pF load caps)
32.768kHz X2 ── PC14-OSC32_IN / PC15-OSC32_OUT (with 5pF caps)
NRST ── 10K pull-up ── 3V3, and to RESET button SW3
```

### 3.2 USB (Type-C)

```
USB1 D+ ── TPD2E001 (ESD) ── PA12 (USB FS D+)
USB1 D- ── TPD2E001 (ESD) ── PA11 (USB FS D-)
USB1 VBUS ── 5V rail ── LDO1 IN
LDO1 OUT ── 3V3 ── C7(10uF), C6(0.1uF) decoupling
USB1 CC/ID lines: 5.1K pull-downs (R8/R12) for sink detection
```

The firmware uses **internal USB-FS** (PA11/PA12), not the OTG-FS with external
PHY — `OTG_FS_GCCFG` config and `stm32f107_usb_driver` in the platform code.

### 3.3 Debug port (J5 header, 5-pin) — as probe output

```
J5.1 GND
J5.2 TDI  ← PB6  (JTAG TDI / SWDIO alt)
J5.3 TDO  ← PB7  (JTAG TDO / SWO)
J5.4 TCK  ← PB8  (SWCLK)
J5.5 TMS  ← PB9  (SWDIO)
```

> Pinout 0 (default): TDI=PB6, TDO=PB7, TCK=PB8, TMS=PB9.
> Alternative pinout 1: TDI=PB5, TDO=PB6, TCK=PB7, TMS=PB8.
> TRST (PA6) is disabled in the vendor firmware (`#if 0`).

### 3.4 UART / aux header (J6, 5-pin)

```
J6.1 3V3
J6.2 GND
J6.3 TX  ← PA9  (USART1_TX / USBUSART)
J6.4 RX  ← PA10 (USART1_RX)
J6.5 PA8 (GPIO, spare)
```

The GDB interface and target UART both come over the USB CDC (ttyACM0 =
GDB, ttyACM1 = target UART passthrough). PA9/PA10 are the aux UART pins
visible on the header.

### 3.5 Status LEDs

```
PB13 ── LED_IDLE_RUN   (active-low, lit when idle/running)
PB14 ── LED_ERROR      (lit on error)
PB15 ── LED_BOOTLOADER (lit when entering bootloader)
PC13 ── LED_UART       (UART activity, pinout 0)
PC1  ── LED_UART       (UART activity, pinout 1)
```

LEDs are 0402 with series resistors (1K). Polarity logic is stock
(`SET_IDLE_STATE` = `!state`, `SET_ERROR_STATE` = `state`) — the vendor only
moved the pins, not the polarity.

### 3.6 Buttons

```
PA0 ── BOOT button ── GND   (pull-up in firmware; enters DFU when held at power-up)
NRST ── RESET button ── GND
```

### 3.7 SPI flash (W25Q128)

The W25Q128 is the **onboard flash** on SPI1:

```
U4 CS#  ── PA4  (SPI1_NSS / OB_SPI_CS)
U4 CLK  ── PA5  (SPI1_SCK / OB_SPI_SCLK)
U4 D0   ── PA6  (SPI1_MISO / OB_SPI_MISO)
U4 D1   ── PA7  (SPI1_MOSI / OB_SPI_MOSI)
U4 WP# / HOLD# ── 3V3
```

Firmware defines (from `blackpill-f4.h`):
- `OB_SPI` = SPI1 on PA4/5/6/7 (onboard flash — the W25Q128)
- `EXT_SPI` = SPI2 on PB12/13/14/15 (external SPI header, spare)

> Verify against your board: `platform_spi_init(SPI_BUS_INTERNAL)` drives
> `OB_SPI` (PA4-7), `SPI_BUS_EXTERNAL` drives `EXT_SPI` (PB12-15).

## 4. How to actually design the board

Since the vendor did not publish the KiCad sources (only the interactive BOM
and a photo), the practical approach:

1. **Start from the public WeAct BlackPill F411CE design** (open source):
   - [STM32-base board page](https://stm32-base.org/boards/STM32F411CEU6-WeAct-Black-Pill-V2.0)
   - WeAct Studio GitHub: [WeActTC/BlackPill-F411CE](https://github.com/WeActTC/BlackPill-F411CE)
2. **Apply the differences** for this board:
   - LEDs moved to PB13/14/15 + PC13/PC1 (per `blackpill-f4.h`)
   - TRST not routed
   - Two buttons (BOOT on PA0, RESET on NRST)
   - Debug header exposing TDI/TDO/TCK/TMS/3V3/TX/RX
   - Onboard W25Q128 SPI flash
3. **Verify with the firmware**: every pin in section 3 is a compile-time
   constant in `blackpill-f4.h` — the board must match those or the probe
   won't work. Pinouts 0/1/2 are selectable via `ALTERNATIVE_PINOUT`.

## 5. Firmware ↔ hardware mapping files

| Hardware | Firmware location |
|---|---|
| LED pins | `blackpill-f4.h` `LED_PORT/LED_IDLE_RUN/LED_ERROR/LED_BOOTLOADER/LED_PORT_UART/LED_UART` |
| SWD/JTAG pins | `blackpill-f4.h` `TDI/TDO/TCK/TMS/SWCLK/SWDIO/NRST/TRST` |
| Buttons | `blackpill-f4.h` `USER_BUTTON_KEY_PORT/PIN` |
| USB | `blackpill-f4.h` USB macros (PA11/PA12, `USB_DRIVER`) |
| Aux UART | `blackpill-f4.h` `USBUSART*` (USART1 on PA9/PA10) |
| Onboard/EXT SPI flash | `blackpill-f4.h` `OB_SPI` (SPI1, PA4-7) / `EXT_SPI` (SPI2, PB12-15) |

## 6. Getting a real schematic

Options, best first:

1. **WeAct BlackPill F411CE official KiCad sources** (open) — modify to match
   section 3. This is 90% of the work; the board is essentially a BlackPill
   with a debug header and W25Q128.
2. **Re-draw from this document** — the pin table in section 3 is complete
   enough to recreate the schematic in KiCad/EasyEDA.
3. **Ask the vendor** — the project title `My_BlackMagic` and the ibom.html
   came from their KiCad export; they may share sources on request.

## 7. Minimum viable clone

To build a working BMP with the same firmware, you only strictly need:

- STM32F411CEU6 + 25 MHz crystal + decoupling
- USB Type-C (or micro-USB) on PA11/PA12 + ESD
- ME6211 (or any 3.3 V LDO) power
- BOOT (PA0) + RESET buttons
- 4× status LEDs (PB13/14/15 + PC13)
- 5-pin debug header (GND/TDI/TDO/TCK/TMS on PB6-9)
- W25Q128 is optional unless you use `monitor` flash-onboard features

Flash with `blackpill-f411ce-ppvision` firmware from this fork
(see `flashing.md` and `porting.md`).
