#!/usr/bin/env bash
# Shared helpers and pins for the aarch64 Linux AppImage build.
# Source from other scripts:  . "$(dirname "$0")/common.sh"

# shellcheck disable=SC2034
if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export ROOT

# ---------------------------------------------------------------- pins
# LÖVE ships no aarch64 binary of any kind -- the 11.5 release has win32/win64,
# macOS, Android, iOS and an x86_64 AppImage, and that is the whole list. So
# this port compiles the official linux-src tarball instead of unpacking a
# prebuilt image the way scripts/build.sh does for x86_64.
LOVE_VERSION="11.5"
LOVE_SRC_TARBALL="love-$LOVE_VERSION-linux-src.tar.gz"
LOVE_SRC_URL="https://github.com/love2d/love/releases/download/$LOVE_VERSION/$LOVE_SRC_TARBALL"
LOVE_SRC_SHA256="066e0843f71aa9fd28b8eaf27d41abb74bfaef7556153ac2e3cf08eafc874c39"

# AppImage type-2 runtime: the ~900 KB static-pie ELF that gets prepended to
# the squashfs payload. Pinned to a dated tag, never "continuous", so a
# rebuild months from now produces the same bytes.
APPIMAGE_RUNTIME_TAG="20251108"
APPIMAGE_RUNTIME_NAME="runtime-aarch64"
APPIMAGE_RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/$APPIMAGE_RUNTIME_TAG/$APPIMAGE_RUNTIME_NAME"
APPIMAGE_RUNTIME_SHA256="00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444"

# Debian bullseye (glibc 2.31) is the compile environment, NOT a statement
# about where the artifact runs. glibc is backward compatible but not forward
# compatible, so linking against the oldest glibc we support is what lets one
# AppImage cover Raspberry Pi OS bullseye/bookworm/trixie, Ubuntu 20.04+ and
# the aarch64 handheld distros. Building on a newer base would silently
# restrict the artifact to that base and newer.
BUILDER_BASE_IMAGE="debian:bullseye"
BUILDER_IMAGE="${GEN1_LINUX_ARM64_IMAGE:-gen1recomp-linux-arm64-builder}"

APP_NAME="gen1recomp"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Print SHA-256 hex digest of PATH. Prefers sha256sum, falls back to shasum
# (same order-agnostic pair scripts/switch/common.sh uses).
sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "need sha256sum or shasum (install coreutils)"
  fi
}

# download_pinned URL DEST EXPECTED_SHA256
#
# A cache hit is only trusted if it still hashes to the pin: a download
# truncated by a network drop would otherwise be reused forever, which is the
# same trap scripts/build.sh guards for the win64 zip and the x86_64 AppImage.
download_pinned() {
  local url="$1" dest="$2" want="$3" got=""
  if [ -f "$dest" ]; then
    got="$(sha256_file "$dest")"
    if [ "$got" = "$want" ]; then
      return 0
    fi
    warn "cached $(basename "$dest") has the wrong digest, re-downloading"
    rm -f "$dest"
  fi
  say "downloading $(basename "$dest")"
  curl -fL --progress-bar "$url" -o "$dest.tmp" || fail "download failed: $url"
  got="$(sha256_file "$dest.tmp")"
  [ "$got" = "$want" ] || fail "$(printf '%s\n  expected %s\n  got      %s' \
    "checksum mismatch for $(basename "$dest")" "$want" "$got")"
  mv "$dest.tmp" "$dest"
}

# Echo the container runtime to use: docker, else podman.
container_runtime() {
  if [ -n "${GEN1_CONTAINER_RUNTIME:-}" ]; then
    printf '%s' "$GEN1_CONTAINER_RUNTIME"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf 'docker'
  elif command -v podman >/dev/null 2>&1; then
    printf 'podman'
  else
    return 1
  fi
}

fail_need_container() {
  fail "$(cat <<'EOF'
the aarch64 AppImage is compiled inside a Debian bullseye container and needs
docker or podman on an aarch64 host.

  Raspberry Pi OS / Debian / Ubuntu:  sudo apt install docker.io && sudo usermod -aG docker "$USER"
  Fedora / Asahi:                     sudo dnf install podman
  macOS (Apple Silicon):              brew install --cask docker

Override the runtime with GEN1_CONTAINER_RUNTIME=podman.
See docs/linux-arm64-build.md.
EOF
)"
}
