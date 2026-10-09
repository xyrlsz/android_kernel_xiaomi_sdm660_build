#!/usr/bin/env bash
set -euo pipefail

echo "===== 最终 ccache 统计 ====="
ccache -s -v

echo "===== 缓存目录大小 ====="
du -sh "$CCACHE_DIR" 2>/dev/null || echo "无法获取"
