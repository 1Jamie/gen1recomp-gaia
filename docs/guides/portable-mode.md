# Portable mode

By default the game keeps your save, options, and the private ROM-derived
data cache in your OS's normal per-user app data folder. Portable mode keeps
everything next to the game instead, which is handy for a USB stick or
portable drive you carry between computers.

To turn it on, drop an empty file named `portable.txt` next to the app (next
to `gen1recomp.app`/`.exe`, or next to `main.lua`/`conf.lua` when running from
source), then launch the game. Portable mode is desktop-only (Windows, Linux,
macOS); it has no effect on Android or iOS, where the app runs from a
read-only package.

With `portable.txt` present:

- `save.lua`, `save.lua.bak`, and `options.lua` are read from and written to
  that same folder instead of the OS save directory.
- A ROM import writes the generated `data/generated` and `assets/generated`
  cache straight into that folder too (nothing is left in the OS save
  directory), so a later launch reuses it without asking for the ROM again
  even on a different computer, as long as the same folder comes along.
- The kept-ROM copy (`roms/`), import inboxes (`imports/`), `baseroms/`,
  `shaders/`, `prints/`, touch skins, and the shader error log also live in
  that folder. The auto-update payload cache (`updates/`) stays in the OS save
  directory on purpose, as does the temporary shader download archive.
- If `portable.txt` is present but rejected (folder not writable, or the
  folder cannot be mounted), the launcher log says why and cache writes fail
  with a message instead of silently landing in the OS save directory.
- Deleting `portable.txt` switches back to the normal OS save directory;
  nothing already written to either location is touched automatically, so
  copy files over yourself if you want to carry existing progress across the
  switch.
