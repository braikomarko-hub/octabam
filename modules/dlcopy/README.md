# `dlcopy` -- DLCOPY

The DSP half of the demand loader (design, measurements and open items:
[`docs/proposals/DEMAND_LOAD.md`](../../docs/proposals/DEMAND_LOAD.md)).

`dlcopy.asm` is a hook on payload B at `P:0x76` (the frame head, after the host handlers'
address masks are set), placed in the shared window. When the doorbell at `X:0x2900` is `0xa55a`
it clears the effect's BOUND word, copies the staged block to the window summing the code words,
and publishes it (init, proc, span, BOUND last) only if the sum matches the one staged after the
code; it clears the doorbell either way. A message with N = 0 clears BOUND
and the span only. The window is one memory, so the copy is resident for core A's tracks.

The build also assembles two templates in this directory from `Remix.window_demand` and
`Remix.window_guard`: `dlstub.asm` (the stub every demand effect's id dispatches to: dry until
BOUND, then the real init once per instance and the real proc) and `dlwrap.asm` (the guard every
stock buffered reverb dispatches to: it runs the stock code only while its buffer misses every
loaded span, and resumes when the range is clear again).

Claims: `X:0x2900..0x3d55` (staging), `X:0x3f00..0x3f4f` (stub tables), `X:0x3f50..0x3fea` (guard tables, the copier's saved `b`). Gates: `verify_dlstub`, `verify_dlwrap` (`dsp_host`). Not run on a unit.
