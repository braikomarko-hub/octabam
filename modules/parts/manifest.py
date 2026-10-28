"""PARTS -- live Part access and coherent replacement, owned once.

A module that keeps state in a Part -- a byte of a track's settings, a
machine's signature, a MIDI routing flag -- needs the same four things, and
each used to do them itself, competing for the same native copy and reset
sites (radiohagen's proposal, 28 Oct 2026; docs/proposals/SHARED_HOOKS.md
section 5):

  * which Part: the one the UI edits (pt_ui_context) and the one a MIDI
    track plays (pt_midi_play_context), as a context = bank * 4 + Part;
  * reading and writing a byte of it (pt_read, pt_write): the working byte,
    the native dirty bits and, for the UI's bank, the battery-backed mirror,
    under one short interrupt mask;
  * consistent reads while a native copy or initialization replaces the
    Part: readers see the whole outgoing window (the snapshot) until the
    new one is published;
  * knowing that a Part was replaced: an epoch per context (pt_epoch), and a
    notification before the native bytes change and after the new ones are
    published (CLIENTS' `before` / `replaced`).

The code is radiohagen's MIDI PART STATE (modules/midi-loopback/upstream,
modules/midi-part-state: part.s, part-copy.s, entry.s), which did this for
the MIDI SETUP arrays, generalized: the snapshot covers every client's
window, the read and write allow-lists are every client's declared bytes,
and the notifications are registered at build time as STORE's are. MIDI
PART STATE's own API (mp_*) stays under its names for the clients that use
it, with its behaviour unchanged; this module retires MIDI PART STATE.

Sites: 0x40020898 (stock memcpy's entry) and 0x40005638 (Part
initialization's entry) go to resident gates in ROM (entry.s) that call
stock until the boot's post-loader call at 0x40000512 publishes the runtime's
wrappers -- memcpy runs before the platform runtime is loaded. A remix with
no client gets none of this: PARTS installs nothing without one.

A client registers in CLIENTS below and declares `requires=("PARTS",)`.
Notifications run unmasked, in the native copy's context (a UI or load path,
never the frame interrupt): a handler may not call a kernel or UI primitive
(docs/contributing/TRAPS.md), and may clobber every register.
"""

import os

from remix.schema import Category, Claims, Detour, Gate, Kind, Linked, Module, Poke, Proof

H = bytes.fromhex
_HERE = os.path.relpath(os.path.dirname(os.path.realpath(__file__)))

PART_LEN = 0x18B2                      # a working Part's bytes
MIDI_SETUP = 0x4E2                     # the MIDI tracks' SETUP arrays: 8 x 36 bytes
# MIDI PART STATE's writable SETUP offsets (bits 3,5,12,13,15,16,18,19) and
# KEY (17), read only; offset 12 is the shared MIDI flags byte.
MIDI_WRITABLE = tuple(MIDI_SETUP + 36 * t + f for t in range(8) for f in (3, 5, 12, 13, 15, 16, 18, 19))
MIDI_READ_ONLY = tuple(MIDI_SETUP + 36 * t + 17 for t in range(8))

EVENTS = ("before", "replaced")
# (module key, handler prefix, events, windows ((Part offset, length), ...),
#  writable Part offsets, uses MIDI PART STATE's mp_* names).
# A handler is `<prefix>_pt_<event>`: before -- d0 the working Part's address,
# d1 its context, the native bytes not yet changed; replaced -- d0 the context,
# the new bytes published. Table order is call order.
CLIENTS = (
    ("MIDI LOOPBACK", None, (), ((MIDI_SETUP, 8 * 36),), MIDI_WRITABLE, True),
)
# What a client brings that is not code: MIDI PART STATE's shared flags byte
# and the Part validator's range for it (0..15, not stock's 0..1).
MIDI_POKES = (Poke(0x400D4082, H("00000001"), H("00000010"), "Follow/Loopback Part flags range"),)
MIDI_CLAIMS = tuple((MIDI_SETUP + 36 * t + 12, 1, "shared MIDI Part flags") for t in range(8))


def _present(modules):
    return tuple(c for c in CLIENTS if c[0] in modules)


def window(modules):
    """(lo, length) of the snapshot: the span of every present client's
    windows, length a multiple of 4; (0, 0) with no window."""
    spans = [(o, o + n) for c in _present(modules) for o, n in c[3]]
    if not spans:
        return 0, 0
    lo, hi = min(a for a, _b in spans), max(b for _a, b in spans)
    return lo, (hi - lo + 3) & ~3


