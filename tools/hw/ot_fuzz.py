#!/usr/bin/env python3
"""Seeded stress sequences for the unit, driven over USB MIDI, with the health checks of the one-cable rig.

    python3 tools/hw/ot_fuzz.py gen SEED OUT.json [--profile mix] [--minutes 5] [--layouts 28]
    python3 tools/hw/ot_fuzz.py run SEQ.json LABEL [--until N] [--audio Octatrack] [--midi NAME] [--no-silence-check]
    python3 tools/hw/ot_fuzz.py show SEQ.json [--from N --to M]
    python3 tools/hw/ot_fuzz.py port REMIX PROJECT LABEL [--seeds 1-8] [--seconds 30] [--profile pc]   # no unit: the ColdFire port

A sequence is a list of timed operations a person could make over MIDI: program changes to the
project's layouts (single, in bursts a few tenths of a second apart, and back again), START and
STOP at any moment, a MIDI clock whose tempo moves, the crossfader (CC 48) swept and jumped, scene
A / B select (CC 55, 56), track mutes and levels, FX page-1 knobs. The same SEED gives the same
sequence; `run` sends it with the recorded timing and, every 0.5 s, checks that the DSP's frame
count advances, the frame interrupt keeps its rate and LOAD METER's bad records stay near zero,
that the MIDI and audio endpoints are still there and, with at least three tracks unmuted by the
sequence, the audio rms over 3 s has not fallen below -80 dB while the transport plays. It stops on the first failure and writes out/hw/fuzz/LABEL/failure.json
with the operation index, the last 40 operations and the unit's state, so `run SEQ.json LABEL
--until INDEX` replays up to it. The unit has to be power-cycled after a failure.

Profiles: pc (program changes only, bursts included), transport (START / STOP / tempo), xf (crossfader
and scene select), scenes (the same with scene select drawn over 0..15, the range the unit takes; pair it with
`ot_scenes.py stamp --all-scenes`), mix (all of them, program changes weighted most).

What it does not do: the panel (LOAD KIT, SAVE KIT, setting a scene lock, the direct-jump toggle) has
to be set up by hand before a run, and it cannot see inside the unit beyond LOAD METER, the audio
stream and the endpoints; a halt that leaves them looking normal is missed. The projects it drives are
the ones `ot_matrix.py proj` writes: layouts are programs 16 * bank + pattern - 1.
"""
import argparse
import json
import pathlib
import random
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

PROFILES = {
    "pc": {"pc": 10, "pc_burst": 4, "pc_back": 3},
    "transport": {"start": 5, "stop": 5, "tempo": 4, "pc": 2},
    "xf": {"xf_sweep": 5, "xf_jump": 4, "scene": 4, "pc": 1},
    "scenes": {"xf_sweep": 5, "xf_jump": 4, "scene": 6, "pc": 1},
    "mix": {"pc": 10, "pc_burst": 4, "pc_back": 3, "start": 3, "stop": 3, "tempo": 2, "xf_sweep": 3, "xf_jump": 3,
            "scene": 2, "mute": 3, "level": 2, "knob": 4},
}
HEALTH_EVERY_S, DEAD_AUDIO_S = 0.5, 3.0
MIN_AUDIBLE_TRACKS = 3        # the silence check needs this many unmuted tracks: one track through an effect can be quieter than -80 dB


