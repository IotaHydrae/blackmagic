# BlackPill F411CE (PPVision Custom Revision)

This platform supports the PPVision custom revision of the Black Pill F411CE
board (STM32F411CEU6), as sold by third-party vendors.

Compared to the stock WeAct F411CE BlackPill, this revision differs in:

- The status LEDs are wired to **PB13/PB14/PB15** (IDLE/RUN, ERROR, BOOTLOADER)
  instead of PC13/PC14/PC15.
- The UART activity LED is wired to **PC13** (alternative pinout 1: PC1)
  instead of PA4/PA1.
- The TRST line is not routed out and is left unconfigured.

The firmware is built from the same `common/blackpill-f4` sources as the stock
platform, with the `PPVISION_COPY` compile definition selecting the matching
hardware definitions in `blackpill-f4.h` / `blackpill-f4.c`.

The two buttons on the board are the standard **BOOT (PA0)** and **RESET**
buttons. Holding BOOT while powering up (or pressing RESET while BOOT is held)
enters the on-chip ST bootloader (USB DFU mode) in non-BMP-bootloader builds.

Build with:

```sh
meson setup build --cross-file cross-file/blackpill-f411ce-ppvision.ini
ninja -C build
```

References to the stock hardware:
- [Zephyr Project F411CE](https://docs.zephyrproject.org/latest/boards/arm/blackpill_f411ce/doc/index.html)
- [STM32-base F411CE](https://stm32-base.org/boards/STM32F411CEU6-WeAct-Black-Pill-V2.0)
