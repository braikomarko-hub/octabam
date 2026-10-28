# PARTS

System module: the live Part, for every module that keeps state in one. A Part is
a pattern's recipe card -- each track's machine and settings -- held three times:
the working copy the UI edits, the saved copy, and the current bank's copy in
battery-backed memory. A module that writes its own byte into a Part used to find
it, write it and its mirror, and guess when the card was being swapped, by
itself; two such modules competed for the same native copy and reset sites.
PARTS owns them once (radiohagen's proposal, 28 Oct 2026;
[SHARED_HOOKS.md](../../docs/proposals/SHARED_HOOKS.md) section 5).

The code is radiohagen's MIDI PART STATE, which did this for the MIDI SETUP
arrays, generalized; PARTS retires it. MIDI PART STATE's own API stays under its
names (`mp_*`), unchanged, for the modules that use it, and its gates check it.

## What a client gets

| entry | in | out |
|---|---|---|
| `pt_ui_context` | | the context the UI edits: bank × 4 + Part, or -1 |
| `pt_midi_play_context` | d0 MIDI track | the context it plays (latched, else applied), or -1 |
| `pt_epoch` | d0 context | its replacement count, or -1 |
| `pt_read` | d0 context, d1 Part offset | the byte, or -1 outside every client's window; while the Part is replaced, the outgoing byte |
| `pt_write` | d0 context, d1 Part offset, d2 byte | 1, or 0 for a byte no client declared writable: the working byte, the Part and bank dirty bits, and for the UI's bank the battery-backed mirror, under one short mask |

Every entry keeps every register but d0. `pt_midi_play_context` is radiohagen's
reading of the MIDI engine; no audio-track equivalent is established.

A client registers in `CLIENTS` (manifest.py): its windows (the Part bytes it
reads, which the replacement snapshot covers), its writable bytes, and the
notifications it takes:

- `<prefix>_pt_before` -- d0 the working Part's address, d1 its context: a native
  copy or initialization is about to replace it; the outgoing window is already
  in the snapshot.
- `<prefix>_pt_replaced` -- d0 the context: the new bytes are published.

Both run unmasked, in the native copy's context (a UI or load path), in
registration order; a handler may clobber every register and may not call a
kernel or UI primitive.

## Sites

| site | stock | PARTS |
|---|---|---|
| `0x40020898` | memcpy's entry | resident gate (ROM): stock until activated, then the coherent copy |
| `0x40005638` | Part initialization's entry | resident gate (ROM): stock until activated, then the coherent clear |
| `0x40000512` | the boot's `jsr 0x4000f938` after the platform loader | publishes the runtime's wrappers, then the stock call |

memcpy runs before the platform runtime is loaded, so its gate stays in ROM. Beside
BOOT TRACE, HOOKS owns `0x40000512` and calls BOOT TRACE's note, then PARTS's
activation ([HOOKS](../hooks/README.md), boot). With no client, PARTS installs
nothing. With a client that uses MIDI PART STATE's API, PARTS also carries that
module's shared MIDI flags byte claim and the Part validator's range for it (0..15).

## Measured

- MIDI PART STATE's gates against a PARTS image (`test/midi-loopback`, 28 Oct
  2026): `verify_midi_part` (contexts, 1,536 field writes, mirror and dirty bits),
  `verify_midi_part_copy` (320 cold operations against stock, interrupted copy and
  clear publication, the missing-epoch mutation rejected), `verify_midi_part_boot`;
  and MIDI LOOPBACK's own gates (author reference, producers, settings, context,
  stress). Its RTOS gate with a project was not run.
- `verify_parts`: the generic API, the notifications and the window under Unicorn
  (two synthetic clients), and the installed sites and activation in a built image.
- Not flashed. Not run on a unit with a project.

## Not yet

- Machine registration (the chooser rows, FLEX renderer entry, PLAYBACK resolver,
  Part validator and signature bytes OCTA303, ANALOG BD, CX OSC, SYNTH MACHINE and
  BLACKPYRAMIDS 303 share): SHARED_HOOKS.md phase 6.
- KITS, MIDI SCENES and the machines still address the mirror themselves.