def _bitmap(offsets):
    bits = bytearray((PART_LEN + 7) // 8)
    for o in offsets:
        if not 0 <= o < PART_LEN:
            raise ValueError(f"PARTS: Part offset 0x{o:x} is outside a Part (0..0x{PART_LEN - 1:x})")
        bits[o >> 3] |= 1 << (o & 7)
    return bytes(bits)


def readable(modules):
    return sorted({o + i for c in _present(modules) for o, n in c[3] for i in range(n)})


def writable(modules):
    out = sorted({o for c in _present(modules) for o in c[4]})
    inside = set(readable(modules))
    for o in out:
        if o not in inside:
            raise ValueError(f"PARTS: writable Part offset 0x{o:x} is outside every client's window")
    return out


def _check():
    keys = set()
    for key, prefix, events, windows, _w, _mp in CLIENTS:
        if key in keys or set(events) - set(EVENTS) or (events and not prefix):
            raise ValueError(f"PARTS: invalid registration {key!r}")
        keys.add(key)
        for o, n in windows:
            if n <= 0 or o < 0 or o + n > PART_LEN:
                raise ValueError(f"PARTS: {key}'s window 0x{o:x}+{n} is outside a Part")


def parts_inc(modules, remix=None):
    """remix.inc for parts.s."""
    _check()
    lo, n = window(modules)
    out = [f".set PT_LO, 0x{lo:x}", f".set PT_LEN, {n}",
           f".set PT_MIDI, {int(any(c[5] for c in _present(modules)))}"]
    for ev in EVENTS:
        handlers = [f"{c[1]}_pt_{ev}" for c in _present(modules) if ev in c[2]]
        out.append(f".macro pt_{ev}_calls")
        if handlers:
            out += ["    lea -60(%sp),%sp", "    movem.l %d0-%d7/%a0-%a6,(%sp)"]
            for h in handlers:
                out += ["    movem.l (%sp),%d0-%d1", f"    jsr {h}"]
            out += ["    movem.l (%sp),%d0-%d7/%a0-%a6", "    lea 60(%sp),%sp"]
        out.append(".endm")
    out.append(".macro pt_tables")
    for name, bits in (("pt_rd", _bitmap(readable(modules))), ("pt_wr", _bitmap(writable(modules)))):
        out.append(f"{name}:")
        out += ["    .byte " + ", ".join(f"0x{b:02x}" for b in bits[i:i + 16]) for i in range(0, len(bits), 16)]
    out.append(".endm")
    return "\n".join(out) + "\n"


ENTRY = Linked("partsentry", os.path.join(_HERE, "entry.s"),
               # resolved from the runtime after its link (schema.Linked.runtime_refs);
               # placeholders inside the runtime's range, so the first link encodes
               # the same 32-bit immediates as the final one (0 would be a moveq)
               defsyms=(("pt_native_copy", 0x40A95000), ("pt_native_init", 0x40A95004)),
               runtime_refs=(("pt_native_copy", "parts", "pt_native_copy"),
                             ("pt_native_init", "parts", "pt_native_init")))
DETOURS = (
    Detour(0x40000512, H("4eb94000f938"), "partsentry", "pt_resident_activate",
           "the boot after the platform loader: publish the runtime's Part wrappers", kind="jsr"),
    Detour(0x40020898, H("2f02226f0008"), "partsentry", "pt_copy_entry",
           "stock memcpy's entry: a copy over a working Part, published coherently"),
    Detour(0x40005638, H("4fefffa848d77cfc"), "partsentry", "pt_init_entry",
           "Part initialization's entry: a cleared Part, published coherently", pad_to=8),
)


def _unit(modules):
    _lo, n = window(modules)
    mutable = (("pt_part_epochs", 64 * 4),) + ((("pt_snapshot", 4 * n),) if n else ())
    # MIDI PART STATE's runtime named the resident targets (its gates read them
    # from the runtime's symbols); the build resolves these from the entry's
    # exports. Nothing here references them.
    names = ((("mp_copy_target", 0), ("mp_init_target", 0))
             if any(c[5] for c in _present(modules)) else ())
    return Linked("parts", os.path.join(_HERE, "parts.s"), dram=True, include=parts_inc,
                  boot_mutable=mutable, defsyms=names)


def select(modules):
    """PARTS's code and sites only with a client; MIDI PART STATE's flags
    byte and validator range only with a client that uses them."""
    present = _present(modules)
    if not present:
        return {"linked": (), "detours": (), "pokes": (), "claims": None}
    midi = any(c[5] for c in present)
    return {"linked": (ENTRY, _unit(modules)), "detours": DETOURS,
            "pokes": MIDI_POKES if midi else (),
            "claims": Claims(part_window=MIDI_CLAIMS) if midi else None}


_ALL = select({c[0] for c in CLIENTS})

MODULE = Module(
    name="parts",
    key="PARTS",
    kind=Kind.CF_PATCH,
    category=Category.PARTS, author="radiohagen, Sam Banks", author_url="https://github.com/radiohagen",
    proof=Proof.PORT,
    proof_note="MIDI PART STATE's gates (verify_midi_part, verify_midi_part_copy) on its mp_* API, and verify_parts "
               "on the generic API, the notifications and the activation, under Unicorn; not flashed",
    doc="System: the Part a module reads or writes, coherent across a native copy or clear, with replacement notices.",
    linked=_ALL["linked"], detours=_ALL["detours"], pokes=_ALL["pokes"], claims=_ALL["claims"],
    select=select,
    gates=(Gate("tools/verify/verify_parts.py", stage="image", venv=True),),
)
