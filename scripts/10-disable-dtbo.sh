#!/usr/bin/env bash
set -euo pipefail

# 为什么要处理 DTBO：
#   arch/arm64/boot/dts/qcom 是指向 arch/arm/boot/dts/qcom 的软链接，该 Makefile 里所有
#   dtbo- overlay 目标（msm8996 8 个、msm8998 9 个、sdm660 只给 lavender 1 个）都被
#   ifeq ($(CONFIG_BUILD_ARM64_DT_OVERLAY),y) 包住：
#
#     ifeq ($(CONFIG_BUILD_ARM64_DT_OVERLAY),y)
#       dtbo-$(CONFIG_MACH_XIAOMI_LAVENDER) += sdm660-mtp-lavender-overlay.dtbo
#     else
#       dtb-$(CONFIG_MACH_XIAOMI_LAVENDER) := sdm660-mtp-lavender.dtb   # 基础 dtb 只在 else 里
#     endif
#
#   也就是说这个开关一开，对应机型的基础 dtb 就不再生成了（改由 overlay 的 -base 机制产出）。
#   而 sdm660 这代小米机型（含 clover）的 ROM 用 appended DTB：
#   device/xiaomi/sdm660-common/BoardConfigCommon.mk 里 BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb，
#   没有 BOARD_PREBUILT_DTBOIMAGE，也没有 dtbo 分区，所以根本不需要 overlay。
#   因此这里不去 sed 改 Makefile（那样反而会把基础 dtb 一起弄没），而是直接关掉这个开关，
#   让 else 分支生效、正常产出基础 dtb。

export PATH="/home/runner/clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"

CFG="out/.config"
DEVICE_MACH_PREFIX="CONFIG_MACH_XIAOMI_"

if [ ! -f "$CFG" ]; then
  echo "::error::找不到 $CFG；请先运行 05-configure-kernel.sh"
  exit 1
fi

if ! grep -q '^CONFIG_BUILD_ARM64_DT_OVERLAY=y$' "$CFG"; then
  echo "===== 本配置不会编译任何 DTBO overlay，无需处理 ====="
  echo "依据：$CFG 中 CONFIG_BUILD_ARM64_DT_OVERLAY 未启用，"
  echo "     arch/arm/boot/dts/qcom/Makefile 里所有 dtbo- 目标都不可达，dtbo-y 为空。"
  echo "当前启用的小米机型配置："
  grep -E "^${DEVICE_MACH_PREFIX}[A-Z0-9_]+=y$" "$CFG" | sed 's/^/  /' || true
  exit 0
fi

echo "===== 检测到 CONFIG_BUILD_ARM64_DT_OVERLAY=y，关闭 DTBO overlay 编译 ====="
./scripts/config --file "$CFG" -d BUILD_ARM64_DT_OVERLAY

make O=out ARCH=arm64 SUBARCH=arm64 \
  CC="ccache clang" \
  HOSTCC="ccache clang" \
  KCFLAGS="-gdwarf-4" \
  olddefconfig

echo "===== 验证 ====="
if grep -q '^CONFIG_BUILD_ARM64_DT_OVERLAY=y$' "$CFG"; then
  echo "::error::CONFIG_BUILD_ARM64_DT_OVERLAY 仍然启用，DTBO overlay 仍会被编译"
  exit 1
fi
echo "CONFIG_BUILD_ARM64_DT_OVERLAY 已关闭，Makefile 走 else 分支（产出基础 dtb，不产出 .dtbo）"

QCOM_MAKEFILE=$(realpath arch/arm64/boot/dts/qcom/Makefile)
found=0
while read -r sym; do
  line=$(grep -E "^dtb-\\\$\\($sym\\)" "$QCOM_MAKEFILE" || true)
  if [ -n "$line" ]; then
    echo "  $sym -> ${line%%:*}"
    found=$((found + 1))
  fi
done < <(sed -n "s/^\(${DEVICE_MACH_PREFIX}[A-Z0-9_]*\)=y$/\1/p" "$CFG")

if [ "$found" -eq 0 ]; then
  echo "::error::在 $QCOM_MAKEFILE 中找不到当前机型对应的 dtb- 定义；appended DTB 将没有 dtb 可用"
  exit 1
fi
