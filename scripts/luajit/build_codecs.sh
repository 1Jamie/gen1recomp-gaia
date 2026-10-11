#!/usr/bin/env bash
# Build libogg, libvorbis/libvorbisfile, libtheoradec and libmpg123 for the
# aarch64 PortMaster zips inside the same debian:bullseye container as LuaJIT.
#
# Usage: scripts/luajit/build_codecs.sh
# Prints the output directory on stdout; progress goes to stderr.
# Output: .bazinga/cache/codecs/<recipe hash>-<image digest>/{lib*.so.*,licenses/}
#
# Must run on an aarch64 host with docker or podman.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../linux-arm64/common.sh
. "$ROOT/scripts/linux-arm64/common.sh"
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }

CODEC_LIBS="libogg.so.0 libvorbis.so.0 libvorbisfile.so.3 libtheoradec.so.1 libmpg123.so.0"

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail "codecs must be built on an aarch64 host (got $(uname -m)); or pass GEN1RECOMP_CODEC_DIR to the zip scripts" ;;
esac

CACHE="$ROOT/.bazinga/cache/codecs"
hash_stdin() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-12; }
RECIPE_HASH="$(printf '%s %s %s %s %s' "$(sha256_file "$HERE/compile_codecs.sh")" \
  "$OGG_SHA256" "$VORBIS_SHA256" "$THEORA_SHA256" "$MPG123_SHA256" | hash_stdin)"
IMAGE_DIGEST="${LUAJIT_BUILD_IMAGE##*sha256:}"
OUT_DIR="$CACHE/$RECIPE_HASH-${IMAGE_DIGEST:0:12}"

complete() {
  local soname
  for soname in $CODEC_LIBS; do [ -s "$OUT_DIR/$soname" ] || return 1; done
  [ -s "$OUT_DIR/licenses/codecs-SOURCE.txt" ]
}

if complete; then
  say "codecs already built"
  echo "$OUT_DIR"
  exit 0
fi

mkdir -p "$CACHE/src"
download_pinned "$OGG_URL" "$CACHE/src/$OGG_TARBALL" "$OGG_SHA256" >&2
download_pinned "$VORBIS_URL" "$CACHE/src/$VORBIS_TARBALL" "$VORBIS_SHA256" >&2
download_pinned "$THEORA_URL" "$CACHE/src/$THEORA_TARBALL" "$THEORA_SHA256" >&2
download_pinned "$MPG123_URL" "$CACHE/src/$MPG123_TARBALL" "$MPG123_SHA256" >&2

RT="$(container_runtime)" \
  || fail "docker or podman is required to build the codecs (or set GEN1RECOMP_CODEC_DIR for the zip scripts)"

STAGE="$(mktemp -d "$CACHE/stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/out"

say "building codecs in $RT ($LUAJIT_BUILD_IMAGE, arm64)"
"$RT" run --rm --platform linux/arm64 \
  -e OGG_TARBALL="$OGG_TARBALL" -e VORBIS_TARBALL="$VORBIS_TARBALL" \
  -e THEORA_TARBALL="$THEORA_TARBALL" -e MPG123_TARBALL="$MPG123_TARBALL" \
  -e CODEC_MAX_GLIBC="$LUAJIT_MAX_GLIBC" \
  -e LUAJIT_APT_SOURCES="$LUAJIT_APT_SOURCES" \
  -v "$HERE:/luajit-scripts:ro" \
  -v "$CACHE/src:/in:ro" \
  -v "$STAGE/out:/out" \
  "$LUAJIT_BUILD_IMAGE" bash -euo pipefail -c '
    printf "%s\n" "$LUAJIT_APT_SOURCES" > /etc/apt/sources.list
    rm -f /etc/apt/sources.list.d/*
    printf "Acquire::Check-Valid-Until \"false\";\nAcquire::Retries \"5\";\nAcquire::http::Pipeline-Depth \"0\";\nAcquire::http::No-Cache \"true\";\n" > /etc/apt/apt.conf.d/99builder
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      build-essential binutils pkg-config autotools-dev bzip2 ca-certificates >/dev/null
    bash /luajit-scripts/compile_codecs.sh /in /out
  ' >&2 || fail "codec container build failed"

for soname in $CODEC_LIBS; do
  [ -s "$STAGE/out/$soname" ] || fail "container produced no $soname"
done
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/licenses"
mv "$STAGE/out/licenses" "$OUT_DIR/licenses"
printf '%s\n' "ogg $OGG_VERSION $OGG_URL" "vorbis $VORBIS_VERSION $VORBIS_URL" \
  "theora $THEORA_VERSION $THEORA_URL" "mpg123 $MPG123_VERSION $MPG123_URL" \
  "built in $LUAJIT_BUILD_IMAGE" > "$OUT_DIR/licenses/codecs-SOURCE.txt"
for soname in $CODEC_LIBS; do mv -f "$STAGE/out/$soname" "$OUT_DIR/$soname"; done
say "built codecs in $OUT_DIR"
echo "$OUT_DIR"
