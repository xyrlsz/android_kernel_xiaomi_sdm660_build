#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/runner/clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"

echo "===== Build 开始 ====="
echo "时间: $(date)"
ccache -s

START_TIME=$(date +%s)

set +e
make -j"$(nproc)" O=out ARCH=arm64 SUBARCH=arm64 \
  CC="ccache clang" \
  HOSTCC="ccache clang" \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-android- \
  CROSS_COMPILE_ARM32=arm-linux-androideabi- \
  KCFLAGS="-gdwarf-4" \
  Image.gz-dtb modules \
  2>&1 | tee build.log
BUILD_STATUS=${PIPESTATUS[0]}
set -e

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "===== Build 结束 ====="
echo "耗时: ${DURATION} 秒 ($((DURATION / 60)) 分钟)"
ccache -s

if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "===== Build failed ====="
  tail -100 build.log
  exit 1
fi

ls -lh out/arch/arm64/boot/Image.gz-dtb out/arch/arm64/boot/Image.gz 2>/dev/null || true
find out -name "*.ko" | head -30 || true
echo "模块总数: $(find out -name '*.ko' | wc -l)"
