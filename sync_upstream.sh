#!/bin/bash
# 一键同步 blackmagic_fork 与上游官方仓库
#
# 用法:
#   bash sync_upstream.sh            # 拉取上游 + 合并（不推送）
#   bash sync_upstream.sh --push     # 拉取上游 + 合并 + 推送到 origin
#   bash sync_upstream.sh --dry-run  # 只查看差异，不改动
#
# 远程配置:
#   origin   = git@github.com:IotaHydrae/blackmagic.git   (你的 fork)
#   upstream = https://codeberg.org/blackmagic-debug/blackmagic.git (官方上游)
#
# 原理:
#   1. git fetch upstream   拉取官方最新到本地引用（不影响工作区）
#   2. 显示上游新增提交
#   3. git merge upstream/main 合并到你的 main（保留你的移植提交）
#   4. --push 时推送到 origin
#
# 注意:
#   - 合并前建议先 git stash 保存未提交的修改
#   - 若有冲突，脚本不自动解决，会提示手动处理

set -u

# 脚本位于 fork 仓库根目录
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO" || { echo "!! 无法进入目录: $REPO"; exit 1; }
echo "同步仓库: $REPO"

# 确保 upstream remote 存在
if ! git remote | grep -qx upstream; then
    echo "!! 缺少 upstream remote，添加："
    git remote add upstream https://codeberg.org/blackmagic-debug/blackmagic.git
fi

echo
echo "==== 1. 拉取上游更新 ===="
git fetch upstream || { echo "!! fetch 失败，检查网络"; exit 1; }

echo
echo "==== 2. 上游新增提交 ===="
NEW=$(git log --oneline HEAD..upstream/main)
if [ -z "$NEW" ]; then
    echo "（无新提交，你的 fork 已是最新）"
else
    echo "$NEW"
fi

echo
echo "==== 3. 你的本地提交（合并后会保留）===="
git log --oneline upstream/main..HEAD

if [ "${1:-}" = "--dry-run" ]; then
    echo
    echo "==== DRY-RUN: 不合并，仅预览 ===="
    echo "要合并的内容: $(git rev-list --count HEAD..upstream/main) 个提交"
    exit 0
fi

if [ -n "$NEW" ]; then
    echo
    echo "==== 4. 合并 upstream/main 到当前分支 ===="
    git merge upstream/main
    RC=$?
    if [ $RC -ne 0 ]; then
        echo
        echo "!! 合并冲突，需要手动解决："
        echo "   git status          # 看冲突文件"
        echo "   git diff            # 看冲突标记"
        echo "   # 编辑解决后:"
        echo "   git add <文件> && git commit"
        exit 1
    fi
    echo
    echo "✅ 合并成功！当前状态："
    git log --oneline -3
else
    echo
    echo "✅ 已是最新，无需合并"
fi

if [ "${1:-}" = "--push" ]; then
    echo
    echo "==== 5. 推送到 origin (GitHub) ===="
    git push origin main || { echo "!! push 失败，检查 SSH key / 网络"; exit 1; }
    echo "✅ 已推送"
else
    echo
    echo "确认无误后推送: bash $0 --push"
fi
