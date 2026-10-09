#!/usr/bin/env bash
set -euo pipefail

rm -rf /tmp/AnyKernel3
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git /tmp/AnyKernel3

cd /tmp/AnyKernel3

rm -f zImage Image.gz Image.lz4 Image.gz-dtb dtb dtbo.img 2>/dev/null || true

BAKASU_VER=$(cat /tmp/bakasu_tag.txt 2>/dev/null || echo "unknown")

sed -i "s/^kernel.string=.*/kernel.string=Baka-SU + SUSFS ${BAKASU_VER} Kernel for Xiaomi Mi Pad 4 (clover) by GitHub Actions/" anykernel.sh
sed -i 's/^do.devicecheck=.*/do.devicecheck=1/' anykernel.sh
sed -i 's/^do.modules=.*/do.modules=1/' anykernel.sh
sed -i 's/^do.systemless=.*/do.systemless=0/' anykernel.sh
sed -i 's/^do.cleanup=.*/do.cleanup=1/' anykernel.sh
sed -i 's/^do.cleanuponabort=.*/do.cleanuponabort=0/' anykernel.sh
sed -i 's/^device.name1=.*/device.name1=clover/' anykernel.sh
sed -i 's/^device.name2=.*/device.name2=clover/' anykernel.sh
# anykernel.sh 里只有 properties() 的选项是小写（kernel.string / do.* / device.name*），
# 顶层的 shell 变量是大写（BLOCK / IS_SLOT_DEVICE / RAMDISK_COMPRESSION），别写错大小写。
# clover（小米平板 4）是 A-only 设备，boot 分区就叫 boot。
sed -i 's|^BLOCK=.*|BLOCK=boot;|' anykernel.sh
sed -i 's/^IS_SLOT_DEVICE=.*/IS_SLOT_DEVICE=auto;/' anykernel.sh
sed -i 's/^RAMDISK_COMPRESSION=.*/RAMDISK_COMPRESSION=auto;/' anykernel.sh

echo "===== anykernel.sh 关键项 ====="
grep -E 'kernel.string|do.devicecheck|do.modules|device.name1|^BLOCK=|^IS_SLOT_DEVICE=|^RAMDISK_COMPRESSION=' anykernel.sh

# 上面三条 sed 若因上游变量改名而失效，会被静默忽略并打出不可刷入的 zip，所以这里强制校验
for key in 'BLOCK=boot;' 'IS_SLOT_DEVICE=auto;' 'RAMDISK_COMPRESSION=auto;' \
           'device.name1=clover' 'do.modules=1' 'do.devicecheck=1'; do
  grep -qF "$key" anykernel.sh || { echo "::error::anykernel.sh 未正确设置（$key）"; exit 1; }
done
