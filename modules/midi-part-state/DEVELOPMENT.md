# midi-part-state implementation and verification

Shared native Part access and coherent publication, introduced with MIDI
Loopback as its first consumer. It adds no panel control and needs no KITS.

Working native Parts are authoritative. UI writes use the selected working
Part; playback reads each track's playing context. Writes update native
working bytes, the current-bank CS1 mirror and native dirty bits. Native
Save/Reload and project storage carry those bytes without a companion file.

SETUP offset 12 is a shared flags byte. Loopback owns bits 2–3 for DEST
(EXT/INT/BOTH); value 3 and invalid flags read as EXT. Bits 0–1 are preserved
for future consumers. The native range is 0..15, declared by this module,
and fresh Parts initialize it to zero. Stock 1.40C cold project load clamps
this flags byte to zero in RAM. Native SAVE PROJECT writes the current
bank's normalized flags, so that saved bank returns to Loopback with EXT.
Other bank files are not rewritten merely by loading. Use EXT and save before returning to
stock, or retain a separate backup to preserve routing choices.

`verify_midi_part_stock.py --project DIR` boots candidate, stock 1.40C and
candidate again on a disposable virtual card. It checks all 256 input bytes,
16 banks, four working plus four saved Parts and eight tracks against loaded RAM and saved
work/strd fields, including unchanged other-bank fields and explicit INT/BOTH
flags in the bank written by SAVE PROJECT. The candidate clamps
at 15; stock clamps at zero. The receipt is
`out/midi-loopback-stock/receipt.json`. This is a cold disk-load/native-save
check, not retained-memory or hardware acceptance.

Cold ROM entry gates retain native copy/initialization before the platform
runtime loads. A native post-loader call then activates the DRAM targets.
While a native copy or initialization replaces working Parts, explicit-context
readers see a complete outgoing snapshot of all four MIDI SETUP arrays.
Snapshot preparation and native copying keep interrupts enabled; final
publication uses a short interrupt mask without callbacks or native copying.
Nested operations retain the outer snapshot. Native arguments and register
returns are preserved. Condition codes are outside the C calling contract.

Direct readers of native memory do not use the snapshot. New clients must
use the explicit-context API. A replaced Part advances its runtime epoch;
ordinary setting edits do not. Runtime note ownership remains the consumer's
responsibility. Bulk operations crossing bank boundaries and live cross-project
transitions require separate qualification.

The adapter declares `mp_snapshot` and `mp_part_epochs` as zero-initialized
`Linked.boot_mutable` data. The shared boot gate validates their owning linked
unit, bounds and initial bytes; it has no Part-specific exceptions.
`verify_midi_part_copy.py` checks the entire outgoing snapshot and all 64 epochs
against each operation's inputs, including unchanged epochs while copying is
interrupted, and rejects a wrapper with epoch publication disabled.

`verify_midi_part.py` checks distinct UI/playback contexts, bounded writes and
mirrors. `verify_midi_part_copy.py` compares native copy/initialization bytes,
registers and interrupt state, cold entry, guards and interrupted publication.
`verify_midi_part_port.py --project DIR` executes native Save/Reload/Clear/Paste
under the firmware emulator on a disposable virtual card. Loopback's UI test
covers project save/load and retained resume. These are emulator checks;
physical Loopback integration results are scoped in its developer notes.

The source is extracted from integration `8f8e00d061d17a890a3b01d5f340492f912712e2`.
Future Harmony/SRAM conditionals remain dormant source; the Follow/Harmony
NOTE SETUP staging hook is omitted from this standalone contribution.

## Author source

Pinned source: the `modules/midi-loopback/upstream` submodule gitlink.
Review both modules in that narrow author history alongside these adapters.
The cold-entry reference is enforced at build time; the combined cross-unit
runtime reference is enforced by `verify_midi_loopback_reference.py`. A native
source build and the adapter build are compared at the same upstream base.
