#!/usr/bin/env bash
set -euo pipefail

echo "===== 应用 Droidspaces non-GKI 补丁 ====="

PATCH_DIR="/tmp/droidspaces-patches"
mkdir -p "$PATCH_DIR"

curl -L --retry 3 --retry-delay 5 \
  -o "$PATCH_DIR/01.fix_xt_qtaguid_panic.patch" \
  "https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI/01.fix_kernel_panic_in_xt_qtaguid.patch" || true

curl -L --retry 3 --retry-delay 5 \
  -o "$PATCH_DIR/02.fix_cgroup_prefix.patch" \
  "https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI/02.fix_restore%20cgroup%20file%20prefix%20handling%20.patch" || true

echo "===== 下载结果 ====="
ls -la "$PATCH_DIR/"

APPLIED=0
SKIPPED=0

for patch_file in "$PATCH_DIR"/*.patch; do
  [ -f "$patch_file" ] || continue
  PATCH_NAME=$(basename "$patch_file")
  echo "----- 检查: $PATCH_NAME -----"

  if [ ! -s "$patch_file" ]; then
    echo "⚠ 补丁文件为空，跳过"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if head -c 100 "$patch_file" | grep -qi "<!DOCTYPE\|<html"; then
    echo "⚠ 补丁下载得到 HTML 页面，跳过"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if patch -p1 --dry-run < "$patch_file" > /dev/null 2>&1; then
    echo "✓ Dry-run 通过，正式应用..."
    patch -p1 < "$patch_file"
    APPLIED=$((APPLIED + 1))
    echo "✓ $PATCH_NAME 应用成功"
  else
    echo "⚠ Dry-run 失败，跳过此补丁"
    SKIPPED=$((SKIPPED + 1))
  fi
done

echo "已应用: $APPLIED 个，已跳过: $SKIPPED 个"
