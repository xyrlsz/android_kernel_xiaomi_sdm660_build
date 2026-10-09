#!/usr/bin/env bash
set -euo pipefail

# 64-bit GCC for arm64 kernel builds
git clone --depth=1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 \
  /tmp/gcc64

echo "/tmp/gcc64/bin" >> "$GITHUB_PATH"

# 32-bit compatibility toolchain for arm64 kernel's compat VDSO.
git clone --depth=1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 \
  /tmp/gcc32

echo "/tmp/gcc32/bin" >> "$GITHUB_PATH"

# 建立不带 -4.9 后缀的软链接（内核构建脚本使用这种命名）
cd /tmp/gcc64/bin
for f in aarch64-linux-android-4.9-*; do
  [ -e "$f" ] || continue
  ln -sf "$f" "${f/aarch64-linux-android-4.9-/aarch64-linux-android-}"
done

cd /tmp/gcc32/bin
for f in arm-linux-androideabi-4.9-*; do
  [ -e "$f" ] || continue
  ln -sf "$f" "${f/arm-linux-androideabi-4.9-/arm-linux-androideabi-}"
done
