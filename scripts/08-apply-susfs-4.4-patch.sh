#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || [ "$KERNEL_MINOR" != "4" ]; then
  echo "::error::指定的 SUSFS 补丁仅适用于 Linux 4.4；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/40b190d46080085b9bf7c67233ae1dc3cad5edc8/Patches/Patch/susfs_patch_to_4.4.patch"
EXPECTED_SHA256="f56740dc698186700f8178621981bc1430cf02ab898b3ffbd684b69380c4a407"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADAPTATION_PATCH="$SCRIPT_DIR/patches/susfs-4.4-kallsyms-adaptation.patch"
PATCH_FILE=$(mktemp)
trap 'rm -f "$PATCH_FILE"' EXIT

echo "===== 下载 SUSFS v2.3.0 Linux 4.4 移植补丁 ====="
curl -fL --retry 3 --retry-delay 5 -o "$PATCH_FILE" "$PATCH_URL"
echo "$EXPECTED_SHA256  $PATCH_FILE" | sha256sum --check --status || {
  echo "::error::SUSFS 补丁 SHA-256 校验失败"
  exit 1
}

echo "===== 检查 SUSFS 补丁是否适配当前内核源码 ====="
if grep -Fq 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile ||
  grep -Fq 'susfs_spoof_cmdline_or_bootconfig' fs/proc/cmdline.c; then
  echo "::error::检测到 SUSFS 补丁或相关适配已存在，拒绝重复应用"
  exit 1
fi

# kernel/kallsyms.c 在该树上用的是 KALLSYM_FMT + iter->value 的写法，上游补丁的 hunk 对不上，
# 所以这里跳过它，改用本仓库维护的适配补丁。
echo "===== 检查 SUSFS 补丁（适配 sdm660 的 kernel/kallsyms.c）====="
if ! git apply --check --exclude=kernel/kallsyms.c "$PATCH_FILE" ||
  ! git apply --check "$ADAPTATION_PATCH"; then
  echo "::error::SUSFS 补丁无法应用到当前内核源码；请确认补丁基线兼容"
  exit 1
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
git apply --exclude=kernel/kallsyms.c "$PATCH_FILE"
git apply "$ADAPTATION_PATCH"

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

echo "===== SUSFS 4.4 补丁应用完成 ====="
