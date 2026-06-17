#!/bin/bash
set -e

# Base directory
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Architectures
ARCHS="arm64-v8a armeabi-v7a x86_64"

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

download_file() {
  echo "Downloading $2 from $1..."
  curl -L -o "$2" "$1"
}

# 1. hev-socks5-tproxy
TPROXY_TAG=$(get_latest_release "heiher/hev-socks5-tproxy")
echo "hev-socks5-tproxy version: $TPROXY_TAG"

# 2. ipt2socks
IPT2SOCKS_TAG=$(get_latest_release "zfl9/ipt2socks")
echo "ipt2socks version: $IPT2SOCKS_TAG"

# 3. dnsproxy
DNSPROXY_TAG=$(get_latest_release "AdguardTeam/dnsproxy")
echo "dnsproxy version: $DNSPROXY_TAG"

# 4. redsocks2
REDSOCKS2_URL_ARM64="https://github.com/Xndm-S/redsocks2-static/releases/download/1.0/redsocks2_arm64"
REDSOCKS2_URL_ARMV7="https://github.com/Xndm-S/redsocks2-static/releases/download/1.0/redsocks2_armv7"
REDSOCKS2_URL_X86_64="https://github.com/Xndm-S/redsocks2-static/releases/download/1.0/redsocks2_x86_64"

for arch in $ARCHS; do
  mkdir -p "$BASE_DIR/bin/$arch"

  case $arch in
    "arm64-v8a")
      TPROXY_URL="https://github.com/heiher/hev-socks5-tproxy/releases/download/$TPROXY_TAG/hev-socks5-tproxy-linux-arm64"
      IPT2SOCKS_URL="https://github.com/zfl9/ipt2socks/releases/download/$IPT2SOCKS_TAG/ipt2socks%40aarch64-linux-musl%40generic%2Bv8a"
      DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_TAG/dnsproxy-linux-arm64-$DNSPROXY_TAG.tar.gz"
      REDSOCKS2_URL=$REDSOCKS2_URL_ARM64
      ;;
    "armeabi-v7a")
      TPROXY_URL="https://github.com/heiher/hev-socks5-tproxy/releases/download/$TPROXY_TAG/hev-socks5-tproxy-linux-arm32v7"
      IPT2SOCKS_URL="https://github.com/zfl9/ipt2socks/releases/download/$IPT2SOCKS_TAG/ipt2socks%40arm-linux-musleabi%40generic%2Bv7a"
      DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_TAG/dnsproxy-linux-arm7-$DNSPROXY_TAG.tar.gz"
      REDSOCKS2_URL=$REDSOCKS2_URL_ARMV7
      ;;
    "x86_64")
      TPROXY_URL="https://github.com/heiher/hev-socks5-tproxy/releases/download/$TPROXY_TAG/hev-socks5-tproxy-linux-x86_64"
      IPT2SOCKS_URL="https://github.com/zfl9/ipt2socks/releases/download/$IPT2SOCKS_TAG/ipt2socks%40x86_64-linux-musl%40x86_64"
      DNSPROXY_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_TAG/dnsproxy-linux-amd64-$DNSPROXY_TAG.tar.gz"
      REDSOCKS2_URL=$REDSOCKS2_URL_X86_64
      ;;
  esac

  download_file "$TPROXY_URL" "$BASE_DIR/bin/$arch/hev-socks5-tproxy"
  chmod +x "$BASE_DIR/bin/$arch/hev-socks5-tproxy"

  download_file "$IPT2SOCKS_URL" "$BASE_DIR/bin/$arch/ipt2socks"
  chmod +x "$BASE_DIR/bin/$arch/ipt2socks"

  download_file "$DNSPROXY_URL" "$BASE_DIR/bin/$arch/dnsproxy.tar.gz"
  # Extract and find the dnsproxy binary regardless of folder structure
  mkdir -p "$BASE_DIR/bin/$arch/dnsproxy_tmp"
  tar -xzf "$BASE_DIR/bin/$arch/dnsproxy.tar.gz" -C "$BASE_DIR/bin/$arch/dnsproxy_tmp"
  find "$BASE_DIR/bin/$arch/dnsproxy_tmp" -type f -name "dnsproxy" -exec mv {} "$BASE_DIR/bin/$arch/dnsproxy" \;
  rm -rf "$BASE_DIR/bin/$arch/dnsproxy_tmp" "$BASE_DIR/bin/$arch/dnsproxy.tar.gz"
  chmod +x "$BASE_DIR/bin/$arch/dnsproxy"

  download_file "$REDSOCKS2_URL" "$BASE_DIR/bin/$arch/redsocks2" || true
  if [ -f "$BASE_DIR/bin/$arch/redsocks2" ]; then
    chmod +x "$BASE_DIR/bin/$arch/redsocks2"
  fi
done

echo "Binaries downloaded successfully."
