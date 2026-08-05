#!/usr/bin/env bash
# Compiles LÖVE for aarch64 and fuses game.love into a self-contained
# AppImage. Runs INSIDE the Debian bullseye container from Dockerfile --
# scripts/build_linux_arm64.sh is the entry point on the host.
#
# Mounts the host provides:
#   /cache  pinned downloads + the compiled LÖVE prefix (persists between runs)
#   /in     read-only inputs: game.love, icon.png
#   /out    the finished AppImage lands here
#
# Environment:
#   LOVE_VERSION, APP_NAME, VERSION   passed through from the host script
#   JOBS                              make -j (defaults to nproc)

set -euo pipefail

LOVE_VERSION="${LOVE_VERSION:?}"
APP_NAME="${APP_NAME:?}"
VERSION="${VERSION:?}"
JOBS="${JOBS:-$(nproc)}"

CACHE="/cache"
IN="/in"
OUT="/out"
WORK="/tmp/build"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$WORK"

# ------------------------------------------------------------ compile LÖVE
# The prefix is cached because this is the only slow step (~3 min on a Pi 5,
# and it is identical for every game version). Keyed by LÖVE version so a
# LOVE_VERSION bump cannot silently reuse the old build.
PREFIX="$CACHE/love-$LOVE_VERSION-prefix"
if [ -x "$PREFIX/bin/love" ] && [ -f "$PREFIX/lib/liblove-$LOVE_VERSION.so" ]; then
  say "reusing cached LÖVE $LOVE_VERSION aarch64 build"
else
  say "compiling LÖVE $LOVE_VERSION for aarch64 (jobs: $JOBS)"
  rm -rf "$PREFIX" "$WORK/love-src"
  mkdir -p "$WORK/love-src"
  tar -xzf "$CACHE/love-$LOVE_VERSION-linux-src.tar.gz" \
    -C "$WORK/love-src" --strip-components=1
  (
    cd "$WORK/love-src"
    # No --disable-* flags on purpose: configure silently drops a love module
    # when its -dev package is absent, so the Dockerfile pins the full set and
    # the assertions below prove each one actually linked.
    ./configure --prefix="$PREFIX" --disable-static >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
    # Keep LÖVE's license inside the cached prefix: the unpacked source tree
    # is thrown away, so a later cache-hit run would otherwise have nothing
    # to ship and the AppImage would go out without its engine license.
    cp license.txt "$PREFIX/license.txt"
  )
fi

love_bin="$PREFIX/bin/love"
love_lib="$PREFIX/lib/liblove-$LOVE_VERSION.so"
[ -x "$love_bin" ] || fail "LÖVE build produced no bin/love"
[ -f "$love_lib" ] || fail "LÖVE build produced no lib/liblove-$LOVE_VERSION.so"
file "$love_bin" | grep -q 'ARM aarch64' \
  || fail "built love is not an aarch64 ELF (got: $(file -b "$love_bin"))"

# A configure run that lost an optional dependency still exits 0 and still
# builds -- the loss only shows up as a missing love module at runtime, i.e.
# in a shipped artifact. Assert the decoder/font/video libs really linked.
for soname in libSDL2-2.0.so.0 libopenal.so.1 libfreetype.so.6 \
              libmodplug.so.1 libmpg123.so.0 libvorbisfile.so.3 \
              libtheoradec.so.1 libluajit-5.1.so.2; do
  objdump -p "$love_lib" | grep -q "NEEDED.*$soname" \
    || fail "liblove is not linked against $soname (a -dev package went missing)"
done

# --------------------------------------------------------------- AppDir
# Layout mirrors LÖVE's own x86_64 AppImage exactly (bin/ lib/ share/ at the
# AppDir root, not usr/-prefixed), so the AppRun contract below -- and the
# FUSE_PATH fusion scripts/build.sh performs on the x86_64 image -- stay the
# same idea on both architectures.
APPDIR="$WORK/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/bin" "$APPDIR/lib" "$APPDIR/share"

cp "$love_bin" "$APPDIR/bin/love"
chmod +x "$APPDIR/bin/love"

