#!/bin/bash
# 自动安装/卸载 Black Magic Probe udev 规则
#
# 用法:
#   bash install-udev-rules.sh           # 安装规则
#   bash install-udev-rules.sh --uninstall  # 卸载规则
#   bash install-udev-rules.sh --check   # 只检查当前状态，不修改
#
# 规则来源: docs/99-blackmagic.rules
# 安装目标: /etc/udev/rules.d/99-blackmagic.rules
#
# 效果:
#   - BMP 的 GDB 口固定为 /dev/ttyBmpGdb，UART 口固定为 /dev/ttyBmpTarg
#   - BMP 固件 (1d50:6018) / bootloader DFU (1d50:6017) / ST DFU (0483:df11)
#     权限放开为 0666，无需 root 即可访问（dfu-util / gdb / openocd）
#
# 需要 root（sudo）。非 root 运行时自动提示用 sudo 重跑。

set -u

# ---- 路径（脚本位于 fork 仓库 tools/ 目录下）----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORK_DIR="$(dirname "$SCRIPT_DIR")"
RULE_SRC="$FORK_DIR/docs/99-blackmagic.rules"
RULE_NAME="99-blackmagic.rules"
RULE_DEST="/etc/udev/rules.d/$RULE_NAME"

# ---- 检查规则源文件 ----
if [ ! -f "$RULE_SRC" ]; then
    echo "!! 找不到规则文件: $RULE_SRC"
    exit 1
fi

# ---- root 检查 ----
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "!! 需要 root 权限，自动尝试 sudo 重跑..."
        exec sudo bash "$0" "$@"
    fi
}

# ---- 安装 ----
install_rules() {
    echo "==== 安装 udev 规则 ===="
    echo "  来源: $RULE_SRC"
    echo "  目标: $RULE_DEST"
    cp "$RULE_SRC" "$RULE_DEST"
    echo "  ✅ 规则已复制"

    echo
    echo "==== 重载 udev 规则 ===="
    udevadm control --reload-rules
    udevadm trigger
    echo "  ✅ 已重载并触发"

    echo
    echo "==== 验证 ===="
    if [ -f "$RULE_DEST" ]; then
        echo "  ✅ 规则文件存在: $RULE_DEST"
        # 语法校验（udevadm test 需要设备，退而求其次检查文件权限）
        ls -l "$RULE_DEST"
    fi
}

# ---- 卸载 ----
uninstall_rules() {
    echo "==== 卸载 udev 规则 ===="
    if [ -f "$RULE_DEST" ]; then
        rm -f "$RULE_DEST"
        echo "  ✅ 已删除 $RULE_DEST"
    else
        echo "  （规则文件不存在，无需删除）"
    fi
    udevadm control --reload-rules
    udevadm trigger
    echo "  ✅ 已重载 udev"
}

# ---- 检查状态 ----
check_status() {
    echo "==== udev 规则状态检查 ===="
    if [ -f "$RULE_DEST" ]; then
        echo "  ✅ 规则已安装: $RULE_DEST"
        echo "  --- 内容预览 ---"
        grep -vE "^\s*#|^\s*$" "$RULE_DEST" | head -12
    else
        echo "  ❌ 规则未安装: $RULE_DEST"
    fi
    echo
    echo "==== 设备节点检查 ===="
    ls -l /dev/ttyBmpGdb /dev/ttyBmpTarg 2>/dev/null || echo "  （BMP 未插入或符号链接未生成）"
    echo
    echo "==== 相关 USB 设备 ===="
    lsusb 2>/dev/null | grep -iE "1d50|0483:df11" || echo "  （未找到 BMP/STM DFU 设备）"
}

# ---- 主流程 ----
case "${1:-}" in
    --uninstall)
        check_root "$@"
        uninstall_rules
        ;;
    --check)
        check_status
        ;;
    *)
        check_root "$@"
        install_rules
        echo
        echo "==== 完成 ===="
        echo "若 BMP 已插入，请重新拔插一次 USB 让符号链接生效"
        echo "验证: bash $0 --check"
        ;;
esac
