#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/runner/clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"

CFG="out/.config"

echo "===== 启用 Baka-SU + SUSFS inline-hook 配置 ====="
# THREAD_INFO_IN_TASK 是 Baka-SU 的 KSU_SUSFS 的依赖项。sdm660 4.4 的 arch/arm64/Kconfig
# 里已经 select THREAD_INFO_IN_TASK，正常情况下不需要手动打开，这里显式写一遍更直观。
./scripts/config --file "$CFG" \
  -e KSU \
  -e THREAD_INFO_IN_TASK \
  -e KSU_SUSFS \
  -d KSU_MANUAL_HOOK \
  -d KSU_TRACEPOINT_HOOK

echo "===== 启用 SUSFS 各子功能（4.4 移植补丁里均已实现）====="
./scripts/config --file "$CFG" \
  -e KSU_SUSFS_SUS_PATH \
  -e KSU_SUSFS_SUS_MOUNT \
  -e KSU_SUSFS_SUS_KSTAT \
  -e KSU_SUSFS_SPOOF_UNAME \
  -e KSU_SUSFS_ENABLE_LOG \
  -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
  -e KSU_SUSFS_OPEN_REDIRECT \
  -e KSU_SUSFS_SUS_MAP

# Inline hooks use SUSFS hooks, not Kprobes or Baka-SU's manual-hook mode.
./scripts/config --file "$CFG" -d KPROBES
./scripts/config --file "$CFG" \
  -d KSU_MANUAL_HOOK_AUTO_INPUT_HOOK \
  -d KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
  -d KSU_MANUAL_HOOK_AUTO_INITRC_HOOK

# 处理依赖
make O=out ARCH=arm64 SUBARCH=arm64 \
  CC="ccache clang" \
  HOSTCC="ccache clang" \
  KCFLAGS="-gdwarf-4" \
  olddefconfig

echo ""
echo "===== Baka-SU + SUSFS inline-hook 配置检查 ====="
grep -E "CONFIG_(KSU|THREAD_INFO_IN_TASK|KPROBES)" out/.config || true

if ! grep -q '^CONFIG_KSU_SUSFS=y$' out/.config; then
  echo "::error::CONFIG_KSU_SUSFS 未启用；请确认所选 Baka-SU 版本包含 SUSFS 支持及其依赖满足"
  exit 1
fi

if ! grep -q '^CONFIG_THREAD_INFO_IN_TASK=y$' out/.config; then
  echo "::error::CONFIG_THREAD_INFO_IN_TASK 未启用；Baka-SU 的 KSU_SUSFS 依赖它（SUSFS 用 thread_info.flags 存状态）"
  exit 1
fi

if [ ! -f fs/susfs.c ] || ! grep -Fq 'susfs.o' fs/Makefile; then
  echo "::error::内核侧 SUSFS 补丁未生效（fs/susfs.c）"
  exit 1
fi

if grep -q '^CONFIG_KSU_MANUAL_HOOK=y$' out/.config ||
  grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y$' out/.config; then
  echo "::error::SUSFS inline-hook 模式不能与 manual-hook 或 tracepoint-hook 模式同时启用"
  exit 1
fi
