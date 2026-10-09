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

# 本内核树的 clover_defconfig 没有任何 =m 项（MODPOST 0 modules），因此通常没有 .ko。
# 而且当前 AnyKernel3 master 的 ak3-core.sh 已不再处理 modules/ 安装，
# 所以只在确实存在 .ko 时才打包模块目录，避免 zip 里出现空目录 / do.modules 与实际不符。
MODCOUNT=$(find out -name '*.ko' | wc -l)
if [ "$MODCOUNT" -gt 0 ]; then
  # do.systemless=0 时，AnyKernel3 按 .ko 在 modules/ 里的相对路径决定写入位置：
  # modules/vendor/lib/modules/x.ko -> /vendor/lib/modules/x.ko。
  # crDroid/LineageOS 的 sdm660 机型默认把内核模块装到 /vendor/lib/modules。
  MODDIR="$AK/modules/vendor/lib/modules"
  rm -rf "$AK/modules"
  mkdir -p "$MODDIR"
  find out -name '*.ko' -exec cp -v {} "$MODDIR/" \;
  sed -i 's/^do.modules=.*/do.modules=1/' "$AK/anykernel.sh"
else
  rm -rf "$AK/modules"
  sed -i 's/^do.modules=.*/do.modules=0/' "$AK/anykernel.sh"
fi
echo "模块数量: $MODCOUNT"
grep -E '^do.modules=' "$AK/anykernel.sh"

echo "===== AnyKernel3 内容 ====="
ls -lh "$AK"/Image.gz*
if [ -f "$AK/dtb" ]; then
  ls -lh "$AK/dtb"
else
  echo "未带独立 dtb（使用 appended DTB 或沿用原 boot）"
fi
