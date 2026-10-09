#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
  bc bison build-essential ccache curl flex gawk \
  git gnupg gperf imagemagick libncurses-dev \
  lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
  libgnutls28-dev liblz4-tool libsdl1.2-dev libssl-dev \
  libxml2 libxml2-utils lzop pngcrush rsync schedtool \
  squashfs-tools xsltproc zip zlib1g-dev unzip \
  python3 python-is-python3 python3-pip \
  libncurses5 libtinfo5

echo "===== ccache version ====="
ccache --version | head -1
