# 复刻板（STM32F411CEU6）烧录与恢复方法

> 板子：PPVision 复刻 BlackPill，主控 STM32F411CEU6（512KB Flash / 128KB RAM）
> 本机烧录工具：**CMSIS-DAP 探针 + openocd**（openocd 0.12.0 已装，CMSIS-DAP 驱动内置）

## 固件文件（目录：`../release/`）

| 文件 | 说明 |
|---|---|
| `blackmagic.bin` | 复刻版卖家固件（138276 字节，加载地址 0x08000000），SHA256: `03162a22706e3cb4a05ebf539a686e559b715f2d7b44351496503edeae063e68` |
| `blackmagic.hex` | 同上固件的 Intel HEX 格式 |
| `blackmagic-copy.elf` | 带调试符号的 ELF（GDB 用） |
| `blackmagic_blackpill_f411ce_ppvision_bootloader.bin` | 移植版 BMP bootloader（9052 字节，0x08000000），SHA256: `76348c509d4a8b99ebae4f7155599be9d38912cdd82ccb80484e3671d775aee3` |
| `blackmagic_blackpill_f411ce_ppvision_firmware.bin` | 移植版主固件（162476 字节，0x08004000），SHA256: `9493968d533881e9f65d199dbaf6670b6cd47ff44df208a53e42988d58807c72` |

## 烧录方法

### 方法 1：CMSIS-DAP + openocd（SWD，推荐）

**接线**（CMSIS-DAP 探针 → 板子）：
```
CMSIS-DAP      →  板子
SWDIO          →  PA13 (SWDIO)
SWCLK          →  PA14 (SWCLK)
GND            →  GND
3.3V (VCC)     →  3.3V（若 DAP 提供目标供电；否则用板子自己的 USB 供电，只连 GND/SWDIO/SWCLK）
```

**烧录任意镜像**（通用命令，注意地址）：
```bash
# 烧 binary 到指定地址（verify 校验 + reset 复位 + exit 退出）
openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
  -c "program 固件文件.bin 地址 verify reset exit"

# 烧 Intel HEX（地址信息在 HEX 内，无需指定）
openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
  -c "program 固件文件.hex verify reset exit"
```

**恢复卖家固件**（回到出厂状态，整体覆盖）：
```bash
openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
  -c "program /home/developer/sources/bmd/blackmagic_fork/release/blackmagic.bin 0x08000000 verify reset exit"
```

**首次升级移植版固件**（双镜像：先 bootloader 后主固件）：
```bash
openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
  -c "program /home/developer/sources/bmd/blackmagic_fork/release/blackmagic_blackpill_f411ce_ppvision_bootloader.bin 0x08000000 verify reset exit"

openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
  -c "program /home/developer/sources/bmd/blackmagic_fork/release/blackmagic_blackpill_f411ce_ppvision_firmware.bin 0x08004000 verify reset exit"
```

> 若探针连接异常，可先加 `adapter serial <SN>` 或 `-c "adapter speed 1000"`（降低 SWD 频率）试连：
> ```bash
> openocd -f interface/cmsis-dap.cfg -f target/stm32f4x.cfg \
>   -c "adapter speed 1000" -c "init" -c "halt" -c "reset halt" -c "exit"
> ```

### 方法 2：STM32 系统 Bootloader（DFU，无需探针）

F411 内置 ROM bootloader 支持 USB DFU。进入方法：

1. **BOOT0 拉高**：短接板子 BOOT0 跳线到 1（VCC 侧），然后**按住复位键再松开**（或重新上电）。
2. 用 USB 线连接板子到电脑，应出现 STM32 BOOTLOADER DFU 设备（`0483:df11`）。
3. 烧录（本机 dfu-util 未装，可用 `sudo apt install dfu-util` 安装）：
   ```bash
   dfu-util -a 0 -s 0x08000000:leave -D blackmagic.bin
   ```
4. 烧完后把 BOOT0 跳线**恢复回 0（GND 侧）**并复位。

### 方法 3：串口 ISP（UART bootloader，需 USB-TTL）

1. BOOT0 拉高 + 复位，进入 ROM bootloader。
2. 连接 USART1（PA9=TX, PA10=RX）或 USART2，接 USB-TTL 到电脑。
3. 用 stm32flash 烧录（需自行安装）：
   ```bash
   stm32flash -w blackmagic.bin -v -g 0x0 /dev/ttyUSB0
   ```

## 移植版固件的后续升级（BMP 自身 DFU）

移植版固件采用 **BMP bootloader + 主固件**双镜像结构：
- bootloader：0x08000000 起（常驻，负责 DFU）
- 主固件：0x08004000 起

bootloader 烧好后，后续升级主固件**不需要 SWD**：
```bash
# 按住 BOOT(PA0) 上电 → 板子以 BMP DFU 设备出现（1d50:6018 / 1d50:6017）
dfu-util -a 0 -s 0x08004000:leave -D blackmagic_blackpill_f411ce_ppvision_firmware.bin
```
> 你的板子有两个无丝印按键，大概率是 BOOT(PA0) + RESET：按住其中一个上电看能否进 DFU 即可确认。
> 若 dfu-util 未装，仍可用方法 1 的 SWD 命令烧主固件到 0x08004000。

## 移植版固件的重新编译（在 `blackmagic_fork` 目录）

```bash
cd /home/developer/sources/bmd/blackmagic_fork
bash build.sh        # 编译主固件 + bootloader，产物复制到 release/
bash build.sh clean  # 从零重新配置编译
```

## 重要提醒

1. **卖家固件（blackmagic.bin）按键进 DFU 无效**：复刻版源码（`dbe4c805` 起）把按键判断逻辑做了反转且构建未定义 `BMP_BOOTLOADER`，所以按 PA0 不会进 DFU。恢复/操作它请用 SWD（方法 1）或 BOOT0 拉高（方法 2）。
2. **移植版固件按键进 DFU 已修复**：恢复官方逻辑，按住 BOOT(PA0) 上电应可进入 BMP DFU。
3. **地址务必对应**：bootloader 烧 0x08000000，主固件烧 0x08004000；烧错地址会变砖（用 SWD 重新烧正确的即可恢复）。
4. **LED 极性**：移植版已按复刻板接法配置 LED（PB13/14/15、PC13）。若烧入后 LED 常亮/常灭（极性反），告诉我现象，我调整 `SET_*_STATE` 宏再给你新固件。
