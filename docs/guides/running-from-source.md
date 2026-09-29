# Running from source

Requires LÖVE 11.x. Place a ROM in the project folder and double-click
`Play-Mac.command` or `Play-Windows.bat`, or run:

```sh
scripts/setup.sh --rom "/path/to/Pokemon Red.gb"
scripts/run.sh
```

then `love .` for later launches.

Windows PowerShell scripts, the optional developer data build, test suites,
and cache management are covered in the
[Developer Setup guide](https://github.com/bryanthaboi/gen1recomp/wiki/Guide-Developer-Setup).
Runtime internals are in [architecture.md](../architecture.md).