def program_of(layout):
    """Layout slot (0..31) -> the program change that selects it (ot_matrix: bank = slot // 4, pattern = slot % 4)."""
    return (layout // 4) * 16 + layout % 4


def gen(seed, minutes, layouts, profile):
    """-> {"seed", "profile", "layouts", "ops": [{"t": seconds, "op": name, "bytes": [..], "note": text}]}.
    Bytes are on MIDI channel 1 for program changes and on the track's channel (track t = channel t) for CCs."""
    rng = random.Random(seed)
    weights = PROFILES[profile]
    names, w = list(weights), [weights[k] for k in weights]
    ops, t, bpm, playing, layout, nb = [], 0.0, 120.0, False, 0, 0

    def add(at, op, bytes_, note=""):
        ops.append({"t": round(at, 3), "op": op, "bytes": list(bytes_), "note": note})

    add(0.0, "start", [0xFA], "START at the first layout")
    playing = True
    while t < minutes * 60.0:
        t += rng.choice([0.25, 0.5, 1.0, 2.0, 3.0, 5.0]) * rng.uniform(0.6, 1.4)
        kind = rng.choices(names, w)[0]
        if kind == "pc":
            layout = rng.randrange(layouts)
            add(t, "pc", [0xC0, program_of(layout)], f"layout {layout}")
        elif kind == "pc_burst":
            nb += 1
            for j in range(rng.randint(3, 8)):
                layout = rng.randrange(layouts)
                add(t, "pc", [0xC0, program_of(layout)], f"burst {nb}.{j}, layout {layout}")
                t += rng.uniform(0.02, 0.4)
        elif kind == "pc_back":
            a, b = layout, rng.randrange(layouts)
            add(t, "pc", [0xC0, program_of(b)], f"layout {b}")
            add(t + rng.uniform(0.05, 0.8), "pc", [0xC0, program_of(a)], f"back to layout {a}")
            t += 1.0
        elif kind == "start" and not playing:
            add(t, "start", [0xFA]); playing = True
        elif kind == "stop" and playing:
            add(t, "stop", [0xFC]); playing = False
        elif kind == "tempo":
            bpm = max(60.0, min(180.0, bpm + rng.choice([-30, -10, -1, 1, 10, 30])))
            add(t, "tempo", [], f"{bpm:g}")
        elif kind == "xf_sweep":
            a, b = rng.randrange(128), rng.randrange(128)
            n = rng.randint(8, 40)
            for i in range(n + 1):
                add(t + i * 0.05, "cc", [0xB0, 48, round(a + (b - a) * i / n)], "crossfader sweep")
            t += n * 0.05
        elif kind == "xf_jump":
            add(t, "cc", [0xB0, 48, rng.choice([0, 127, rng.randrange(128)])], "crossfader jump")
        elif kind == "scene":
            # The unit clamps the value to 0..15 (MIDI.md Appendix A): drawn over 0..127, 7 in 8 select scene 15.
            add(t, "cc", [0xB0, rng.choice([55, 56]), rng.randrange(16 if profile == "scenes" else 128)], "scene select")
        elif kind == "mute":
            tr = rng.randrange(8)
            add(t, "cc", [0xB0 | tr, 49, rng.choice([0, 127])], f"mute T{tr + 1}")
        elif kind == "level":
            tr = rng.randrange(8)
            add(t, "cc", [0xB0 | tr, 7, rng.randrange(40, 128)], f"level T{tr + 1}")
        elif kind == "knob":
            tr = rng.randrange(8)
            cc = rng.choice(list(range(34, 40)) + list(range(40, 46)))
            add(t, "cc", [0xB0 | tr, cc, rng.randrange(128)], f"T{tr + 1} knob CC{cc}")
    add(t + 2.0, "stop", [0xFC], "end")
    ops.sort(key=lambda o: o["t"])
    return {"seed": seed, "profile": profile, "layouts": layouts, "minutes": minutes, "ops": ops}


class ClockGen(threading.Thread):
    """24 ppqn MIDI clock whose tempo can change, sent while `running`."""

    def __init__(self, out, bpm=120.0):
        super().__init__(daemon=True)
        self.out, self.bpm, self.stop_evt = out, bpm, threading.Event()

    def run(self):
        nxt = time.monotonic()
        while not self.stop_evt.is_set():
            self.out.send([0xF8])
            nxt += 60.0 / (self.bpm * 24.0)
            d = nxt - time.monotonic()
            if d > 0:
                time.sleep(d)
            else:
                nxt = time.monotonic()


def cmd_gen(a):
    seq = gen(a.seed, a.minutes, a.layouts, a.profile)
    pathlib.Path(a.out).write_text(json.dumps(seq, indent=1))
    kinds = {}
    for o in seq["ops"]:
        kinds[o["op"]] = kinds.get(o["op"], 0) + 1
    print(f"seed {a.seed}, profile {a.profile}: {len(seq['ops'])} operations over {seq['ops'][-1]['t']:.0f} s: {kinds}")
    return 0


def cmd_show(a):
    seq = json.loads(pathlib.Path(a.seq).read_text())
    for i, o in enumerate(seq["ops"]):
        if (a.start is None or i >= a.start) and (a.to is None or i <= a.to):
            print(f"{i:5d} {o['t']:8.3f}s  {o['op']:6s} {bytes(o['bytes']).hex(' '):12s} {o['note']}")
    return 0


def cmd_run(a):
    import numpy as np
    import ot_midi
    import load_meter
    import sounddevice as sd
    import usb_transport_probe as U
    seq = json.loads(pathlib.Path(a.seq).read_text())
    ops = seq["ops"] if a.until is None else seq["ops"][:a.until + 1]
    out_dir = pathlib.Path("out/hw/fuzz") / a.label
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in ("failure.json", "run.json"):
        (out_dir / stale).unlink(missing_ok=True)            # a previous run's verdict must not outlive it
    usb = load_meter.libusb_device()
    try:
        load_meter.read_fast(usb)
    except Exception as e:  # noqa: BLE001
        if getattr(e, "errno", None) != 32:
            raise
        print("The image has no LOAD METER (0xc0/0x57 STALLs): health is the MIDI destination and the audio only.")
        usb = None
    dev, nch = U.find_input(a.audio)
    out = ot_midi.Out(a.midi)
    clock = ClockGen(out)
    state = {"idx": -1, "db": -240.0, "played_at": None, "bad0": None, "fail": None, "samples": [], "muted": set()}

    blocks = []                                    # (time, sum of squares, samples) over the last DEAD_AUDIO_S

    def cb(indata, frames, t, status):
        x = indata[:, :2].astype(np.float64)
        state["db"] = float(20 * np.log10(max(np.sqrt(np.mean(x ** 2)), 1e-12)))
        now = time.monotonic()
        blocks.append((now, float(np.sum(x ** 2)), x.size))
        while blocks and now - blocks[0][0] > DEAD_AUDIO_S:
            blocks.pop(0)

    def window_db():
        """rms over the last DEAD_AUDIO_S seconds: one quiet stretch of a sweep or a decay is not silence."""
        snap = list(blocks)
        n = sum(b[2] for b in snap)
        return 20 * np.log10(max(np.sqrt(sum(b[1] for b in snap) / n), 1e-12)) if n else -240.0
    last_audio = {"t": time.monotonic()}

    def check():
        """-> a reason string, or None."""
        if usb is not None:
            ok, why = load_meter.healthy(usb)
            if not ok:
                return why
            r = load_meter.read_fast(usb)
            if state["bad0"] is None:
                state["bad0"] = r["dsp"]["bad"]
            state["samples"].append((round(time.monotonic() - t_start, 2), round(r["cf"]["longest_us"]), r["dsp"]["bad"] - state["bad0"],
                                     round(r["cf"]["mean_us"], 1), round(r["cf"]["share"], 4)))
            if r["dsp"]["bad"] - state["bad0"] > 200:
                return f"{r['dsp']['bad'] - state['bad0']} bad records since the start (frames are being skipped)"
        if not any(n == "Elektron Octatrack DPS-1" for n, _ in ot_midi.endpoints("dst")):
            return "the MIDI destination is gone"
        if (not a.no_silence_check and 8 - len(state["muted"]) >= MIN_AUDIBLE_TRACKS and state["played_at"] is not None
                and time.monotonic() - state["played_at"] > DEAD_AUDIO_S and window_db() < -80.0):
            return f"the audio has been below -80 dB (rms over {DEAD_AUDIO_S:.0f} s) while the transport plays"
        return None

    t_start = time.monotonic()
    code = 0
    try:
        with sd.InputStream(device=dev, channels=nch, samplerate=44100, dtype="float32", callback=cb):
            clock.start()
            health_stop = threading.Event()

            def health():
                # check() takes 0.4 s (load_meter.healthy waits for the frame counter to move); inline in the
                # sender it delayed every operation up to 0.4 s and sent them in bursts (25 Oct 2026)
                nxt = time.monotonic()
                while not health_stop.is_set() and not state["fail"]:
                    if time.monotonic() >= nxt:
                        nxt += HEALTH_EVERY_S
                        try:
                            why = check()
                        except Exception as e:  # noqa: BLE001
                            why = f"the health check raised {e!r}"
                        if why:
                            state["fail"] = why
                    time.sleep(0.01)
            threading.Thread(target=health, daemon=True).start()
            for i, o in enumerate(ops):
                while time.monotonic() - t_start < o["t"] and not state["fail"]:
                    time.sleep(0.002)
                if state["fail"]:
                    break
                state["idx"] = i
                if o["op"] == "tempo":
                    clock.bpm = float(o["note"])
                elif o["bytes"]:
                    out.send(o["bytes"])
                    if o["op"] == "cc" and o["bytes"][1] == 49:
                        (state["muted"].add if o["bytes"][2] >= 64 else state["muted"].discard)(o["bytes"][0] & 15)
                if o["op"] == "start":
                    state["played_at"] = time.monotonic(); last_audio["t"] = time.monotonic()
                elif o["op"] == "stop":
                    state["played_at"] = None
            health_stop.set()
            if not state["fail"]:
                # a final look after the last operation
                time.sleep(1.0)
                state["fail"] = check()
    finally:
        clock.stop_evt.set()
        try:
            out.send([0xFC])
        except Exception:  # noqa: BLE001
            pass
    idx = state["idx"]
    if state["fail"]:
        code = 1
        rep = {"seed": seq["seed"], "profile": seq["profile"], "failed_after_operation": idx, "reason": state["fail"],
               "elapsed_s": round(time.monotonic() - t_start, 1), "last_operations": ops[max(idx - 39, 0):idx + 1],
               "samples_tail": state["samples"][-20:],
               "replay": f"python3 tools/hw/ot_fuzz.py run {a.seq} {a.label}_replay --until {idx}"}
        (out_dir / "failure.json").write_text(json.dumps(rep, indent=1))
        print(f"FAILED after operation {idx} at {rep['elapsed_s']} s: {state['fail']}")
        print(f"  last: {ops[idx]['op']} {ops[idx]['note']}; failure.json has the last 40 operations. Power-cycle the unit.")
    else:
        longest = max((s[1] for s in state["samples"]), default=0)
        print(f"{len(ops)} operations over {ops[-1]['t']:.0f} s, no failure; ColdFire longest run {longest} us, "
              f"bad records {state['samples'][-1][2] if state['samples'] else 0}")
    (out_dir / "run.json").write_text(json.dumps({"seed": seq["seed"], "operations": len(ops), "failed": state["fail"],
                                                  "samples": state["samples"][::4]}))
    return code


FRAMES_PER_S = 44100 / 16.0          # the frame engine's rate: 2,756.25 frames a second


def midi_script(seq, frames):
    """The port's --midi file: `<frames after the transport start> <hex bytes>` for the program changes and CCs
    inside `frames`. START, STOP and tempo are the unit's own and have no counterpart under --internal-clock."""
    lines, kept, skipped = [], 0, 0
    for o in seq["ops"]:
        f = int(round(o["t"] * FRAMES_PER_S))
        if f >= frames:
            break
        if o["op"] in ("pc", "cc"):
            lines.append(f"{max(f, 1)} " + bytes(o["bytes"]).hex(" "))
            kept += 1
        else:
            skipped += 1
    return "\n".join(lines) + "\n", kept, skipped


def parse_port_log(text):
    """-> (ok, summary) from an ot_emu log: the run must reach its frame target with every MIDI byte taken."""
    import re
    m = re.search(r"frames run : (\d+) since transport start \(target (\d+)\), run ended (\w+)(?: -- (.*))?", text)
    if not m:
        return False, "no frames line (the load or the run did not complete)"
    ran, target, how, why = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
    q = re.search(r"midi in\s+: (\d+) byte\(s\) still queued", text)
    if how != "REACHED":
        return False, f"{how} after {ran} of {target} frames: {why or ''}"[:300]
    if q and int(q.group(1)) > 0:
        return False, f"{q.group(1)} MIDI byte(s) still queued at the end"
    return True, f"{ran} frames"


PATTERN_S = 8.0                      # 64 steps at 120 BPM: a program change lands at the next multiple of this


def effective_layout(seq, end_s, start=0):
    """The layout playing at end_s if a program change is taken at the next pattern end and the last one received
    before that end wins (the model under test, 24 Oct 2026: measured on a unit for one change at a time)."""
    cur, pending = start, None
    ops = [o for o in seq["ops"] if o["op"] == "pc" and o["t"] < end_s]
    boundary, i = PATTERN_S, 0
    while boundary <= end_s:
        while i < len(ops) and ops[i]["t"] < boundary:
            pending = ops[i]["bytes"][1]; i += 1
        if pending is not None:
            cur = layout_of_program(pending, seq.get("layouts", 32))
            pending = None
        boundary += PATTERN_S
    return cur


def layout_of_program(program, layouts):
    """Inverse of program_of for slots < layouts."""
    for i in range(layouts):
        if program_of(i) == program:
            return i
    return None


def expected_ids(remix, project, slot):
    """-> the 16 live effect ids (FX1 x 8, FX2 x 8) layout `slot` of the project stamps."""
    sys.path.insert(0, str(HERE.parent))
    import toolpath  # noqa: F401
    import ot_ladder as L
    import ot_matrix as M
    from remix import registry
    plan = json.loads((pathlib.Path(project) / "OCTABAM_MATRIX.json").read_text())
    name = plan["layouts"][slot]["name"]
    lo = {n: lo for n, _k, lo in M.layouts(remix, True, True)}[name]
    r, mods = registry.remix(remix), registry.modules()
    return ([L._slot_bytes(lo[t][0], r, mods)[0] for t in range(1, 9)] + [L._slot_bytes(lo[t][1], r, mods)[0] for t in range(1, 9)])


def kits_assign(project):
    """The project's ASSIGN table (pattern index -> Kit, 0xff none) when it has a valid kits.work with Kits, else None."""
    import ot_kits
    f = pathlib.Path(project) / "kits.work"
    if not f.is_file():
        return None
    try:
        info = ot_kits.parse(f.read_bytes())
    except ValueError:
        return None
    return info["assign"] if any(v != 0xFF for v in info["assign"]) else None


def cmd_port(a):
    """Replay sequences under the ColdFire port: stage the project once, load it once, fork one child per sequence."""
    import shutil
    import subprocess
    root = HERE.parents[1]
    out_dir = root / "out/fuzz_port" / a.label
    out_dir.mkdir(parents=True, exist_ok=True)
    venv_py = root / ".venv/bin/python3"
    r = subprocess.run([str(venv_py), "tools/verify/verify_set.py", a.remix, "--project", a.project, "--bank", str(a.bank), "--stage-only"],
                       cwd=root, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"staging failed:\n{r.stdout[-600:]}{r.stderr[-600:]}")
    for f in ("image.bin", "card.img"):
        shutil.copy2(root / "out/setverify" / f, out_dir / f)
    seqs = []
    if a.seqs:
        seqs = [(pathlib.Path(p).stem, json.loads(pathlib.Path(p).read_text())) for p in a.seqs]
    else:
        lo, _, hi = a.seeds.partition("-")
        for sd in range(int(lo), int(hi or lo) + 1):
            seqs.append((f"seed{sd}", gen(sd, a.seconds / 60.0, a.layouts, a.profile)))
    frames = int(a.seconds * FRAMES_PER_S)
    scen = []
    for name, seq in seqs:
        script, kept, skipped = midi_script(seq, frames)
        (out_dir / f"{name}.midi").write_text(script)
        (out_dir / f"{name}.json").write_text(json.dumps(seq))          # the sequence itself: what a failing seed is reproduced from
        scen.append(f"{out_dir / (name + '.log')} --sequencer --internal-clock --frames {frames} --midi {out_dir / (name + '.midi')} "
                    f"--mem-dump 0x80000ec4,16={out_dir / (name + '.ids')}"
                    + (f" --card-out {out_dir / (name + '.card')}" if a.keep_card else ""))
    cmd = [str(root / "out/emu/ot_emu"), "--image", str(out_dir / "image.bin"), "--card", str(out_dir / "card.img"),
           "--set", "OCTABAM", "--project", "RIG", "--load-ms", "90000", "--dsp", "--main-level", "64", "--audio-in", "tones"]
    for sc in scen:
        cmd += ["--scenario", sc]
    cmd += ["--scenario-jobs", str(a.jobs)]
    print(f"{len(seqs)} sequences of {a.seconds:g} s ({frames} frames) from one load, {a.jobs} at a time ...", flush=True)
    t0 = time.time()
    with open(out_dir / "parent.log", "w") as lf:
        rc = subprocess.run(cmd, cwd=root, stdout=lf, stderr=subprocess.STDOUT).returncode
    bad = 0
    for name, seq in seqs:
        lp = out_dir / f"{name}.log"
        ok, why = parse_port_log(lp.read_text()) if lp.exists() else (False, "no log")
        ip = out_dir / f"{name}.ids"
        if ok and ip.exists():
            slot = effective_layout(seq, a.seconds)
            kit_note = ""
            assign = kits_assign(a.project)
            if assign is not None:
                k = assign[program_of(slot)]
                if k != 0xFF:
                    kit_note = f" (pattern {program_of(slot)} plays Kit {k})"
                    slot = k                      # Kit k is layout k's Part, from the first load's migration
            want = expected_ids(a.remix, a.project, slot)
            got = list(ip.read_bytes()[:16])
            if got != want:
                ok = False
                why += f"; the live effect ids are not layout {slot}'s: got {bytes(got).hex(' ')}, want {bytes(want).hex(' ')}"
            else:
                why += f"; ends on layout {slot}{kit_note} as the model says"
        bad += not ok
        print(f"  [{'ok' if ok else 'FAIL'}] {name:10s} {len(seq['ops']):4d} operations  {why}")
    print(f"{len(seqs) - bad} of {len(seqs)} ran clean in {time.time() - t0:.0f} s (parent exit {rc}); logs in {out_dir}")
    return 1 if bad or rc else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("gen"); p.add_argument("seed", type=int); p.add_argument("out")
    p.add_argument("--profile", choices=sorted(PROFILES), default="mix"); p.add_argument("--minutes", type=float, default=5.0)
    p.add_argument("--layouts", type=int, default=28, help="layouts in the project (slot 0 is BASE)")
    p = sub.add_parser("run"); p.add_argument("seq"); p.add_argument("label")
    p.add_argument("--until", type=int, default=None, help="stop after this operation index (a replay)")
    p.add_argument("--audio", default="Octatrack"); p.add_argument("--midi", default="Elektron Octatrack DPS-1")
    p.add_argument("--no-silence-check", action="store_true", help="skip the -80 dB check (a project with no samples is silent)")
    p = sub.add_parser("port", help="replay sequences under the ColdFire port, no unit")
    p.add_argument("remix"); p.add_argument("project"); p.add_argument("label")
    p.add_argument("--bank", type=int, default=1); p.add_argument("--seqs", nargs="*", help="sequence files; else --seeds")
    p.add_argument("--seeds", default="1-4", help="N or N-M: sequences generated on the fly"); p.add_argument("--seconds", type=float, default=30.0)
    p.add_argument("--profile", choices=sorted(PROFILES), default="pc"); p.add_argument("--layouts", type=int, default=28)
    p.add_argument("--jobs", type=int, default=3)
    p.add_argument("--keep-card", action="store_true", help="write each child's card image (64 MB) as NAME.card, to read kits.work back")
    p = sub.add_parser("show"); p.add_argument("seq")
    p.add_argument("--from", dest="start", type=int, default=None); p.add_argument("--to", type=int, default=None)
    a = ap.parse_args()
    return {"gen": cmd_gen, "run": cmd_run, "show": cmd_show, "port": cmd_port}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main() or 0)
