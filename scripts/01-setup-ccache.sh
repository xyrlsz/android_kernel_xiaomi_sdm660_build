#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$CCACHE_DIR"

{
  echo "CCACHE_DIR=$CCACHE_DIR"
  echo "CCACHE_MAXSIZE=5G"
  echo "CCACHE_COMPRESS=true"
  echo "CCACHE_COMPRESSLEVEL=6"
  echo "CCACHE_BASEDIR=${GITHUB_WORKSPACE}"
  echo "CCACHE_NOHASHDIR=true"
  echo "CCACHE_SLOPPINESS=time_macros,include_file_ctime,include_file_mtime"
  echo "CCACHE_CPP2=true"
  echo "CCACHE_DEPEND=true"
} >> "$GITHUB_ENV"
