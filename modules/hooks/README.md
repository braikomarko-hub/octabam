# HOOKS

Platform module: the one owner of a stock site that two selected modules both
claim. Nobody selects it; the registry appends it to a remix whenever one of
its bridges has two participants in it, as it appends MEMORY. A remix with one
participant, or none, gets nothing from HOOKS: that module's own claim stands
and its bytes do not move, so a module proven alone on a unit stays exactly what
was proven. The participants' sources are not edited.

The design, and the conflicts it is meant to remove next:
[docs/proposals/SHARED_HOOKS.md](../../docs/proposals/SHARED_HOOKS.md).

## Bridges

| bridge | site | participants | what HOOKS does |
|---|---|---|---|
| track_key | the [TRACK]-held key layer's keys field `0x400d164e` (stock `0x400d1594`, six 26-byte records) | REC_TRIG_MUTE (replaces YES/NO), MORPH (adds UP/DOWN) | points the field at one table: stock's records with each participant's replacements, then each participant's added keys |
| status_icon | the track status icon renderer's state-cache load `0x4004bee2` | REC_TRIG_MUTE (`rtm_glyph`), REC THRESHOLD (`blink_gate`) | one `jsr` calls `rtm_glyph`, then `blink_gate`: the mute fold first, so the blink bit survives it |

A bridge takes each participant's claim at the site by `schema.Override`
(`ledger.py` and `build_bus.py` skip the overridden detour or symbol ref).
REC_TRIG_MUTE's own refs into stock's [TRACK] table are still written when
track_key is bridged; nothing reads that table once the field is repointed.

A selection with a bridged pair and no HOOKS is refused by the ledger, by
name: MORPH's and REC_TRIG_MUTE's claims do not overlap, so without the
rule the pair would build and REC_TRIG_MUTE's keys would silently stop.

## Measured

- `tools/verify/verify_hooks.py`: the selection rules; under Unicorn, the
  three participants' own sources linked with `bridge.s`, `hk_status_icon`
  over 128 states (track, state, mute, arm, TRIG, blink phase) against the
  model and against the two routines called in turn, the opposite order
  losing the blink; the [TRACK]-layer table decoded. With a built image of
  [`test/hooks`](../../remixes/test/hooks/README.md): stock's six records are
  the ones HOOKS copies, and both sites hold HOOKS's writes.
- Not flashed. Not run under the ColdFire port with a project.

## Adding a bridge

A bridge is a participant list in `manifest.py`, a branch of `select()` and
its code in `bridge.s`. Each participant's routine is called as its own
detour would be; the order is the bridge's, and `verify_hooks` should show
why it is that order.
