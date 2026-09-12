#!/bin/bash
# 一键启动 GDB 连接 BMP，设置推荐布局并定位到现场
#
# 用法:
#   bash bmd-gdb.sh                  # 连接 BMP，halt 目标并查看现场（无符号）
#   bash bmd-gdb.sh your_program.elf # 连接 + 加载符号 + 定位现场
#   BMP_DEV=/dev/ttyACM0 bash bmd-gdb.sh   # 指定设备（默认自动找 ttyBmpGdb/ttyACM*）
#
# GDB 选择: gdb-multiarch > arm-none-eabi-gdb > gdb（多架构能正确解析 ARM ELF）
#
# 推荐布局（GDB TUI）:
#   - 顶部寄存器窗口 (regs)
#   - 下方分割窗口: 源码 (src) + 反汇编 (asm)
#   - 定位现场: 自动 halt 目标，显示 PC 附近反汇编和调用栈
#
# 进入 GDB 后的常用操作:
#   continue / c          继续运行
#   si / ni               单步指令/汇编
#   b main                源码断点（需加载 ELF）
#   layout next           切换布局
#   monitor help          查看 BMP 固件命令
#   Ctrl+C                （目标运行中）中断回现场

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
# 优先 gdb-multiarch（多架构，能正确解析 ARM/RISC-V ELF 与反汇编），
# 其次 arm-none-eabi-gdb（ARM 专用），最后回退原生 gdb（仅 x86-64）。
GDB="$(command -v gdb-multiarch 2>/dev/null || command -v arm-none-eabi-gdb 2>/dev/null || command -v gdb 2>/dev/null || true)"
if [ -z "$GDB" ]; then
    echo "!! 未找到 gdb（需要 gdb-multiarch / arm-none-eabi-gdb / gdb）"
    exit 1
fi
echo "GDB: $GDB"

# ---- 3. 可选 ELF 符号文件 ----
ELF="${1:-}"
if [ -n "$ELF" ]; then
    if [ ! -f "$ELF" ]; then
        echo "!! ELF 文件不存在: $ELF"
        exit 1
    fi
    echo "加载符号: $ELF"
fi

# ---- 4. 构造 GDB 命令序列 ----
CMDS=(
    "set pagination off"
    "target extended-remote $BMP_DEV"
)

if [ -n "$ELF" ]; then
    CMDS+=(
        "file $ELF"
        "monitor swd_scan"
        "attach 1"
    )
else
    CMDS+=(
        "monitor swd_scan"
        "attach 1"
    )
fi

CMDS+=(
    "layout regs"          # 顶部寄存器窗口
    "layout split"         # 下方: 源码 + 反汇编
    "echo \n========== 现场 ==========\n"
    "info registers"       # 全部寄存器
    "echo \n---- PC 附近反汇编 ----\n"
    "x/12i \$pc"           # 当前指令流
    "echo \n---- 调用栈 ----\n"
    "bt"                   # backtrace
)

ARGS=()
for c in "${CMDS[@]}"; do ARGS+=(-ex "$c"); done

# ---- 5. 启动 GDB（TUI 交互模式）----
echo
echo "==== 启动 GDB (TUI) ===="
exec "$GDB" -q -tui "${ARGS[@]}"
