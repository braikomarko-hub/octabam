"""MU-SHRM -- the Mu-Tron III's photocell on two Sherman Filterbank-style filters, with the dirt.

A per-track insert (FX1 or FX2: no delay line, its state is ~60 words of its r7 block), MONO: L and R are summed,
filtered once, and the result goes to both sides (MaMarko, 26 Nov 2026).  Idea, choices and
listening: MaMarko; design, model and code: Claude (Anthropic), 26 Nov 2026.

  * the photocell (the Mu-Tron III's envelope follower): the block peak of |L+R|/2 -- of this track, or with
    KEY T1..T8 of that track, as KEYBUS publishes it -- through SENS, a LED law ((dB + 24)/18) and a one-pole
    with a fast attack and a slow release (SPD).  SPD 127 is GATE: the photocell is 0 or 1 and also opens the
    output (the Mutronics Mutator's gate);
  * two TPT state-variable filters a channel (F1 at BASE moved by DPTH x the photocell, F2 a HARM step away),
    in parallel or in series, MORF from low-pass through band-pass to high-pass, each with its resonance
    through a soft clip so it cannot run away;
  * the Sherman's dirt (DIRT): noise before the filters, the switched-capacitor clock (100 or 50 x F1) holding
    the output and leaking into it; DRIV and an asymmetric saturation (ASYM) before and after.

The integer model tools/mushrm/mushrm_ref.py is the judge: tools/mushrm/gen_mushrm.py writes mushrm.asm from
the same constants, and tools/verify/verify_mushrm.py wants every sample of the assembly equal to the model's.
"""
import importlib.util as _ilu
import pathlib as _pl

from remix.schema import (BusRole, Category, DspSection, Formatter, Gate, Harness, Kind, MenuEntry, Module,
                          Param, Proof, YBase)

_spec = _ilu.spec_from_file_location("_mushrm_ref", _pl.Path(__file__).resolve().parents[2] / "tools/mushrm/mushrm_ref.py")
REF = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(REF)

PTABLE = tuple(w & 0xFFFFFF for w in REF.PTABLE)        # LOG (33), EXP2 (17), G (69), HARM (11)

_P = Formatter.PLAIN
_B = Formatter.BIPOLAR
_HARM = tuple(f"{r}{st:+d}" if st else f"{r}0" for r in "PS" for st in REF.HARM_ST)

MODULE = Module(
    name="mushrm",
    key="MU-SHRM",
    kind=Kind.DSP_EFFECT,
    category=Category.TRACK, author="MaMarko", author_url="https://github.com/braikomarko-hub",
    proof=Proof.CHECK,
    proof_note="bit-exact against its integer model in dsp_host on both payloads (verify_mushrm), 26 Nov 2026; not yet on a unit",
    doc="The Mu-Tron III's photocell on two dirty Sherman-style filters: auto-wah, two resonances, side-chain KEY from any track, GATE.",
    menu=MenuEntry(
        fx2_id=0x0b,                  # preferred, not a stock id: the remix may move it (registry.assign_ids)
        donor_desc=0x400d58b8,        # DARK REV: 12 active slots
        abbr=b"MUSH",
        fullname=b"MU-SHRM",
        build_tag=False,
    ),
    params=(
        Param(b"BASE", 40, 128, active=True, formatter=_P,
              doc="F1 at rest: 30 Hz (0) .. 10 kHz (127), exponential"),
        Param(b"SENS", 64, 128, active=True, formatter=_B,
              doc="how much the photocell hears: -18 .. +18 dB (64 = 0 dB)"),
        Param(b"DPTH", 96, 128, active=True, formatter=_B,
              doc="how far the photocell moves F1: 64 none, up opens, down closes, up to 5 octaves"),
        Param(b"RES1", 60, 128, active=True, formatter=_P, doc="F1's resonance"),
        Param(b"RES2", 40, 128, active=True, formatter=_P, doc="F2's resonance"),
        Param(b"HARM", 5, count=22, active=True, formatter=Formatter.WIDE_STEPPED, labels=_HARM,
              doc="F2 against F1 (-24 .. +24 semitones), P = in parallel, S = in series"),
        Param(b"MORF", 0, 128, active=True, formatter=_P,
              doc="0 low-pass, 64 band-pass, 127 high-pass, continuous"),
        Param(b"KEY", 0, count=9, active=True, formatter=Formatter.WIDE_STEPPED,
              labels=("OFF", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8"),
              doc="who moves the photocell: OFF = this track, T1..T8 = that track (KEYBUS's block peak)"),
        Param(b"SPD", 64, 128, active=True, formatter=_P,
              doc="the photocell's speed: 64 = 4 ms attack / 45 ms release, 0 four times slower, 126 ~four times faster; 127 = GATE"),
        Param(b"DRIV", 32, 128, active=True, formatter=_P,
              doc="0 .. +30 dB in; two thirds of the dB come back off at the output"),
        Param(b"ASYM", 32, 128, active=True, formatter=_P,
              doc="the asymmetric saturation, at the input and (half) at the output"),
        Param(b"DIRT", 0, 128, active=True, formatter=_P,
              doc="0 clean; 1..63 noise + the clock at 100 x F1; 64..127 the clock at 50 x F1, dirtier"),
    ),
    dsp=DspSection(
        asm="modules/mushrm/mushrm.asm",
        ptable=PTABLE,
        priority=29,                  # after KEYBUS (25), VCA160 (26), FET76 (28)
        bus_role=BusRole.NONE,
        ybase=YBase.NEVER,
        r7_latch_slot=None,
        gate_label=None,
    ),
    requires=("KEYBUS",),
    harness=Harness(layout_char=None, is_server=False),
    gates=(Gate("tools/verify/verify_mushrm.py", remix_arg=False),),
    dear={"BASE": 127, "SENS": 127, "DPTH": 127, "RES1": 127, "RES2": 127, "HARM": 21, "MORF": 64,
          "KEY": 1, "SPD": 126, "DRIV": 127, "ASYM": 127, "DIRT": 127},
)
