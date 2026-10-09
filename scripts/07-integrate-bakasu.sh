#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "===== 集成 Baka-SU 内核源码 ====="
echo "=========================================="

INPUT_TAG="${BAKASU_TAG_INPUT:-}"

if [ -n "$INPUT_TAG" ]; then
  BAKASU_REF="$INPUT_TAG"
  echo "使用手动指定的 Baka-SU ref: $BAKASU_REF"
else
  BAKASU_REF="main"
  echo "未指定 tag/ref，将使用 Baka-SU main 分支最新提交"
fi

echo "最终使用 Baka-SU ref: $BAKASU_REF"

# ---- 按指定 ref 或默认分支克隆 ----
rm -rf KernelSU
git clone --depth=1 --branch "$BAKASU_REF" "$BAKASU_REPO" KernelSU

cd KernelSU
KSU_COMMIT=$(git rev-parse HEAD)
KSU_SHORT_COMMIT=$(git rev-parse --short HEAD)
if [ -n "$INPUT_TAG" ]; then
  KSU_VERSION=$(git describe --tags --exact-match 2>/dev/null || echo "$BAKASU_REF")
else
  KSU_VERSION="latest-${KSU_SHORT_COMMIT}"
fi
echo "Baka-SU ref: $BAKASU_REF"
echo "Baka-SU version: $KSU_VERSION"
echo "Baka-SU commit: $KSU_COMMIT"
cd ..

# 保存版本信息，供后续步骤使用
echo "$KSU_VERSION" > /tmp/bakasu_tag.txt
echo "$KSU_COMMIT" > /tmp/bakasu_commit.txt

# 软链接到 drivers/kernelsu
ln -sf "$(pwd)/KernelSU/kernel" "$(pwd)/drivers/kernelsu"

# 注册到 drivers/Makefile
if ! grep -q "kernelsu" drivers/Makefile; then
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
  echo "✓ drivers/Makefile 已添加 kernelsu"
else
  echo "✓ drivers/Makefile 已包含 kernelsu"
fi

# 注册到 drivers/Kconfig
if ! grep -q "kernelsu" drivers/Kconfig; then
  cat >> drivers/Kconfig <<'EOF'

source "drivers/kernelsu/Kconfig"
EOF
  echo "✓ drivers/Kconfig 已添加 kernelsu"
else
  echo "✓ drivers/Kconfig 已包含 kernelsu"
fi

echo "===== Baka-SU 源码集成完成 ====="
