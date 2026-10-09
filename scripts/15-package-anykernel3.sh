#!/usr/bin/env bash
set -euo pipefail

cd /tmp/AnyKernel3

BAKASU_VER=$(cat /tmp/bakasu_tag.txt 2>/dev/null || echo "unknown")

ZIP="$GITHUB_WORKSPACE/boot-clover-bakasu-susfs-${BAKASU_VER}-anykernel-${GITHUB_RUN_NUMBER}.zip"
rm -f "$ZIP"

zip -r9 "$ZIP" . -x ".git/*" "README.md" "*.zip"

ls -lh "$ZIP"

# 先把清单存下来，避免 unzip 因 head/grep 提前退出收到 SIGPIPE（141）被 pipefail 判为失败
LIST=$(unzip -l "$ZIP")
echo "$LIST" | grep -q 'Image.gz' || { echo "::error::zip 中缺少 Image.gz"; exit 1; }
echo "$LIST" | grep -q '^ *[0-9]* .*anykernel.sh$' || { echo "::error::zip 中缺少 anykernel.sh"; exit 1; }
# clover_defconfig 无 =m 项，正常情况下不带模块；只有 14-copy-kernel.sh 真的放了 .ko，才要求 zip 里存在
if [ -d modules ] && [ -n "$(find modules -name '*.ko' -print -quit)" ]; then
  echo "$LIST" | grep -qE 'modules/vendor/lib/modules/[^/]+\.ko' || { echo "::error::zip 中缺少 vendor 内核模块"; exit 1; }
else
  echo "本内核没有可加载模块（全部内建），跳过模块校验"
fi

echo "===== zip 内容 ====="
echo "$LIST" | head -80 || true
