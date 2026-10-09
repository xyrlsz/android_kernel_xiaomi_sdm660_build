#!/usr/bin/env bash
set -euo pipefail

# crdroidandroid/android_kernel_xiaomi_sdm660 自带了老版 KernelSU（drivers/kernelsu + fs/kernel/security
# 里的 manual hook）。它的 hook 名称和调用方式与 Baka-SU 的 SUSFS inline hook 完全不兼容：
#   - inline hook 脚本会跳过任何已经包含 "ksu_handle" 的文件，导致 hook 注入不完整；
#   - Baka-SU 的 kernel/tools/inline_hook_check.mk 会检测到 ksu_vfs_read_hook / ksu_input_hook /
#     ksu_execveat_hook / ksu_init_rc_hook 这些旧 hook 并直接报错中止编译。
# 所以先把老的那套 KernelSU 集成整块拆掉，再按 Baka-SU + SUSFS inline hook 的方式重新装。

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STRIP_PATCH="$SCRIPT_DIR/patches/strip-legacy-kernelsu.patch"

echo "===== 检查是否还残留旧 KernelSU ====="
if [ ! -d drivers/kernelsu ]; then
  echo "::error::drivers/kernelsu 不存在；内核源码基线可能已变化，请重新确认补丁基线"
  exit 1
fi

echo "===== 检查旧 KernelSU hook 是否与预期一致 ====="
for check in \
  'fs/exec.c:ksu_handle_execveat' \
  'fs/open.c:ksu_handle_faccessat' \
  'fs/read_write.c:ksu_handle_vfs_read' \
  'fs/stat.c:ksu_handle_stat' \
  'fs/devpts/inode.c:ksu_handle_devpts' \
  'drivers/input/input.c:ksu_handle_input_handle_event'; do
  source=${check%%:*}
  hook=${check#*:}
  if ! grep -q "$hook" "$source"; then
    echo "::error::旧 KernelSU 的 $hook 未出现在 $source，补丁基线不匹配（用 patch -R 也能看出）"
    exit 1
  fi
done

echo "===== 移除旧 KernelSU 源码目录 ====="
rm -rf drivers/kernelsu

echo "===== 移除旧 KernelSU 的 hook 与注册项 ====="
git apply --check "$STRIP_PATCH"
git apply "$STRIP_PATCH"

echo "===== 验证清理结果 ====="
if grep -rq --include='*.c' --include='*.h' 'ksu_' fs kernel security drivers/input 2>/dev/null; then
  echo "::error::仍有 KernelSU 残留引用："
  grep -rn --include='*.c' --include='*.h' 'ksu_' fs kernel security drivers/input | head -20
  exit 1
fi
if grep -q 'kernelsu' drivers/Makefile drivers/Kconfig; then
  echo "::error::drivers/Makefile 或 drivers/Kconfig 仍引用 kernelsu"
  exit 1
fi

echo "===== 旧 KernelSU 清理完成 ====="
