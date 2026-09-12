#!/bin/bash
# BMP (Black Magic Probe) 固件测试脚本
# 用法: bash bmd-test.sh
# 会在系统里找到 ttyACM 设备并用 GDB 通过 BMP 的 GDB 接口查询固件状态

set -u

echo "=== 1. 查找 BMP 设备节点 ==="
ls -lh /dev/ttyACM* 2>/dev/null || { echo "未找到 /dev/ttyACM* 设备节点！"; exit 1; }

# 优先尝试 ttyACM0（BMP 的 GDB 接口），失败则尝试下一个
TTY=""
for dev in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2; do
    if [ -e "$dev" ]; then
        TTY="$dev"
        break
    fi
done
echo "使用 GDB 接口: $TTY"
echo

echo "=== 2. 通过 GDB 连接并查询固件 ==="
# monitor version: 固件版本
# monitor help:    支持的命令列表
# monitor s:       扫描目标（当前未接目标芯片时也能看到电源电压信息）
if command -v arm-none-eabi-gdb >/dev/null 2>&1; then
    GDB=arm-none-eabi-gdb
elif command -v gdb >/dev/null 2>&1; then
    GDB=gdb
else
    echo "未找到 gdb！"
    exit 1
fi

echo "使用 GDB: $GDB"
"$GDB" -batch \
    -ex "set pagination off" \
    -ex "target extended-remote $TTY" \
    -ex "echo \n----- monitor version -----\n" \
    -ex "monitor version" \
    -ex "echo \n----- monitor help -----\n" \
    -ex "monitor help" \
    -ex "echo \n----- monitor scan (探测目标) -----\n" \
    -ex "monitor s" \
    2>&1

echo
echo "=== 3. 测试目标 UART 串口 (ttyACM1, 若存在) ==="
UART_DEV=""
for dev in /dev/ttyACM1 /dev/ttyACM0; do
    if [ -e "$dev" ] && [ "$dev" != "$TTY" ]; then
        UART_DEV="$dev"
        break
    fi
done
if [ -n "$UART_DEV" ]; then
    echo "目标 UART 接口: $UART_DEV (可用 minicom/picocom/python 打开，波特率任意，BMP 会透传)"
else
    echo "未找到第二个 ttyACM 设备（可能只有一个接口或固件配置不同）"
fi

echo
echo "=== 完成 ==="
