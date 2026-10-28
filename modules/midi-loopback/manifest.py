"""Pinned author source; reviewed alongside the matching author commit."""
import dataclasses
from pathlib import Path
import runpy
from remix.schema import Gate

SOURCE = Path(__file__).resolve().parent / 'upstream/modules/midi-loopback/manifest.py'
MODULE = runpy.run_path(str(SOURCE), run_name='remix_manifest_midi_loopback')['MODULE']
# The cross-unit author runtime is linked and checked together. Independent
# Linked.reference links cannot resolve its mutual Part State/Loopback symbols.
MODULE = dataclasses.replace(MODULE, linked=tuple(
    dataclasses.replace(unit,
        include=(lambda modules, remix, source=unit.include: source(modules)))
    if unit.include else unit for unit in MODULE.linked
), gates=(
    Gate('tools/verify/verify_midi_loopback_reference.py', stage='image', venv=True),
    *MODULE.gates,
))

# PARTS carries MIDI PART STATE's API (mp_*) unchanged and retires it
# (modules/parts): Loopback's units link against PARTS, and MIDI PART STATE's
# gates, which check that API by its names, run here. The author reference
# above still builds Loopback with the author's own Part State.
MODULE = dataclasses.replace(MODULE, requires=tuple(
    "PARTS" if r == "MIDI PART STATE" else r for r in MODULE.requires), gates=(
    *MODULE.gates,
    Gate('tools/verify/verify_midi_part.py', stage='image', venv=True),
    Gate('tools/verify/verify_midi_part_copy.py', stage='image', venv=True),
    Gate('tools/verify/verify_midi_part_boot.py', stage='image', venv=True),
))

# Detailed verification lives in developer notes, outside the README index.
MODULE = dataclasses.replace(MODULE, proof_note="")
