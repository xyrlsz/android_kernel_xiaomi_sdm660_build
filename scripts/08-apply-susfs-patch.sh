#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || { [ "$KERNEL_MINOR" != "4" ] && [ "$KERNEL_MINOR" != "19" ]; }; then
  echo "::error::仅支持 Linux 4.4 和 4.19 的 SUSFS 移植补丁；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADAPTATION_PATCH="$SCRIPT_DIR/patches/susfs-4.4-kallsyms-adaptation.patch"
PATCH_FILE=$(mktemp)
trap 'rm -f "$PATCH_FILE"' EXIT

if [ "$KERNEL_MINOR" = "4" ]; then
  PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/Patch/susfs_patch_to_4.4.patch"
else
  PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/Patch/susfs_patch_to_4.19.patch"
fi

echo "===== 下载 SUSFS Linux 4.${KERNEL_MINOR} 移植补丁 ====="
curl -fL --retry 3 --retry-delay 5 -o "$PATCH_FILE" "$PATCH_URL"

echo "===== 检查 SUSFS 补丁是否适配当前内核源码 ====="
if grep -Fq 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile ||
  grep -Fq 'susfs_spoof_cmdline_or_bootconfig' fs/proc/cmdline.c; then
  echo "::error::检测到 SUSFS 补丁或相关适配已存在，拒绝重复应用"
  exit 1
fi

echo "===== 检查 SUSFS Linux 4.${KERNEL_MINOR} 补丁是否适配当前源码 ====="
if [ "$KERNEL_MINOR" = "4" ]; then
  # 4.4 分支的 kallsyms 格式与上游 hunk 不同，使用本地适配补丁。
  if ! git apply --check --exclude=kernel/kallsyms.c "$PATCH_FILE" ||
    ! git apply --check "$ADAPTATION_PATCH"; then
    echo "::error::SUSFS 4.4 补丁无法应用到当前内核源码；请确认补丁基线兼容"
    exit 1
  fi
else
  if ! git apply --check "$PATCH_FILE"; then
    echo "::error::SUSFS 4.19 补丁无法应用到当前内核源码；请确认补丁基线兼容"
    exit 1
  fi
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
if [ "$KERNEL_MINOR" = "4" ]; then
  git apply --exclude=kernel/kallsyms.c "$PATCH_FILE"
  git apply "$ADAPTATION_PATCH"
else
  git apply "$PATCH_FILE"
fi

echo "===== 验证 SUSFS 补丁应用结果 ====="
for check in \
  'fs/susfs.c:SUSFS_VERSION' \
  'include/linux/susfs_def.h:susfs_is_current_proc_no_su' \
  'include/linux/susfs_def.h:susfs_starts_with' \
  'fs/Makefile:obj-$(CONFIG_KSU_SUSFS) += susfs.o' \
  'kernel/kallsyms.c:CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS'; do
  file=${check%%:*}
  needle=${check#*:}
  if [ ! -f "$file" ] || ! grep -Fq "$needle" "$file"; then
    echo "::error::SUSFS 补丁缺少 $needle（$file）"
    exit 1
  fi
done

echo "===== SUSFS 4.${KERNEL_MINOR} 补丁应用完成 ====="
