#!/usr/bin/env bash
set -euo pipefail

AK="/tmp/AnyKernel3"
BOOT_DIR="out/arch/arm64/boot"

# sdm660 4.4 用 appended DTB：Image.gz-dtb 已经把 sdm660-mtp-clover.dtb 拼在 Image.gz 后面
if [ -f "$BOOT_DIR/Image.gz-dtb" ]; then
  cp "$BOOT_DIR/Image.gz-dtb" "$AK/Image.gz-dtb"
  echo "使用 $BOOT_DIR/Image.gz-dtb（appended DTB）"
elif [ -f "$BOOT_DIR/Image.gz" ]; then
  cp "$BOOT_DIR/Image.gz" "$AK/Image.gz"
  if [ -f "$BOOT_DIR/dtb" ]; then
    cp "$BOOT_DIR/dtb" "$AK/dtb"
  elif [ -f "$BOOT_DIR/dtb.img" ]; then
    cp "$BOOT_DIR/dtb.img" "$AK/dtb"
  fi
  echo "使用 $BOOT_DIR/Image.gz（无 appended DTB）"
else
  echo "::error::既没有 Image.gz-dtb 也没有 Image.gz"
  ls -la "$BOOT_DIR"
  exit 1
fi

# do.systemless=0 时，AnyKernel3 按 .ko 在 modules/ 里的相对路径决定写入位置：
# modules/vendor/lib/modules/x.ko -> /vendor/lib/modules/x.ko（并按 vendor 目录打 SELinux 标签）。
# crDroid/LineageOS 的 sdm660 机型默认把内核模块装到 /vendor/lib/modules。
MODDIR="$AK/modules/vendor/lib/modules"
rm -rf "$AK/modules"
mkdir -p "$MODDIR"
find out -name '*.ko' -exec cp -v {} "$MODDIR/" \;
echo "模块数量: $(find "$AK/modules" -name '*.ko' | wc -l)"

echo "===== AnyKernel3 内容 ====="
ls -lh "$AK"/Image.gz*
if [ -f "$AK/dtb" ]; then
  ls -lh "$AK/dtb"
else
  echo "未带独立 dtb（使用 appended DTB 或沿用原 boot）"
fi
