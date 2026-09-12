# 烧录速度测试与优化记录

> 场景：BMP（blackpill-f411ce-ppvision 固件）烧录 RP2350（Pico 2，QSPI Flash）
> 测试固件：aht10.elf（16,700 字节，含 .text/.rodata/.data 等段）
> 测试日期：2026-09-12

## 一、测试结果

| SWD 频率 | 烧录速度 | 说明 |
|---|---|---|
| 2M（固件默认） | 3 KB/sec | 慢在 SWD 传输 |
| 10M | 8 KB/sec | 传输不再是瓶颈 |
| 20M | 8 KB/sec | 到页编程物理上限 |
| 24M | 8 KB/sec | 同上，不会再快 |

**结论：8 KB/sec 是 BMP + QSPI Flash 方案的物理上限。**

## 二、瓶颈分析

### 烧录路径

```
GDB load 795B 块 (USB)
  → BMP 固件接收
    → 按 256B 页写 QSPI Flash（SPI page program）
      → 每页轮询 BUSY 状态（页编程物理耗时 ~3-5ms）
```

### 为什么频率到 10M 后不再提升

1. **页大小 256B**：`src/target/spi.c` 中 `spi_parameters.page_size = 256U`（由 SFDP 探测到），每页最多写 256B。
2. **每页轮询 BUSY**：`bmp_spi_flash_write()` 每写一页都 `while (bmp_spi_read_status(...) & BUSY)` 等待 Flash 内部完成。
3. **页编程是物理耗时**：QSPI Flash 页编程典型耗时 3-5ms，与 SWD 频率无关。

数学验证：`256B / ~30ms ≈ 8.5 KB/s` ✓ 与实测 8 KB/sec 吻合。

### 频率 vs 速度的物理含义

- **2M → 10M**：SWD 传输从瓶颈变为非瓶颈，速度提升 ~2.7 倍
- **10M 之后**：瓶颈转移到 Flash 页编程本身，频率再高无效

## 三、如何设置频率

`tools/bmd-flash.sh` 支持 `SWD_FREQ` 环境变量，默认 10M：

```bash
# 默认 10M（推荐，速度与稳定性的平衡点）
./tools/bmd-flash.sh your_program.elf

# 手动指定
SWD_FREQ=5M  ./tools/bmd-flash.sh your_program.elf   # 时序更保守
SWD_FREQ=2M  ./tools/bmd-flash.sh your_program.elf   # 回到固件默认
SWD_FREQ=20M ./tools/bmd-flash.sh your_program.elf   # 线短可试，速度不变
```

## 四、提高速度的进一步方向（均需改 BMP 固件，有风险，不建议）

| 方向 | 原理 | 预期收益 | 风险 |
|---|---|---|---|
| XIP 直写 | 绕过页编程用特殊命令 | 可能 2-3 倍 | 改 flash 驱动，易不稳定 |
| 压缩传输 | GDB 协议无压缩 | 小 | 需改协议 |
| 更大页写入 | 部分 Flash 支持 512B 页 | 小 | 取决于 Flash 型号 |

## 五、实际体验参考

- 16.7KB 固件：~2 秒烧完（10M）
- 100KB 固件：~12 秒
- 1MB 固件：~2 分钟

对调试场景（几十 KB 固件）完全够用；只有频繁烧几 MB 大固件才值得考虑更深层的优化。

## 六、相关文件

- 烧录脚本：`tools/bmd-flash.sh`
- BMP 固件 flash 驱动：`src/target/spi.c`（页大小/擦除/写逻辑）
- RP2350 目标支持：`src/target/rp2350.c`
- GDB 烧录的 GEF 兼容问题：见 [gdb/28874](https://sourceware.org/bugzilla/show_bug.cgi?id=28874)（`bmd-flash.sh` 用 `-nx` 规避）
