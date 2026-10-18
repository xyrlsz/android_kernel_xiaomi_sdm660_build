#!/usr/bin/env bash
set -euo pipefail

# 上游 Droidspaces 的 non-GKI 补丁按较新内核的目录结构编写，需按当前源码布局选择补丁：
#   01 fix_kernel_panic_in_xt_qtaguid.patch    -> net/netfilter/xt_qtaguid.c
#      本树没有 qtaguid（Android 9 起内核已移除该驱动），这条 panic 路径不存在。
#   02 fix_restore cgroup file prefix handling -> kernel/cgroup.c (4.4)
#                                             or kernel/cgroup/cgroup.c (4.19+)
#      4.19+ 使用 Droidspaces 仓库的上游补丁；4.4 使用本地适配补丁。
# 除此之外本树还有一个上游补丁没有覆盖的回移缺陷（"启动容器就自动重启手机"的
# 根因），由本地补丁 03 修掉，见下方说明。
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CGROUP_PATCH_44="$SCRIPT_DIR/patches/droidspaces-4.4-cgroup-prefix.patch"
IPCNS_PATCH="$SCRIPT_DIR/patches/droidspaces-4.4-ipcns-user-ns.patch"
QTAGUID_PATCH_URL="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI/01.fix_kernel_panic_in_xt_qtaguid.patch"
CGROUP_PATCH_URL="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/main/Documentation/resources/kernel-patches/non-GKI/02.fix_restore%20cgroup%20file%20prefix%20handling%20.patch"
CGROUP_PATCH_TEMP=""
QTAGUID_PATCH_TEMP=""

cleanup() {
  [ -z "$CGROUP_PATCH_TEMP" ] || rm -f "$CGROUP_PATCH_TEMP"
  [ -z "$QTAGUID_PATCH_TEMP" ] || rm -f "$QTAGUID_PATCH_TEMP"
}
trap cleanup EXIT

echo "===== 应用 Droidspaces 容器补丁 ====="

# ---------------------------------------------------------------------------
# 补丁 03（本树必需）：启动容器就重启手机的根因。
#
# 本树把 4.8 的 mount_ns(fs_type, flags, data, ns, user_ns, fill_super) 回移了
# 回来，ipc/mqueue.c 的 mqueue_mount() 也改成了把 ns->user_ns 传下去。但是
# ipc/namespace.c 的 create_ipc_ns() 仍是 4.4 的顺序：
#
#     ns = kmalloc(...);            /* 不清零，user_ns 是脏数据 */
#     atomic_set(&ns->count, 1);
#     err = mq_init_ns(ns);         /* -> kern_mount_data() -> mqueue_mount()
#                                      -> mount_ns(..., ns->user_ns, ...)
#                                      -> sget_userns() -> alloc_super()
#                                      -> get_user_ns(脏指针) -> 解引用崩溃 */
#     ...
#     ns->user_ns = get_user_ns(user_ns);   /* 太晚了 */
#
# 于是任何 unshare(CLONE_NEWIPC)（启动容器必做）都会 Oops，而本设备 defconfig
# 打开了 CONFIG_PANIC_ON_OOPS，所以表现为"一启动容器就重启"：
#   sget_userns+0xfc <- mount_ns <- mqueue_mount <- mount_fs <- vfs_kern_mount
#   <- kern_mount_data <- mq_init_ns <- copy_ipcs <- create_new_namespaces
#   <- unshare_nsproxy_namespaces <- SyS_unshare
# 上游同一系列的回移把赋值放在了 mq_init_ns() 之前，这里按其顺序补回去。
# ---------------------------------------------------------------------------
# 判定标准：ns->user_ns 的赋值是否已经出现在 mq_init_ns() 之前
ipcns_fixed() {
  awk '/ns->user_ns = get_user_ns\(user_ns\);/ { u = NR }
       /err = mq_init_ns\(ns\);/ { m = NR }
       END { exit !(u && m && u < m) }' ipc/namespace.c
}

if ipcns_fixed; then
  echo "✓ ipc/namespace.c 中 ns->user_ns 已在 mq_init_ns() 之前初始化，跳过"
else
  git apply --check "$IPCNS_PATCH"
  git apply "$IPCNS_PATCH"
  if ! ipcns_fixed; then
    echo "::error::IPC namespace user_ns 修复未生效（ipc/namespace.c）"
    exit 1
  fi
  echo "✓ ipc/namespace.c user_ns 初始化顺序修复已应用（容器启动复位根因）"
fi

# ---------------------------------------------------------------------------
# 补丁 02：以 CGRP_ROOT_NOPREFIX 挂载的层级里，控制器文件名会丢掉子系统前缀
# （cpuset.cpus 变成 cpus），runc/LXC 仍按带前缀的名字打开文件并失败。这里把带前缀
# 的名字额外做成指向同一文件的符号链接。
# ---------------------------------------------------------------------------
CGROUP_MARKER='kernfs_create_link(cgrp->kn, '
if [ -f kernel/cgroup.c ]; then
  CGROUP_FILE="kernel/cgroup.c"
  CGROUP_PATCH="$CGROUP_PATCH_44"
elif [ -f kernel/cgroup/cgroup.c ]; then
  CGROUP_FILE="kernel/cgroup/cgroup.c"
  CGROUP_PATCH_TEMP=$(mktemp)
  echo "===== 下载 Droidspaces 上游 cgroup 前缀补丁 ====="
  curl -fL --retry 3 --retry-delay 5 -o "$CGROUP_PATCH_TEMP" "$CGROUP_PATCH_URL"
  CGROUP_PATCH="$CGROUP_PATCH_TEMP"
else
  echo "::error::找不到支持的 cgroup 源文件（kernel/cgroup.c 或 kernel/cgroup/cgroup.c）"
  exit 1
fi

if grep -q "$CGROUP_MARKER" "$CGROUP_FILE"; then
  echo "✓ $CGROUP_FILE 已包含 cgroup 前缀修复，跳过"
else
  if [ ! -f "$CGROUP_PATCH" ]; then
    echo "::error::缺少适配当前源码布局的补丁：$CGROUP_PATCH"
    exit 1
  fi
  if ! git apply --check "$CGROUP_PATCH"; then
    echo "::error::cgroup 前缀补丁无法应用到 $CGROUP_FILE"
    exit 1
  fi
  git apply "$CGROUP_PATCH"
  if ! grep -q "$CGROUP_MARKER" "$CGROUP_FILE"; then
    echo "::error::cgroup 前缀修复未生效（$CGROUP_FILE）"
    exit 1
  fi
  echo "✓ $CGROUP_FILE cgroup 前缀修复已应用"
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
  QTAGUID_PATCH_TEMP=$(mktemp)
  curl -fL --retry 3 --retry-delay 5 -o "$QTAGUID_PATCH_TEMP" "$QTAGUID_PATCH_URL"
  if ! git apply --check "$QTAGUID_PATCH_TEMP"; then
    echo "::error::上游 qtaguid 补丁无法应用到当前内核源码"
    exit 1
  fi
  git apply "$QTAGUID_PATCH_TEMP"
  if grep -q 'dev_get_stats(iface_entry->net_dev' net/netfilter/xt_qtaguid.c; then
    echo "::error::xt_qtaguid panic 修复未生效"
    exit 1
  fi
  echo "✓ xt_qtaguid panic 修复已应用"
fi

echo "===== Droidspaces 容器补丁处理完成 ====="
