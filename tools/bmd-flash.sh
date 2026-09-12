#!/bin/bash
# 通过 BMP 把指定 ELF 直接烧录到目标芯片 Flash
#
# 用法:
#   bash bmd-flash.sh your_program.elf          # 烧录 + 复位运行后退出
#   bash bmd-flash.sh your_program.elf --interactive  # 烧录后进入 GDB 交互
#   BMP_DEV=/dev/ttyACM0 bash bmd-flash.sh your_program.elf  # 指定设备
#   SWD_FREQ=10M bash bmd-flash.sh your_program.elf   # 指定 SWD 频率（默认 10M）
#
# 流程:
#   1. 连接 BMP（自动找 /dev/ttyBmpGdb 或 /dev/ttyACM*）
#   2. 设置 SWD 频率（monitor frequency，提高烧录速度）
#   3. 加载 ELF，扫描 SWD 目标，attach
#   4. load 写入 Flash（GDB/BMP flash 编程算法，自动处理擦除）
#   5. 复位并运行（--interactive 时停在复位后，交给你操作）
#
# GDB 选择: gdb-multiarch > arm-none-eabi-gdb > gdb
# 频率说明: 固件默认 2MHz，烧录较慢；SWD_FREQ 默认 10M 可显著提速。
#   若目标/线缆时序不稳，降为 5M 或 2M 重试。

set -u

# ---- 1. 定位 BMP 设备 ----
BMP_DEV="${BMP_DEV:-}"
if [ -z "$BMP_DEV" ]; then
    for d in /dev/ttyBmpGdb /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2; do
        if [ -e "$d" ]; then BMP_DEV="$d"; break; fi
    done
fi
if [ -z "$BMP_DEV" ]; then
    echo "!! 未找到 BMP 设备（/dev/ttyBmpGdb 或 /dev/ttyACM*）"
    echo "   请确认 BMP 已连接，或指定: BMP_DEV=/dev/ttyACM0 bash $0"
    exit 1
fi
echo "BMP GDB 接口: $BMP_DEV"

# ---- 2. 定位 GDB ----
GDB="$(command -v gdb-multiarch 2>/dev/null || command -v arm-none-eabi-gdb 2>/dev/null || command -v gdb 2>/dev/null || true)"
if [ -z "$GDB" ]; then
    echo "!! 未找到 gdb（需要 gdb-multiarch / arm-none-eabi-gdb / gdb）"
    exit 1
fi
echo "GDB: $GDB"

# ---- 3. 检查 ELF 参数 ----
ELF="${1:-}"
if [ -z "$ELF" ]; then
    echo "!! 用法: bash $0 <your_program.elf> [--interactive]"
    exit 1
fi
if [ ! -f "$ELF" ]; then
    echo "!! ELF 文件不存在: $ELF"
    exit 1
fi
INTERACTIVE=0
[ "${2:-}" = "--interactive" ] && INTERACTIVE=1
echo "烧录镜像: $ELF"

# ---- SWD 频率（默认 10MHz，可环境变量覆盖）----
SWD_FREQ="${SWD_FREQ:-10M}"
echo "SWD 频率: $SWD_FREQ"

# ---- 4. 构造 GDB 命令 ----
CMDS=(
    "set pagination off"
    "target extended-remote $BMP_DEV"
    "monitor frequency $SWD_FREQ"
    "file $ELF"
    "monitor swd_scan"
    "attach 1"               # attach 会自动 halt 目标
    "echo \n========== 烧录开始 ==========\n"
    "load"                     # 写入 Flash（含擦除），自动校验
    "echo \n========== 烧录完成 ==========\n"
)

if [ "$INTERACTIVE" = "1" ]; then
    # 交互模式：复位后停在入口，交给你继续操作
    CMDS+=(
        "monitor reset"
        "echo \n镜像已烧录。输入 continue 运行，或单步调试。\n"
    )
else
    # 批处理模式：复位并运行，然后退出
    CMDS+=(
        "monitor reset"
        "continue"
        "echo \n目标已复位运行。\n"
    )
fi

ARGS=()
for c in "${CMDS[@]}"; do ARGS+=(-ex "$c"); done

# ---- 5. 执行 GDB（带自动重试）----
# GDB 对 BMP 裸机目标 attach 存在已知 bug（gdb/28874）：
#   inferior_thread: Assertion 'current_thread_ != nullptr' failed
# GEF/pwndbg 等插件的事件钩子会加重此 bug，故用 -nx 禁用 .gdbinit。
# 崩溃后重启 GDB 再试一次通常即可成功，这里最多重试 2 次。
flash_once() {
    if [ "$INTERACTIVE" = "1" ]; then
        "$GDB" -q -nx "${ARGS[@]}"
    else
        "$GDB" -q -nx -batch "${ARGS[@]}"
    fi
}

echo
echo "==== 开始烧录 ===="
RC=1
for attempt in 1 2; do
    echo "---- 第 $attempt 次尝试 ----"
    flash_once
    RC=$?
    if [ $RC -eq 0 ]; then
        break
    fi
    echo "!! GDB 退出码 $RC"
    if [ $attempt -lt 2 ]; then
        echo "   这是 GDB 对 BMP 的已知 attach bug（gdb/28874），自动重试..."
        sleep 1
    fi
done

if [ "$INTERACTIVE" = "0" ]; then
    echo
    if [ $RC -eq 0 ]; then
        echo "✅ 烧录完成"
    else
        echo "!! 烧录失败（退出码 $RC）"
        echo "   若持续失败，请检查:"
        echo "   - BMP 固件是否支持该目标（monitor swd_scan 能否列出）"
        echo "   - 目标供电 / SWD 接线"
        echo "   - 手动调试: $GDB -q $ELF"
    fi
fi
exit $RC
