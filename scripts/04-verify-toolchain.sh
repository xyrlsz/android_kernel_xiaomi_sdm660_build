#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/runner/clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"

which clang
clang --version

which aarch64-linux-android-ld
which arm-linux-androideabi-ld
