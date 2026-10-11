#!/usr/bin/env bash
# Compile the audio/video codec libraries liblove-11.5.so links but the
# PortMaster runtime does not ship. Runs INSIDE the debian:bullseye container.
#
# Usage: compile_codecs.sh <tarball dir> <out dir>
# Env:   OGG_TARBALL VORBIS_TARBALL THEORA_TARBALL MPG123_TARBALL  (required)
#        CODEC_MAX_GLIBC  highest GLIBC_x.y symbol allowed (required)

set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || fail "usage: compile_codecs.sh <tarball dir> <out dir>"
IN="$1"
OUT="$2"
: "${OGG_TARBALL:?}" "${VORBIS_TARBALL:?}" "${THEORA_TARBALL:?}" "${MPG123_TARBALL:?}"
: "${CODEC_MAX_GLIBC:?}"

PREFIX=/usr/local
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
mkdir -p "$OUT/licenses"

build() { # $1 = label  $2 = tarball  $3.. = configure args
  local label="$1" tarball="$2"; shift 2
  local src="$WORK/$label"
  mkdir -p "$src"
  case "$tarball" in
    *.tar.bz2) tar -xjf "$IN/$tarball" -C "$src" --strip-components=1 ;;
    *)         tar -xzf "$IN/$tarball" -C "$src" --strip-components=1 ;;
  esac
  (
    cd "$src"
    for helper in config.guess config.sub; do
      [ -f "$helper" ] && cp "/usr/share/misc/$helper" .
    done
    ./configure --prefix="$PREFIX" --disable-static "$@" >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null
  )
  cp "$src/COPYING" "$OUT/licenses/$label-COPYING"
  ldconfig
}

build ogg "$OGG_TARBALL"
build vorbis "$VORBIS_TARBALL"
build theora "$THEORA_TARBALL" --disable-examples --disable-spec --disable-doc
build mpg123 "$MPG123_TARBALL" --disable-modules --with-audio=dummy --disable-lfs-alias

LIBS="libogg.so.0 libvorbis.so.0 libvorbisfile.so.3 libtheoradec.so.1 libmpg123.so.0"
for soname in $LIBS; do
  lib="$PREFIX/lib/$soname"
  [ -f "$lib" ] || fail "build produced no $soname"
  cp -L "$lib" "$OUT/$soname"
  strip --strip-unneeded "$OUT/$soname"
  dyn="$(readelf -d "$OUT/$soname")"
  got="$(sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p' <<<"$dyn")"
  [ "$got" = "$soname" ] || fail "$soname has SONAME '$got'"
  if grep -Eq 'RPATH|RUNPATH' <<<"$dyn"; then
    fail "$soname carries a build-time RPATH/RUNPATH"
  fi
  sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' <<<"$dyn" | while read -r needed; do
    case " libc.so.6 libm.so.6 ld-linux-aarch64.so.1 $LIBS " in
      *" $needed "*) ;;
      *) fail "$soname needs $needed, which is neither glibc nor a bundled codec" ;;
    esac
  done
  max="$(objdump -T "$OUT/$soname" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -t. -k1,1n -k2,2n | tail -1)"
  if [ -n "$max" ] && [ "$(printf '%s\n%s\n' "$max" "$CODEC_MAX_GLIBC" | sort -t. -k1,1n -k2,2n | tail -1)" != "$CODEC_MAX_GLIBC" ]; then
    fail "$soname needs GLIBC_$max, newer than $CODEC_MAX_GLIBC"
  fi
done

objdump -T "$OUT/libmpg123.so.0" | grep -q mpg123_info2 \
  || fail "libmpg123 lacks mpg123_info2; a host libsndfile would fail to relocate against it"
echo "codecs ok: $LIBS" >&2
