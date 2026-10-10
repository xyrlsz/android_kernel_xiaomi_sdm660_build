#!/usr/bin/env bash
set -euo pipefail

COMMIT_FILE="/tmp/bakasu_commit.txt"
if [ ! -s "$COMMIT_FILE" ]; then
  echo "::error::Baka-SU commit file is missing: $COMMIT_FILE"
  exit 1
fi

KSU_COMMIT=$(tr -d '[:space:]' < "$COMMIT_FILE")
if [[ ! "$KSU_COMMIT" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "::error::Invalid Baka-SU commit SHA: $KSU_COMMIT"
  exit 1
fi

API_BASE="https://api.github.com/repos/Baka-SU/BakaSU"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 下载 Actions 产物必须带认证（匿名请求会 401）；未提供 token 时仍按匿名方式请求
CURL_AUTH=()
if [ -n "${GH_API_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer $GH_API_TOKEN")
fi

if ! curl -fsSL --retry 3 --retry-delay 2 \
  "${CURL_AUTH[@]}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_BASE/actions/workflows/build-manager.yml/runs?head_sha=$KSU_COMMIT&status=completed&per_page=100" \
  -o "$TMP_DIR/runs.json"; then
  echo "::error::Failed to query Baka-SU manager workflow runs for $KSU_COMMIT"
  exit 1
fi

RUN_ID=$(jq -r --arg commit "$KSU_COMMIT" \
  '[.workflow_runs[]? | select(.head_sha == $commit and .conclusion == "success")] | sort_by(.created_at) | last | .id // empty' \
  "$TMP_DIR/runs.json")
if [ -z "$RUN_ID" ]; then
  echo "::notice::No successful Baka-SU manager workflow run found for commit $KSU_COMMIT; skipping Manager APK"
  echo "manager_found=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

if ! curl -fsSL --retry 3 --retry-delay 2 \
  "${CURL_AUTH[@]}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --get --data-urlencode "name=Manager-release" --data-urlencode "per_page=100" \
  "$API_BASE/actions/runs/$RUN_ID/artifacts" \
  -o "$TMP_DIR/artifacts.json"; then
  echo "::error::Failed to query manager artifacts for Baka-SU workflow run $RUN_ID"
  exit 1
fi

ARTIFACT_ID=$(jq -r \
  '[.artifacts[]? | select(.name == "Manager-release" and .expired == false)] | sort_by(.created_at) | last | .id // empty' \
  "$TMP_DIR/artifacts.json")
if [ -z "$ARTIFACT_ID" ]; then
  echo "::notice::No unexpired Manager-release artifact found for Baka-SU commit $KSU_COMMIT (run $RUN_ID); skipping Manager APK"
  echo "manager_found=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# -L 跳到 blob 存储时 curl 会自行丢弃 Authorization 头，不会把 token 发到第三方
if ! curl -fLsS --retry 3 --retry-delay 2 \
  "${CURL_AUTH[@]}" \
  "$API_BASE/actions/artifacts/$ARTIFACT_ID/zip" \
  -o "$TMP_DIR/manager.zip"; then
  echo "::error::Failed to download Manager-release artifact $ARTIFACT_ID"
  exit 1
fi

unzip -tq "$TMP_DIR/manager.zip"
mkdir -p "$GITHUB_WORKSPACE/bakasu-manager"
mapfile -d '' MANAGER_APKS < <(find "$TMP_DIR" -type f -iname '*.apk' -print0)
if [ "${#MANAGER_APKS[@]}" -eq 0 ]; then
  echo "::notice::Manager-release artifact contains no APK for commit $KSU_COMMIT; skipping Manager APK"
  echo "manager_found=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

for APK in "${MANAGER_APKS[@]}"; do
  APK_NAME=$(basename "$APK")
  if [ -e "$GITHUB_WORKSPACE/bakasu-manager/$APK_NAME" ]; then
    echo "::error::Manager-release artifact contains duplicate APK filename: $APK_NAME"
    exit 1
  fi
  cp "$APK" "$GITHUB_WORKSPACE/bakasu-manager/$APK_NAME"
done

echo "Baka-SU manager commit: $KSU_COMMIT"
echo "Baka-SU manager workflow run: $RUN_ID"
echo "manager_found=true" >> "$GITHUB_OUTPUT"
echo "Downloaded manager APK(s):"
ls -lh "$GITHUB_WORKSPACE"/bakasu-manager/*.apk
