### Measuring frame time

Press `F3` in a running game to toggle a small frame-time overlay (FPS,
per-section update/draw/present timings, Lua heap, draw calls, texture
memory). It is off by default and costs nothing when hidden. Set
`POKEPORT_GAME_PROF_OVERLAY=1` to start with it shown. For a headless
measurement set `POKEPORT_GAME_PROF=<frames>`: after a 60-frame warmup and
`<frames>` recorded frames it prints a `PROF ...` summary to stderr and quits.
`POKEPORT_GAME_PROF=all` records until the game quits and then prints the
summary, which also lists the worst spikes (over 16.7 ms) with the
per-section cost and the screen/map they happened on. The `frame` figure and
the spike threshold are work time: the vsync wait in or just before `present`
(up to one display refresh) is excluded, so an idle frame reads well under a millisecond
while a GPU stall in `present` still counts. The launcher is never profiled.

`POKEPORT_JIT=0` turns the LuaJIT compiler off (prints `[info] jit off`), to
approximate low-power devices that run Lua without it. It affects only the
main Lua state; worker threads (music/SFX and the atlas/decode worker) keep
their JIT.