# ------------------------------------------------------ bundle dependencies
# Walk the DT_NEEDED graph from love + liblove, copying in everything that is
# not host-provided. Recursion stops at excluded libraries, so the driver and
# session subtrees behind SDL2 are never pulled in.
#
# Three reasons a library MUST come from the host, and every entry below is
# one of them:
#
#  1. Driver/session coupled. A bundled libGL would bypass Mesa's V3D driver
#     on the Pi; a bundled libpulse/libdbus would fight the user's running
#     session. GL/EGL/gbm/drm, X11/xcb/wayland/xkbcommon, dbus, pulse, alsa,
#     systemd/udev.
#
#  2. Loader coupled. glibc's pieces cannot be mixed with the host's ld.so at
#     all, and libstdc++/libgcc_s must be at least as new as the compiler --
#     bullseye's gcc 10 is older than any supported host's, so the host copy
#     always satisfies us.
#
#  3. Shared with the host's font stack -- the subtle one, and the reason
#     this list is longer than LÖVE's own AppImage manifest. Bullseye's
#     libtheoradec is (bizarrely, a Debian packaging artifact) linked against
#     libcairo, so the HOST's cairo gets loaded into our process. Because the
#     dynamic loader resolves one SONAME once per process, that host cairo
#     then binds to whatever libfreetype.so.6 we bundled -- and a bullseye
#     freetype 2.10.4 has no FT_Get_Transform, which cairo 1.18 needs:
#
#       love -> liblove -> libtheoradec -> libcairo (host, new)
#                                             `-> FT_Get_Transform -> libfreetype (ours, old)  BOOM
#
#     Bundling a newer freetype only moves the arms race. Excluding the whole
#     font/compression stack instead makes it self-consistent: cairo,
#     fontconfig and freetype all come from one host and agree with each
#     other, while liblove -- compiled against 2.10.4 -- only ever asks for
#     symbols every supported host already has.
EXCLUDE_RE='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libresolv\.so\.2|libutil\.so\.1|libanl\.so\.1|libnsl\.so\.[0-9]+|libstdc\+\+\.so\.6|libgcc_s\.so\.1|lib(GL|GLX|GLdispatch|OpenGL|EGL|GLESv[12]|glapi|gbm|drm)\..*|libX[a-z0-9]*\..*|libxcb.*|libwayland-.*|libxkbcommon.*|libdbus-1\..*|libpulse.*|libasound\..*|libsndfile\..*|libFLAC\..*|libopus\..*|libsystemd\..*|libudev\..*|libselinux\..*|libcap\..*|libgcrypt\..*|libgpg-error\..*|liblzma\..*|libzstd\..*|liblz4\..*|libffi\..*|libexpat\..*|libbsd\..*|libmd\..*|libuuid\..*|libg(lib|object|module|thread)-2\..*|libfontconfig\..*|libfreetype\..*|libpng[0-9]*\..*|libbrotli.*|libz\.so\..*|libwrap\..*|libasyncns\..*|libtirpc\..*|lib(gssapi_krb5|krb5|k5crypto|com_err|krb5support|keyutils)\..*|libpcre.*)$'

# soname -> absolute path, harvested from the full ldd closure of both roots.
declare -A RESOLVED=()
while read -r soname _arrow path _addr; do
  [ -n "${path:-}" ] || continue
  [ -e "$path" ] || continue
  RESOLVED["$soname"]="$path"
done < <(ldd "$love_bin" "$love_lib" | awk '/=>/ {print $1, $2, $3, $4}')

declare -A BUNDLED=()
bundle_needed() { # $1 = ELF whose DT_NEEDED entries to walk
  local soname target
  while read -r soname; do
    [ -n "$soname" ] || continue
    if [[ "$soname" =~ $EXCLUDE_RE ]]; then continue; fi
    if [ -n "${BUNDLED[$soname]:-}" ]; then continue; fi
    target="${RESOLVED[$soname]:-}"
    [ -n "$target" ] || fail "cannot resolve $soname (needed by $(basename "$1"))"
    # Copy dereferenced and under the soname: the AppDir must not depend on
    # the builder's libSDL2-2.0.so.0 -> libSDL2-2.0.so.0.14.0 symlink chain.
    cp -L "$target" "$APPDIR/lib/$soname"
    chmod 0644 "$APPDIR/lib/$soname"
    BUNDLED["$soname"]=1
    bundle_needed "$APPDIR/lib/$soname"
  done < <(objdump -p "$1" | awk '/NEEDED/ {print $2}')
}

