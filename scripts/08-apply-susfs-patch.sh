#!/usr/bin/env bash
set -euo pipefail

KERNEL_MAJOR=$(sed -n 's/^VERSION = //p' Makefile)
KERNEL_MINOR=$(sed -n 's/^PATCHLEVEL = //p' Makefile)
if [ "$KERNEL_MAJOR" != "4" ] || { [ "$KERNEL_MINOR" != "4" ] && [ "$KERNEL_MINOR" != "19" ]; }; then
  echo "::error::仅支持 Linux 4.4 和 4.19 的 SUSFS 移植补丁；当前版本为 ${KERNEL_MAJOR:-unknown}.${KERNEL_MINOR:-unknown}"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADAPTATION_PATCH_44="$SCRIPT_DIR/patches/susfs-4.4-kallsyms-adaptation.patch"
ADAPTATION_PATCH_419="$SCRIPT_DIR/patches/susfs-4.19-fs-context-adaptation.patch"
PATCH_FILE=$(mktemp)
TEST_DIR=$(mktemp -d)
APPLY_LOG="$TEST_DIR/apply.log"
trap 'rm -f "$PATCH_FILE"; rm -rf "$TEST_DIR"' EXIT

if [ "$KERNEL_MINOR" = "4" ]; then
  PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/Patch/susfs_patch_to_4.4.patch"
else
  PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/Patch/susfs_patch_to_4.19.patch"
fi

echo "===== 下载 SUSFS Linux 4.${KERNEL_MINOR} 移植补丁 ====="
curl -fL --retry 3 --retry-delay 5 -o "$PATCH_FILE" "$PATCH_URL"

echo "===== 检查 SUSFS 补丁是否适配当前内核源码 ====="
if grep -Fq 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile ||
  grep -Fq 'susfs_spoof_cmdline_or_bootconfig' fs/proc/cmdline.c; then
  echo "::error::检测到 SUSFS 补丁或相关适配已存在，拒绝重复应用"
  exit 1
fi

echo "===== 检查 SUSFS Linux 4.${KERNEL_MINOR} 补丁是否适配当前源码 ====="
if [ "$KERNEL_MINOR" = "4" ]; then
  # 4.4 分支的 kallsyms 格式与上游 hunk 不同，使用本地适配补丁。
  if ! git apply --check --exclude=kernel/kallsyms.c "$PATCH_FILE" ||
    ! git apply --check "$ADAPTATION_PATCH_44"; then
    echo "::error::SUSFS 4.4 补丁无法应用到当前内核源码；请确认补丁基线兼容"
    exit 1
  fi
else
  expected_rejects=(
    fs/Makefile.rej
    fs/namespace.c.rej
    fs/proc/cmdline.c.rej
    fs/proc/task_mmu.c.rej
    fs/super.c.rej
    mm/memory.c.rej
  )

  validate_419_rejects() {
    local root=$1
    local reject
    local source
    local expected_hunks
    local found

    for reject in "${expected_rejects[@]}"; do
      if [ ! -f "$root/$reject" ]; then
        echo "::error::SUSFS 4.19 补丁冲突位置变化，缺少预期诊断 $reject"
        return 1
      fi

      expected_hunks=1
      if [ "$reject" = "fs/namespace.c.rej" ] || [ "$reject" = "mm/memory.c.rej" ]; then
        expected_hunks=2
      fi
      found=$(grep -c '^@@' "$root/$reject")
      if [ "$found" -ne "$expected_hunks" ]; then
        echo "::error::SUSFS 4.19 补丁冲突块数量变化：$reject（预期 $expected_hunks，实际 $found）"
        return 1
      fi
    done

    while IFS= read -r source; do
      [ -n "$source" ] || continue
      if [ -f "$root/$source.rej" ]; then
        case " ${expected_rejects[*]} " in
          *" $source.rej "*) ;;
          *)
            echo "::error::SUSFS 4.19 补丁出现未审核冲突：$source.rej"
            return 1
            ;;
        esac
      fi
    done < <(sed -n 's#^diff --git a/\([^ ]*\) b/.*#\1#p' "$PATCH_FILE")

    return 0
  }

  stage_upstream_patch() {
    local root=$1
    local status=0
    git -C "$root" apply --reject "$PATCH_FILE" >"$APPLY_LOG" 2>&1 || status=$?
    if [ "$status" -ne 1 ]; then
      echo "::error::无法按预期检查 SUSFS 4.19 上游补丁（git apply 状态 $status）"
      cat "$APPLY_LOG"
      return 1
    fi
    validate_419_rejects "$root"
  }

  echo "===== 检查 SUSFS 4.19 上游补丁及分支适配 ====="
  while IFS= read -r source; do
    [ -n "$source" ] || continue
    if [ -f "$source" ]; then
      mkdir -p "$TEST_DIR/$(dirname "$source")"
      cp -p "$source" "$TEST_DIR/$source"
    fi
  done < <(sed -n 's#^diff --git a/\([^ ]*\) b/.*#\1#p' "$PATCH_FILE")

  if ! stage_upstream_patch "$TEST_DIR"; then
    echo "::error::SUSFS 4.19 上游补丁冲突超出已验证的 crDroid fs_context 适配范围"
    exit 1
  fi
  if ! git -C "$TEST_DIR" apply --check "$ADAPTATION_PATCH_419"; then
    echo "::error::SUSFS 4.19 分支适配补丁无法应用到上游补丁结果"
    exit 1
  fi
fi

echo "===== 应用 SUSFS 内核侧补丁 ====="
if [ "$KERNEL_MINOR" = "4" ]; then
  git apply --exclude=kernel/kallsyms.c "$PATCH_FILE"
  git apply "$ADAPTATION_PATCH_44"
else
  stage_upstream_patch "."
  git apply "$ADAPTATION_PATCH_419"
  for reject in "${expected_rejects[@]}"; do
    rm -f "$reject"
  done
fi

echo "===== 验证 SUSFS 补丁应用结果 ====="
for check in \
  'fs/susfs.c:SUSFS_VERSION' \
  'include/linux/susfs_def.h:susfs_is_current_proc_no_su' \
  'include/linux/susfs_def.h:susfs_starts_with' \
  'fs/Makefile:obj-$(CONFIG_KSU_SUSFS) += susfs.o' \
  'kernel/kallsyms.c:CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS'; do
  file=${check%%:*}
  needle=${check#*:}
  if [ ! -f "$file" ] || ! grep -Fq "$needle" "$file"; then
    echo "::error::SUSFS 补丁缺少 $needle（$file）"
    exit 1
  fi
done

echo "===== SUSFS 4.${KERNEL_MINOR} 补丁应用完成 ====="
