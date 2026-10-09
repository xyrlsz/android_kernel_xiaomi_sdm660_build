#!/usr/bin/env bash
set -euo pipefail

# sdm660 是 msm-4.4 内核树，clang 16+ 已经无法编译它（旧内核语法/内建函数都被移除）。
# 因此这里使用 LineageOS 的 clang-r416183b（Clang 12），这是 sdm660 4.4 上验证过的版本。
CLANG_DIR="/home/runner/clang"
rm -rf "$CLANG_DIR"

git clone --depth=1 --branch "$CLANG_BRANCH" \
  "https://github.com/${CLANG_REPO}.git" "$CLANG_DIR"

"$CLANG_DIR/bin/clang" --version

echo "$CLANG_DIR/bin" >> "$GITHUB_PATH"
