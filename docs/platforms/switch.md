# Nintendo Switch

Releases ship an SD-ready `gen1recomp-*-switch.zip`. Runtime target is pinned
[love-nx](https://github.com/retronx-team/love-nx) `11.5-nx1`. Requires a
console that can run Switch homebrew.

- Players: [switch-install.md](../switch-install.md). Download the zip,
  extract at the microSD root (install or update), title-override launch,
  import your own legal ROM, Joy-Con controls and shortcuts.
- Builders: [switch-build.md](../switch-build.md). `--fetch` / `--loose` /
  `--fused`, toolchain, Docker fallback, and CI vs release (path-gated ubuntu
  selftest, fused PR artifact on the main repo, release hard-fail).
- File transfer (MTP / SD / FTP): [switch-transfer.md](../switch-transfer.md).
