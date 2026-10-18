#!/usr/bin/env bash
set -euo pipefail

# sdm660 的旧版内核树使用兼容性较好的 clang-r416183b（Clang 12），避免新版本
# Clang 对旧内核语法及内建函数的兼容性问题。
CLANG_DIR="/home/runner/clang"
rm -rf "$CLANG_DIR"

git clone --depth=1 --branch "$CLANG_BRANCH" \
  "https://github.com/${CLANG_REPO}.git" "$CLANG_DIR"

"$CLANG_DIR/bin/clang" --version

echo "$CLANG_DIR/bin" >> "$GITHUB_PATH"
