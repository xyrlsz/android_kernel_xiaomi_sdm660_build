#!/usr/bin/env bash
set -euo pipefail

# 上游 Droidspaces 的 non-GKI 补丁是按 4.9+ 的目录结构写的，直接套在本 4.4 树上
# 一个都落不下去（会被静默跳过，等于什么都没做）：
#   01 fix_kernel_panic_in_xt_qtaguid.patch    -> net/netfilter/xt_qtaguid.c
#      本树没有 qtaguid（Android 9 起内核已移除该驱动），这条 panic 路径不存在。
#   02 fix_restore cgroup file prefix handling -> kernel/cgroup/cgroup.c
#      4.4 的 cgroup 代码在 kernel/cgroup.c，且 cgroup v1 的前缀取 legacy_name
#      而不是 name（见 cgroup_file_name()），所以 02 必须按本树重新生成。
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CGROUP_PATCH="$SCRIPT_DIR/patches/droidspaces-4.4-cgroup-prefix.patch"
QTAGUID_PATCH_URL="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI/01.fix_kernel_panic_in_xt_qtaguid.patch"

echo "===== 应用 Droidspaces 容器补丁 ====="

# ---------------------------------------------------------------------------
# 补丁 02：以 CGRP_ROOT_NOPREFIX 挂载的层级里，控制器文件名会丢掉子系统前缀
# （cpuset.cpus 变成 cpus），runc/LXC 仍按带前缀的名字打开文件并失败。这里把带前缀
# 的名字额外做成指向同一文件的符号链接。
# ---------------------------------------------------------------------------
if grep -q 'kernfs_create_link(cgrp->kn, ' kernel/cgroup.c; then
  echo "✓ kernel/cgroup.c 已包含 cgroup 前缀修复，跳过"
else
  git apply --check "$CGROUP_PATCH"
  git apply "$CGROUP_PATCH"
  if ! grep -q 'kernfs_create_link(cgrp->kn, ' kernel/cgroup.c; then
    echo "::error::cgroup 前缀修复未生效（kernel/cgroup.c）"
    exit 1
  fi
  echo "✓ kernel/cgroup.c cgroup 前缀修复已应用"
fi

# ---------------------------------------------------------------------------
# 补丁 01：xt_qtaguid 在非激活接口上调用 dev_get_stats() 导致内核 panic（NAT 路径
# 会走到这里）。本 4.4 树没有该驱动，这种情况下跳过即可。
# ---------------------------------------------------------------------------
if [ ! -f net/netfilter/xt_qtaguid.c ]; then
  echo "✓ 本内核没有 net/netfilter/xt_qtaguid.c（Android 9 起已移除 qtaguid），无需补丁 01"
elif ! grep -q 'dev_get_stats(iface_entry->net_dev' net/netfilter/xt_qtaguid.c; then
  echo "✓ net/netfilter/xt_qtaguid.c 已包含 panic 修复，跳过"
else
  echo "----- 应用上游补丁 01（xt_qtaguid panic）-----"
  QTAGUID_PATCH=$(mktemp)
  trap 'rm -f "$QTAGUID_PATCH"' EXIT
  curl -fL --retry 3 --retry-delay 5 -o "$QTAGUID_PATCH" "$QTAGUID_PATCH_URL"
  git apply "$QTAGUID_PATCH"
  if grep -q 'dev_get_stats(iface_entry->net_dev' net/netfilter/xt_qtaguid.c; then
    echo "::error::xt_qtaguid panic 修复未生效"
    exit 1
  fi
  echo "✓ xt_qtaguid panic 修复已应用"
fi

echo "===== Droidspaces 容器补丁处理完成 ====="
