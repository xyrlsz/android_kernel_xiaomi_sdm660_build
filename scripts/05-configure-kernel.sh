#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/runner/clang/bin:/tmp/gcc64/bin:/tmp/gcc32/bin:$PATH"
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-

CONFIG_ROOT="arch/arm64/configs"
CONFIG_INPUT="${DEFCONFIG_PATH:-}"
if [ -z "$CONFIG_INPUT" ]; then
  echo "::error::未设置 DEFCONFIG_PATH；请指定 *_defconfig 或 .config 配置片段"
  exit 1
fi

case "$CONFIG_INPUT" in
  "$CONFIG_ROOT"/*)
    CONFIG_INPUT="${CONFIG_INPUT#"$CONFIG_ROOT"/}"
    ;;
  arch/arm64/configs/*)
    CONFIG_INPUT="${CONFIG_INPUT#arch/arm64/configs/}"
    ;;
esac

case "$CONFIG_INPUT" in
  /*|..|../*|*/../*|*/..)
    echo "::error::配置路径必须位于 $CONFIG_ROOT 目录内：$DEFCONFIG_PATH"
    exit 1
    ;;
esac

CONFIG_FILE="$CONFIG_ROOT/$CONFIG_INPUT"
if [ ! -f "$CONFIG_FILE" ]; then
  case "$CONFIG_INPUT" in
    */*)
      echo "::error::找不到配置文件：$CONFIG_FILE"
      exit 1
      ;;
  esac

  mapfile -t CONFIG_MATCHES < <(find "$CONFIG_ROOT" -type f -name "$CONFIG_INPUT" -print | sort)
  if [ "${#CONFIG_MATCHES[@]}" -eq 0 ]; then
    echo "::error::在 $CONFIG_ROOT 下找不到配置文件：$CONFIG_INPUT"
    exit 1
  elif [ "${#CONFIG_MATCHES[@]}" -gt 1 ]; then
    echo "::error::配置文件名不唯一，请指定相对路径。匹配结果："
    printf '  %s\n' "${CONFIG_MATCHES[@]}"
    exit 1
  fi
  CONFIG_FILE="${CONFIG_MATCHES[0]}"
fi

CONFIG_RELATIVE_PATH="${CONFIG_FILE#"$CONFIG_ROOT"/}"
case "$CONFIG_FILE" in
  *_defconfig)
    CONFIG_TARGET="${CONFIG_RELATIVE_PATH}"
    echo "===== 使用 defconfig: $CONFIG_FILE ====="
    make O=out ARCH=arm64 SUBARCH=arm64 \
      CC="ccache clang" \
      HOSTCC="ccache clang" \
      KCFLAGS="-gdwarf-4" \
      "$CONFIG_TARGET"
    ;;
  *.config)
    BASE_DEFCONFIG="vendor/xiaomi/sdm660_defconfig"
    if [ ! -f "$CONFIG_ROOT/$BASE_DEFCONFIG" ]; then
      echo "::error::配置片段 $CONFIG_FILE 需要基础配置，但找不到 $CONFIG_ROOT/$BASE_DEFCONFIG"
      exit 1
    fi
    if [ ! -f scripts/kconfig/merge_config.sh ]; then
      echo "::error::找不到 scripts/kconfig/merge_config.sh，无法合并配置片段"
      exit 1
    fi
    echo "===== 使用基础 defconfig: $BASE_DEFCONFIG ====="
    make O=out ARCH=arm64 SUBARCH=arm64 \
      CC="ccache clang" \
      HOSTCC="ccache clang" \
      KCFLAGS="-gdwarf-4" \
      "$BASE_DEFCONFIG"
    echo "===== 合并配置片段: $CONFIG_FILE ====="
    bash scripts/kconfig/merge_config.sh -m -O out out/.config "$CONFIG_FILE"
    ;;
  *)
    echo "::error::不支持的配置文件类型：$CONFIG_FILE（应为 *_defconfig 或 *.config）"
    exit 1
    ;;
esac

CFG="out/.config"

# ============================================
# 保持 arm64 内核，同时启用 32 位 userspace 兼容支持
# （COMPAT_32BIT_TIME / KUSER_HELPERS 是 4.12+ 才有的选项，4.4 上没有）
# ============================================
./scripts/config --file "$CFG" -e COMPAT

# ============================================
# IPC 机制
# ============================================
./scripts/config --file "$CFG" \
  -e SYSCTL -e SYSVIPC -e POSIX_MQUEUE

# ============================================
# 核心命名空间
# ============================================
./scripts/config --file "$CFG" \
  -e NAMESPACES -e PID_NS -e UTS_NS -e IPC_NS \
  -e NET_NS -e USER_NS

# ============================================
# Seccomp
# ============================================
./scripts/config --file "$CFG" \
  -e SECCOMP -e SECCOMP_FILTER

# ============================================
# 控制组
# ============================================
./scripts/config --file "$CFG" \
  -e CGROUPS -e CGROUP_DEVICE -e CGROUP_PIDS -e MEMCG \
  -e CGROUP_SCHED -e FAIR_GROUP_SCHED -e CGROUP_FREEZER \
  -e CGROUP_NET_PRIO

# ============================================
# 设备文件系统
# ============================================
./scripts/config --file "$CFG" -e DEVTMPFS

# ============================================
# Overlay 文件系统
# ============================================
./scripts/config --file "$CFG" -e OVERLAY_FS

# ============================================
# tmpfs xattr / posix acl
# ============================================
./scripts/config --file "$CFG" \
  -e TMPFS_POSIX_ACL -e TMPFS_XATTR

# ============================================
# 固件加载
# ============================================
./scripts/config --file "$CFG" \
  -e FW_LOADER -e FW_LOADER_USER_HELPER -e FW_LOADER_COMPRESS

# ============================================
# 网络隔离
# ============================================
./scripts/config --file "$CFG" \
  -e VETH -e BRIDGE -e NETFILTER -e BRIDGE_NETFILTER \
  -e NETFILTER_ADVANCED -e NF_CONNTRACK \
  -e IP_NF_IPTABLES -e IP_NF_FILTER -e NF_NAT -e NF_TABLES \
  -e IP_NF_TARGET_MASQUERADE -e NETFILTER_XT_TARGET_MASQUERADE \
  -e NETFILTER_XT_TARGET_TCPMSS -e NETFILTER_XT_MATCH_ADDRTYPE \
  -e NF_CONNTRACK_NETLINK -e NF_NAT_REDIRECT \
  -e IP_ADVANCED_ROUTER -e IP_MULTIPLE_TABLES

# ============================================
# 旧内核兼容
# ============================================
./scripts/config --file "$CFG" \
  -e NF_CONNTRACK_IPV4 -e NF_NAT_IPV4 -e IP_NF_NAT

# ============================================
# 关键：禁用 ANDROID_PARANOID_NETWORK
# ============================================
./scripts/config --file "$CFG" -d ANDROID_PARANOID_NETWORK

# ============================================
# 只生成 clover 的 appended-DTB 镜像
# ============================================
# BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES 为空时，Image.gz-dtb 会把 dts 目录下所有 .dtb
# 全部拼接进内核镜像（几百 MB），所以必须指定本机型对应的 dtb（不带 .dtb 后缀）。
# 注意：这个名字是相对 arch/arm64/boot/dts/ 的路径
# （arch/arm64/boot/Makefile: DTB_OBJS := $(addprefix $(obj)/dts/,$(DTB_LIST))），
# 因此必须带 qcom/ 子目录，否则 Image.gz-dtb 会报 "No rule to make target"。
DTB_NAME="qcom/sdm660-mtp-clover"
if [ ! -f "arch/arm/boot/dts/${DTB_NAME}.dts" ]; then
  echo "::error::找不到 arch/arm/boot/dts/${DTB_NAME}.dts；请确认 defconfig 与 appended DTB 名称"
  exit 1
fi
./scripts/config --file "$CFG" \
  -e BUILD_ARM64_APPENDED_DTB_IMAGE -e IMG_GZ_DTB
./scripts/config --file "$CFG" \
  --set-str BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES "$DTB_NAME"

# 自动处理依赖
make O=out ARCH=arm64 SUBARCH=arm64 \
  CC="ccache clang" \
  HOSTCC="ccache clang" \
  KCFLAGS="-gdwarf-4" \
  olddefconfig

echo "===== appended DTB 配置检查 ====="
if ! grep -q "^CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES=\"${DTB_NAME}\"$" out/.config; then
  echo "::error::CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES 未生效（应为 \"${DTB_NAME}\"）"
  grep -E "CONFIG_BUILD_ARM64_APPENDED_DTB" out/.config || true
  exit 1
fi
echo "CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES=\"${DTB_NAME}\" OK"

echo "===== Droidspaces 必要配置检查 ====="
grep -E "CONFIG_(SYSCTL|SYSVIPC|POSIX_MQUEUE|NAMESPACES|PID_NS|UTS_NS|IPC_NS|NET_NS|USER_NS|SECCOMP|SECCOMP_FILTER|CGROUPS|CGROUP_DEVICE|CGROUP_PIDS|MEMCG|CGROUP_SCHED|FAIR_GROUP_SCHED|CGROUP_FREEZER|CGROUP_NET_PRIO|DEVTMPFS|OVERLAY_FS|TMPFS_POSIX_ACL|TMPFS_XATTR|FW_LOADER|FW_LOADER_USER_HELPER|FW_LOADER_COMPRESS|VETH|BRIDGE|NETFILTER|BRIDGE_NETFILTER|NETFILTER_ADVANCED|NF_CONNTRACK|IP_NF_IPTABLES|IP_NF_FILTER|NF_NAT|NF_TABLES|IP_NF_TARGET_MASQUERADE|NETFILTER_XT_TARGET_MASQUERADE|NETFILTER_XT_TARGET_TCPMSS|NETFILTER_XT_MATCH_ADDRTYPE|NF_CONNTRACK_NETLINK|NF_NAT_REDIRECT|IP_ADVANCED_ROUTER|IP_MULTIPLE_TABLES|NF_CONNTRACK_IPV4|NF_NAT_IPV4|IP_NF_NAT)=" out/.config || true

echo "===== ANDROID_PARANOID_NETWORK 检查 ====="
grep -E "CONFIG_ANDROID_PARANOID_NETWORK" out/.config || true

echo "===== 32 位 userspace 兼容配置检查 ====="
grep -E "CONFIG_COMPAT=" out/.config || true
if ! grep -q '^CONFIG_COMPAT=y$' out/.config; then
  echo "::error::CONFIG_COMPAT 未启用；无法运行 32 位 userspace"
  exit 1
fi
