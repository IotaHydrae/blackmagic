#!/bin/bash
# 一键编译 blackmagic_fork 的 blackpill-f411ce-ppvision 固件
#
# 用法:
#   bash build.sh             # 编译固件 + bootloader
#   bash build.sh clean       # 清理构建目录后重新编译
#   bash build.sh setup-only  # 只配置 meson，不编译
#   bash build.sh -v          # 详细输出（显示完整编译日志）
#
# 产物:
#   build-ppvision/blackmagic_blackpill_f411ce_ppvision_firmware.bin
#   build-ppvision/blackmagic_blackpill_f411ce_ppvision_bootloader.bin
#   并自动复制到 release/ 目录（带 SHA256 校验和）

set -e

# ---- 路径（脚本位于 fork 仓库根目录）----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORK_DIR="$SCRIPT_DIR"
BUILD_DIR="$FORK_DIR/build-ppvision"
CROSS_FILE="$FORK_DIR/cross-file/blackpill-f411ce-ppvision.ini"
OUT_DIR="$FORK_DIR/release"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1 && shift

# ---- 检查目录 ----
[ -d "$FORK_DIR" ] || { echo "!! 找不到 fork 目录: $FORK_DIR"; exit 1; }
[ -f "$CROSS_FILE" ] || { echo "!! 找不到 cross-file: $CROSS_FILE"; exit 1; }

# ---- 定位 meson ----
# venv 在 workspace 顶层（脚本上一级目录），其次系统 PATH
VENV_DIR="$(dirname "$SCRIPT_DIR")/.venv"
find_meson() {
    if [ -x "$VENV_DIR/bin/meson" ]; then
        echo "$VENV_DIR/bin/meson"
    elif command -v meson >/dev/null 2>&1; then
        command -v meson
    else
        return 1
    fi
}
MESON="$(find_meson)" || { echo "!! 未找到 meson。安装: python3 -m venv $VENV_DIR && $VENV_DIR/bin/pip install meson"; exit 1; }
echo "使用 meson: $MESON"
echo "构建目录:   $BUILD_DIR"
echo

# ---- 配置阶段 ----
setup() {
    echo "==== meson setup ===="
    # 显式指定源目录（FORK_DIR），避免 clean 后误把 build 目录当源
    (cd "$FORK_DIR" && "$MESON" setup "$BUILD_DIR" --cross-file "$CROSS_FILE")
    echo
}

if [ "${1:-}" = "clean" ]; then
    echo "==== 清理构建目录 ===="
    rm -rf "$BUILD_DIR"
    setup
elif [ -f "$BUILD_DIR/build.ninja" ]; then
    echo "==== 构建目录已配置，跳过 setup ===="
    echo "（如需重新配置: bash $0 clean）"
    echo
else
    setup
fi

if [ "${1:-}" = "setup-only" ]; then
    echo "✅ 配置完成（未编译）"
    exit 0
fi

# ---- 编译阶段 ----
echo "==== 编译主固件 ===="
if [ "$VERBOSE" = "1" ]; then
    ninja -C "$BUILD_DIR"
else
    ninja -C "$BUILD_DIR" 2>&1 | tail -15
fi

echo
echo "==== 编译 bootloader ===="
if [ "$VERBOSE" = "1" ]; then
    ninja -C "$BUILD_DIR" boot-bin boot-hex
else
    ninja -C "$BUILD_DIR" boot-bin boot-hex 2>&1 | tail -5
fi

# ---- 复制产物到备份目录 ----
echo
echo "==== 复制产物到 $OUT_DIR ===="
mkdir -p "$OUT_DIR"
FIRMWARE_BIN="$BUILD_DIR/blackmagic_blackpill_f411ce_ppvision_firmware.bin"
BOOTLOADER_BIN="$BUILD_DIR/blackmagic_blackpill_f411ce_ppvision_bootloader.bin"

if [ -f "$FIRMWARE_BIN" ]; then
    cp "$FIRMWARE_BIN" "$OUT_DIR/"
    echo "  ✅ 主固件:   $(basename "$FIRMWARE_BIN")"
    echo "     SHA256:   $(sha256sum "$OUT_DIR/$(basename "$FIRMWARE_BIN")" | cut -d' ' -f1)"
    echo "     大小:     $(stat -c%s "$OUT_DIR/$(basename "$FIRMWARE_BIN")") 字节"
else
    echo "  ⚠️ 主固件未生成!"
fi

if [ -f "$BOOTLOADER_BIN" ]; then
    cp "$BOOTLOADER_BIN" "$OUT_DIR/"
    echo "  ✅ bootloader: $(basename "$BOOTLOADER_BIN")"
    echo "     SHA256:   $(sha256sum "$OUT_DIR/$(basename "$BOOTLOADER_BIN")" | cut -d' ' -f1)"
    echo "     大小:     $(stat -c%s "$OUT_DIR/$(basename "$BOOTLOADER_BIN")") 字节"
else
    echo "  ⚠️ bootloader 未生成!"
fi

echo
echo "==== 完成 ===="
echo "烧录地址: bootloader -> 0x08000000, 主固件 -> 0x08004000"
echo "烧录方法见 $FORK_DIR/docs/烧录方法.md"