say "bundling shared libraries"
cp "$love_lib" "$APPDIR/lib/liblove-$LOVE_VERSION.so"
chmod 0644 "$APPDIR/lib/liblove-$LOVE_VERSION.so"
BUNDLED["liblove-$LOVE_VERSION.so"]=1
bundle_needed "$APPDIR/bin/love"
bundle_needed "$APPDIR/lib/liblove-$LOVE_VERSION.so"
say "bundled $(ls "$APPDIR/lib" | wc -l) libraries: $(ls "$APPDIR/lib" | tr '\n' ' ')"

# LÖVE loads jit.* (jit.status, the profiler) through LUA_PATH; without these
# the modules are simply absent, so ship them the way upstream's image does.
jit_share="$(ls -d /usr/share/luajit-* 2>/dev/null | head -1)"
[ -n "$jit_share" ] || fail "luajit jit/*.lua modules not found under /usr/share"
LUAJIT_SHARE_DIR="$(basename "$jit_share")"
mkdir -p "$APPDIR/share/$LUAJIT_SHARE_DIR" "$APPDIR/share/lua/5.1" "$APPDIR/lib/lua/5.1"
cp -R "$jit_share/jit" "$APPDIR/share/$LUAJIT_SHARE_DIR/"

# --------------------------------------------------------------- branding
cp "$IN/game.love" "$APPDIR/game.love"
# The .desktop's Icon= resolves against the AppDir root by basename, and
# .DirIcon is what appimaged and file-manager thumbnailers read.
cp "$IN/icon.png" "$APPDIR/$APP_NAME.png"
cp "$IN/icon.png" "$APPDIR/.DirIcon"

cat > "$APPDIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=gen1recomp
Comment=Pokémon Gen 1 recompilation
Exec=$APP_NAME
Icon=$APP_NAME
Categories=Game;
Terminal=false
EOF

# AppRun follows LÖVE's own, with FUSE_PATH committed to instead of shipped
# commented out: this image is a game, not the engine, so it must never fall
# through to LÖVE's "no game" screen.
cat > "$APPDIR/AppRun" <<EOF
#!/bin/sh
# gen1recomp aarch64 AppImage launcher.

if [ -z "\$APPDIR" ]; then
    APPDIR="\$(dirname "\$(readlink -f "\$0")")"
fi

export LD_LIBRARY_PATH="\$APPDIR/lib/:\$LD_LIBRARY_PATH"

if [ -z "\$XDG_DATA_DIRS" ]; then
    XDG_DATA_DIRS="/usr/local/share/:/usr/share/"
fi
export XDG_DATA_DIRS="\$APPDIR/share/:\$XDG_DATA_DIRS"

if [ -z "\$LUA_PATH" ]; then
    LUA_PATH=";"
fi
export LUA_PATH="\$APPDIR/share/$LUAJIT_SHARE_DIR/?.lua;\$APPDIR/share/lua/5.1/?.lua;\$LUA_PATH"

if [ -z "\$LUA_CPATH" ]; then
    LUA_CPATH=";"
fi
export LUA_CPATH="\$APPDIR/lib/lua/5.1/?.so;\$LUA_CPATH"

exec "\$APPDIR/bin/love" --fused "\$APPDIR/game.love" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

[ -f "$PREFIX/license.txt" ] || fail "LÖVE license.txt missing from the build prefix"
cp "$PREFIX/license.txt" "$APPDIR/license.love2d.txt"

# --------------------------------------------------------------- fuse image
# An AppImage is just <runtime ELF><squashfs>. gzip at 128K blocks matches what
# LÖVE's official image uses and what every type-2 runtime can read; zstd would
# be smaller but is not universally supported by older runtimes users may have
# registered through appimaged.
say "packing squashfs"
sfs="$WORK/payload.squashfs"
rm -f "$sfs"
mksquashfs "$APPDIR" "$sfs" \
  -comp gzip -b 131072 -noappend -all-root -no-xattrs -quiet >/dev/null

out="$OUT/$APP_NAME-$VERSION-linux-arm64.AppImage"
rm -f "$out"
cat "$CACHE/runtime-aarch64" "$sfs" > "$out"
chmod +x "$out"

say "AppImage: $(basename "$out") ($(du -h "$out" | cut -f1))"
