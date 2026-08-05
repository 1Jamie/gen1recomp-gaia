# Build environment for the aarch64 Linux AppImage.
#
# Debian bullseye on purpose: it ships glibc 2.31, the oldest runtime we
# promise to support. Everything linked here therefore runs on bullseye and
# every later distro (glibc is backward compatible, not forward), which is
# what makes the resulting AppImage portable across Raspberry Pi OS, Armbian,
# Ubuntu 20.04+, and the aarch64 handheld distros.
#
# This image is arch-native: build it on an aarch64 host (Raspberry Pi 5,
# ubuntu-24.04-arm runner, Apple Silicon Docker) — no qemu emulation.
FROM debian:bullseye

ENV DEBIAN_FRONTEND=noninteractive

# build-essential/autoconf: LÖVE 11.5's linux-src tarball is autotools.
# squashfs-tools: packs the AppDir into the AppImage payload.
# The lib*-dev set is LÖVE's full optional-module surface — a missing one
# does not fail configure, it silently drops a module (love.sound decoders,
# love.font, love.video), so they are pinned here deliberately.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config autoconf automake libtool \
      ca-certificates curl file xz-utils zip unzip squashfs-tools \
      libsdl2-dev libopenal-dev libogg-dev libvorbis-dev libtheora-dev \
      libmodplug-dev libmpg123-dev libfreetype6-dev libluajit-5.1-dev \
      zlib1g-dev libgl1-mesa-dev libgles2-mesa-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
