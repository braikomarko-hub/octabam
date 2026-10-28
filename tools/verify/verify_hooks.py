#!/usr/bin/env python3
"""HOOKS (modules/hooks): which bridges a selection gets, and what they run.

1. Selection: a bridge is on only with two or more of its participants; the
   registry appends HOOKS exactly then; the ledger refuses a bridged pair
   without it and accepts it with it; a malformed registration is refused.
2. Behaviour, under Unicorn: the participants' own sources (REC_TRIG_MUTE's
   submodule source unchanged, REC THRESHOLD, MORPH) linked with bridge.s
   as the platform links them. hk_status_icon is run over every track
   state, mute, arm, TRIG and blink phase, and compared with the model of
   the two routines in HOOKS's order, and with the two routines called one
   after the other; the opposite order is shown to lose the blink. The
   [TRACK]-layer table is decoded and compared with track_key_records.
   The frame interrupt's entry and epilogue chains and the boot chain are
   run with LOAD METER, CF METER, BOOT TRACE and PARTS built with
   HOOKS's flags: one prologue and one epilogue, every participant's work
   done, the registers and stack as the interrupt found them.
3. Installed (stage image, when the built image is the remix's and carries
   HOOKS): stock's six [TRACK]-layer records at 0x400d1594 are the ones
   HOOKS copies; each bridged site holds HOOKS's write, and the
   participants' overridden writes are not there.
"""
import hashlib
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import toolpath  # noqa: E402,F401
from remix import ledger, registry  # noqa: E402

DECL = runpy.run_path(str(ROOT / "modules/hooks/manifest.py"))
RTM = "REC_TRIG_MUTE"
THR = "REC THRESHOLD"
BASE_IMG = 0x40000400
fails = 0


def check(ok, what):
    global fails
    print(f"  [{'PASS' if ok else 'FAIL'}] {what}")
    if not ok:
        fails += 1


def selection():
    known = registry.modules()
    m = lambda *ks: [known[k] for k in ks + ("MEMORY",)]   # noqa: E731
    bridged = DECL["bridged"]
    check(bridged({RTM}) == () and bridged({"MORPH"}) == () and bridged({THR}) == (),
          "one participant alone: no bridge")
    check(bridged({RTM, "MORPH"}) == ("track_key",), "REC_TRIG_MUTE + MORPH: track_key only")
    check(bridged({RTM, THR}) == ("status_icon",), "REC_TRIG_MUTE + REC THRESHOLD: status_icon only")
    check(bridged({RTM, THR, "MORPH"}) == ("track_key", "status_icon"), "all three: both bridges")
    check(DECL["select"](set()) == {"linked": (), "detours": (), "symbol_refs": (), "overrides": ()},
          "an empty selection: HOOKS has no unit, claim or override")
    check(not registry.hooks_needed(known, {RTM, "MORPH"} - {"MORPH"}) and
          registry.hooks_needed(known, {RTM, "MORPH"}), "registry.hooks_needed follows the bridges")
    for name, want in (("octabam", False), ("morph", False), ("rec-threshold", False), ("hooks", True)):
        try:
            has = "HOOKS" in registry.remix(name).modules
        except SystemExit:
            continue
        check(has == want, f"remix {name}: HOOKS {'appended' if want else 'not appended'}")
    for sel in ((RTM, "MORPH", "STORE"), (RTM, THR)):
        bad = ledger.check(m(*sel))
        check(any(p.startswith("hooks:") for p in bad), f"{' + '.join(sel)} without HOOKS is refused")
        check(ledger.check(m(*sel, "HOOKS")) == [], f"{' + '.join(sel)} with HOOKS is clean")
    rom = {sym for parts in DECL["BRIDGES"].values() for key, *rest in parts
           for sym in (rest[0],) if isinstance(rest[0], str)
           and any(sym in (ROOT / u.source).read_text() and not u.dram for u in known[key].linked)}
    check(rom == DECL["ROM_ROUTINES"], f"ROM_ROUTINES names the ROM-placed routines ({', '.join(sorted(rom))})")
    tk = DECL["TRACK_KEY"]
    for bad, why in (((("A", ((0x31, "a", None),), (), False), ("B", ((0x31, "b", None),), (), False)),
                      "two participants replacing one key"),
                     ((("A", (), ((0x27, "a", None),), False),), "an added key stock already has"),
                     ((("A", ((0x99, "a", None),), (), False),), "a replaced key stock does not have")):
        DECL["track_key_records"].__globals__["TRACK_KEY"] = bad
        try:
            DECL["track_key_records"]({"A", "B"})
            check(False, f"refused: {why}")
        except ValueError:
            check(True, f"refused: {why}")
    DECL["track_key_records"].__globals__["TRACK_KEY"] = tk


def _link(work):
    """bridge.s, REC_TRIG_MUTE, REC THRESHOLD and MORPH linked as one runtime,
    as platform_build.link_runtime links DRAM units: each assembled for the
    chip, one ld. Returns (image bytes, base, symbols)."""
    keys = {RTM, THR, "MORPH"}
    (work / "remix.inc").write_text(DECL["hooks_inc"](keys))
    known = registry.modules()
    units = [(k, u) for k in (RTM, THR, "MORPH") for u in known[k].linked] + [("HOOKS", DECL["UNIT"])]
    objs = []
    for i, (_k, u) in enumerate(units):
        obj = work / f"{i}_{u.label}.o"
        defs = [a for n, v in u.defsyms for a in ("--defsym", f"{n}={v}")]
        subprocess.run(["m68k-elf-as", "-mcpu=54455", "-I", str(work), "-I", str(ROOT), *defs,
                        "-o", str(obj), str(ROOT / u.source)], check=True, capture_output=True)
        objs.append(str(obj))
    base = 0x41000000
    # MORPH calls STORE's file routines, which nothing here runs: only its key
    # handlers' addresses are read, so those references are left unresolved.
    subprocess.run(["m68k-elf-ld", f"-Ttext=0x{base:x}", "--unresolved-symbols=ignore-all",
                    "-o", str(work / "rt.elf"), *objs],
                   check=True, capture_output=True)
    subprocess.run(["m68k-elf-objcopy", "-O", "binary", str(work / "rt.elf"), str(work / "rt.bin")],
                   check=True)
    nm = subprocess.check_output(["m68k-elf-nm", str(work / "rt.elf")], text=True)
    sym = {f[2]: int(f[0], 16) for line in nm.splitlines() if len(f := line.split()) == 3}
    return (work / "rt.bin").read_bytes(), base, sym


def behaviour():
    from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN
    from unicorn.m68k_const import (UC_CPU_M68K_CFV4E, UC_M68K_REG_A0, UC_M68K_REG_A4,
                                    UC_M68K_REG_A7, UC_M68K_REG_D3, UC_M68K_REG_PC)
    with tempfile.TemporaryDirectory(prefix="octabam-hooks-") as td:
        rt, base, sym = _link(Path(td))
    CACHE, PART_IDX, BANK_PTR, BANK = 0x400C0CB8, 0x100B14CF, 0x46C82456, 0x42000000
    STACK, DONE = 0x47008000, 0x4700FFF0
    u = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    u.ctl_set_cpu_model(UC_CPU_M68K_CFV4E)
    u.mem_map(0x10000000, 0x200000)
    u.mem_map(0x40000000, 0x08000000)
    u.mem_write(base, rt)
    u.mem_write(DONE, b"\x4e\x71")
    u.mem_write(BANK_PTR, BANK.to_bytes(4, "big"))
    u.mem_write(PART_IDX, b"\x00")
    mask, armed, blink = sym["RTM_MASK"], sym["armed"], sym["blink"]

    def trig_addr(t):                                  # thresh.s rec_addr, Part 0, +3
        return BANK + 0x8F382 + 12 * t + 3

    def run(entry, t, a4):
        sp = STACK - 4
        u.mem_write(sp, DONE.to_bytes(4, "big"))
        u.reg_write(UC_M68K_REG_A7, sp)
        u.reg_write(UC_M68K_REG_D3, t)
        u.reg_write(UC_M68K_REG_A4, a4)
        u.emu_start(entry, DONE, count=2000)
        assert u.reg_read(UC_M68K_REG_PC) == DONE
        return (u.reg_read(UC_M68K_REG_A4), u.reg_read(UC_M68K_REG_A0),
                int.from_bytes(u.mem_read(armed + 4 * t, 4), "big"))

    def state(t, muted, arm, trig, off):
        u.mem_write(mask, bytes([(1 << t) if muted else 0]))
        u.mem_write(armed + 4 * t, (0x8010 if arm else 0).to_bytes(4, "big"))
        u.mem_write(trig_addr(t), bytes([trig]))
        u.mem_write(blink, ((1 << 10) if off else 0).to_bytes(4, "big"))

    def model(t, a4, muted, arm, trig, off, order=("rtm", "thr")):
        armed_after = 0x8010 if arm else 0
        for step in order:
            if step == "rtm" and muted and not a4 & 2:
                a4 = (a4 & 1) + 8
            if step == "thr" and arm:
                if trig != 3:
                    armed_after = 0
                elif off:
                    a4 |= 0x10
        return a4, armed_after

    n = bad = bad_seq = 0
    lost = False
    for t in (0, 5):
        for a4 in range(4):
            for muted in (0, 1):
                for arm in (0, 1):
                    for trig in (3, 1):
                        for off in (0, 1):
                            state(t, muted, arm, trig, off)
                            got = run(sym["hk_status_icon"], t, a4)
                            want = model(t, a4, muted, arm, trig, off)
                            state(t, muted, arm, trig, off)
                            mid = run(sym["rtm_glyph"], t, a4)
                            seq = run(sym["blink_gate"], t, mid[0])
                            n += 1
                            bad += (got[0], got[2]) != want or got[1] != CACHE
                            bad_seq += got != seq
                            rev = model(t, a4, muted, arm, trig, off, ("thr", "rtm"))
                            lost |= rev[0] != want[0]
    check(bad == 0, f"hk_status_icon matches the model in all {n} states (a0 = the cache on return)")
    check(bad_seq == 0, "hk_status_icon equals rtm_glyph then blink_gate, called one after the other")
    check(lost, "the opposite order loses the blink on a muted, armed track (why HOOKS folds first)")

    recs = DECL["track_key_records"]({RTM, THR, "MORPH"})
    at = sym["hk_track_keys"]
    table = bytes(u.mem_read(at, 0x1A * (len(recs) + 1)))
    resolve = lambda v: v if isinstance(v, int) else sym[v]   # noqa: E731
    decoded = [(table[i * 0x1A], int.from_bytes(table[i * 0x1A + 2:i * 0x1A + 6], "big"),
                int.from_bytes(table[i * 0x1A + 6:i * 0x1A + 10], "big")) for i in range(len(recs))]
    check(decoded == [(c, resolve(p), resolve(r)) for c, p, r in recs],
          f"the [TRACK]-layer table: {len(recs)} records, YES/NO -> rtm_yes/rtm_no, UP/DOWN -> MORPH")
    check(all(not any(table[i * 0x1A + 10:i * 0x1A + 0x1A]) and table[i * 0x1A + 1] == 0
              for i in range(len(recs))) and table[len(recs) * 0x1A] == 0xFF,
          "each record's padding is zero and stock's terminator follows")


def _link_units(work, keys, units, defs=()):
    """Assemble (key, Linked) units with each one's remix.inc and link them
    as one image at 0x41000000, as the platform links DRAM units. `defs` are
    extra (name, value) link-time symbols. Returns (bytes, base, symbols)."""
    known = registry.modules()
    objs = []
    for i, (_k, u) in enumerate(units):
        d = work / f"inc{i}"
        d.mkdir()
        (d / "remix.inc").write_text(u.include(keys, None) if u.include else "")
        obj = work / f"{i}_{u.label}.o"
        uds = [a for n, v in u.defsyms if n not in dict(defs) for a in ("--defsym", f"{n}={v}")]
        subprocess.run(["m68k-elf-as", "-mcpu=54455", "-I", str(d), "-I", str(ROOT), *uds,
                        "-o", str(obj), str(ROOT / u.source)], check=True, capture_output=True)
        objs.append(str(obj))
    base = 0x41000000
    subprocess.run(["m68k-elf-ld", f"-Ttext=0x{base:x}", "--unresolved-symbols=ignore-all",
                    *[f"--defsym={n}=0x{v:x}" for n, v in defs],
                    "-o", str(work / "rt.elf"), *objs], check=True, capture_output=True)
    subprocess.run(["m68k-elf-objcopy", "-O", "binary", str(work / "rt.elf"), str(work / "rt.bin")],
                   check=True)
    nm = subprocess.check_output(["m68k-elf-nm", str(work / "rt.elf")], text=True)
    sym = {f[2]: int(f[0], 16) for line in nm.splitlines() if len(f := line.split()) == 3}
    del known
    return (work / "rt.bin").read_bytes(), base, sym


def frames():
    """frame_tail, frame_entry and boot: the participants built with their
    flags (hooks_flags) and HOOKS's chains, run under Unicorn."""
    from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN
    from unicorn.m68k_const import (UC_CPU_M68K_CFV4E, UC_M68K_REG_A7, UC_M68K_REG_PC,
                                    UC_M68K_REG_D0, UC_M68K_REG_A6)
    from unicorn import m68k_const as mc
    keys = {"LOAD METER", "CF METER", "BOOT TRACE", "PARTS", "HOOKS"}
    known = registry.modules()
    units = [(k, u) for k in ("LOAD METER", "CF METER", "BOOT TRACE") for u in known[k].linked]
    units += [("PARTS", u) for u in known["PARTS"].linked if u.label == "partsentry"]
    units += [("HOOKS", DECL["UNIT"])]
    with tempfile.TemporaryDirectory(prefix="octabam-hooks-frames-") as td:
        # PARTS's runtime wrappers, which its resident entry publishes, at
        # stand-in addresses (the build resolves them from the runtime)
        rt, base, sym = _link_units(Path(td), keys, units,
                                    defs=(("pt_native_copy", 0x41234560), ("pt_native_init", 0x41234570)))
    regs = [getattr(mc, f"UC_M68K_REG_D{i}") for i in range(8)] + \
           [getattr(mc, f"UC_M68K_REG_A{i}") for i in range(7)]
    u = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    u.ctl_set_cpu_model(UC_CPU_M68K_CFV4E)
    for a, n in ((0x10000000, 0x200000), (0x20000000, 0x10000), (0x40000000, 0x08000000),
                 (0x80000000, 0x100000), (0xFC000000, 0x100000)):
        u.mem_map(a, n)
    u.mem_write(base, rt)
    u.mem_write(0xFC060004, b"\x04")                     # UART0 USR (a byte): TXRDY, so a note never waits
    u.mem_write(0x4000F938, b"\x4e\x75")                 # the boot's callee: rts
    rd = lambda a: int.from_bytes(u.mem_read(a, 4), "big")   # noqa: E731
    STACK = 0x47008000

    # ---- frame_entry: prologue once, BOOT TRACE's note, LOAD METER's stamp
    u.mem_write(0x4000AAD8, b"\x4e\x71")
    vals = [0x1000 + i for i in range(15)]
    for r, v in zip(regs, vals):
        u.reg_write(r, v)
    u.reg_write(UC_M68K_REG_A7, STACK)
    u.mem_write(0xFC07C00C, (0x12345678).to_bytes(4, "big"))  # DTCN3
    u.emu_start(sym["hk_frame_entry"], 0x4000AAD8, count=20000)
    sp = u.reg_read(UC_M68K_REG_A7)
    saved = [rd(sp + 4 * i) for i in range(15)]
    check(u.reg_read(UC_M68K_REG_PC) == 0x4000AAD8 and sp == STACK - 252 and saved == vals,
          "frame_entry: reaches the body with the prologue's frame, once (sp - 252, d0-a6 saved)")
    check(u.mem_read(sym["seen7"], 1)[0] == 1 and rd(sym["lm_t0"]) == 0x12345678,
          "frame_entry: BOOT TRACE's note 7 sent, LOAD METER's entry stamp taken")

    # ---- frame_tail: each participant, then the epilogue once
    for r in regs:
        u.reg_write(r, 0xDEAD0000)
    u.mem_write(0xFC07C00C, (0x12345678 + 500).to_bytes(4, "big"))
    seq0 = rd(sym["lm_stats"])
    u.emu_start(sym["hk_frame_tail"], sym["hk_frame_tail_rte"], count=200000)
    check(u.reg_read(UC_M68K_REG_PC) == sym["hk_frame_tail_rte"] and u.reg_read(UC_M68K_REG_A7) == STACK
          and [u.reg_read(r) for r in regs] == vals,
          "frame_tail: reaches rte once, with sp and d0-a6 as the interrupt found them")
    # Both meters' windows are past due (their window starts at 0), so each
    # publishes this interrupt and starts a new window at `now`.
    now = 0x12345678 + 500
    check(rd(sym["lm_stats"]) == seq0 + 1 and rd(sym["lm_stats"] + 8) == 500
          and rd(sym["lm_stats"] + 12) == 1 and rd(sym["lm_w0"]) == now,
          "frame_tail: LOAD METER publishes this interrupt (one, 500 counts) and starts its window")
    check(rd(sym["m_seg0"]) == now and rd(sym["m_icnt"]) == 0 and u.mem_read(sym["seen8"], 1)[0] == 1,
          "frame_tail: CF METER closes its segment at the same instant; BOOT TRACE's note 8")

    # ---- boot: BOOT TRACE's note 3, then PARTS's activation into the stock call
    DONE = 0x4700FFF0
    u.mem_write(DONE, b"\x4e\x71")
    u.reg_write(UC_M68K_REG_A7, STACK - 4)
    u.mem_write(STACK - 4, DONE.to_bytes(4, "big"))
    trace = []
    from unicorn import UC_HOOK_CODE
    h = u.hook_add(UC_HOOK_CODE, lambda uc, pc, size, _d: trace.append(pc), begin=0x4000F938, end=0x4000F938)
    u.emu_start(sym["hk_boot"], DONE, count=200000)
    u.hook_del(h)
    check(u.reg_read(UC_M68K_REG_PC) == DONE and u.reg_read(UC_M68K_REG_A7) == STACK
          and trace == [0x4000F938],
          "boot: the stock call made once, and the boot resumes after it")
    check(rd(sym["pt_copy_target"]) == 0x41234560 and rd(sym["pt_init_target"]) == 0x41234570,
          "boot: PARTS's copy and init targets published")
    del UC_M68K_REG_D0, UC_M68K_REG_A6


def installed(name):
    img_path = ROOT / "out/mainos_bus.bin"
    raw = ROOT / "out/raw/section_3_MAIN_OS.bin"
    if not raw.exists():
        print("  [SKIP] installed: no out/raw/section_3_MAIN_OS.bin")
        return
    stock = raw.read_bytes()
    rd = lambda b, a: int.from_bytes(b[a - BASE_IMG:a - BASE_IMG + 4], "big")   # noqa: E731
    keys = DECL["KEYS_STOCK"]
    got = [(stock[keys + i * 0x1A - BASE_IMG], rd(stock, keys + i * 0x1A + 2), rd(stock, keys + i * 0x1A + 6))
           for i in range(len(DECL["STOCK_KEYS"]))]
    check(got == list(DECL["STOCK_KEYS"]) and stock[keys + 6 * 0x1A - BASE_IMG] == 0xFF,
          "stock's six [TRACK]-layer records are the ones HOOKS copies")
    check(rd(stock, DECL["KEYS_FIELD"]) == keys, "stock's keys field points at them")
    sel = {m.key: m for m in registry.selected(registry.remix(name))}
    if "HOOKS" not in sel or not img_path.exists():
        print(f"  [SKIP] installed: remix {name} carries no HOOKS or is not built")
        return
    img = img_path.read_bytes()
    # The image on disk is whatever built last (TRAPS.md, "The boot verifier
    # booted the wrong image"): build_bus's sidecar names the remix and hash.
    side = img_path.with_suffix(".remix")
    parts = side.read_text().split() if side.exists() else []
    if parts != [name, hashlib.sha256(img).hexdigest()]:
        print(f"  [SKIP] installed: out/mainos_bus.bin is not remix {name}'s build "
              f"({parts[0] if parts else 'no sidecar'}); make bus REMIX={name} first")
        return
    nm = subprocess.check_output(["m68k-elf-nm", str(ROOT / "out/platform/runtime/runtime.elf")], text=True)
    sym = {f[2]: int(f[0], 16) for line in nm.splitlines() if len(f := line.split()) == 3}
    h = sel["HOOKS"]
    for d in h.detours:
        op = {"jmp": b"\x4e\xf9", "jsr": b"\x4e\xb9"}[d.kind]
        check(img[d.site - BASE_IMG:d.site - BASE_IMG + 6] == op + sym[d.symbol].to_bytes(4, "big"),
              f"0x{d.site:08x}: {d.kind} {d.symbol} (no participant's detour)")
    for r in h.symbol_refs:
        check(rd(img, r.addr) == sym[r.symbol], f"0x{r.addr:08x}: -> {r.symbol} (not MORPH's copy)")
    # Each chain's calls, decoded from the linked runtime: every participant
    # in order, at its real address (a ROM-placed one from its unit's ELF),
    # none at 0 (an unresolved defsym).
    elf = ROOT / "out/platform/runtime/runtime.elf"
    hdr = subprocess.check_output(["m68k-elf-objdump", "-h", str(elf)], text=True)
    base = min(int(f[3], 16) for line in hdr.splitlines() if len(f := line.split()) > 6
               and f[1] == ".text")
    rt = (ROOT / "out/platform/runtime/runtime.bin").read_bytes()
    rom = {}
    for key in ("BOOT TRACE", "PARTS"):
        if key in sel:
            for u in sel[key].linked:
                ue = ROOT / "out/linked" / sel[key].name / u.label / "u.elf"
                if not u.dram and ue.exists():
                    out = subprocess.check_output(["m68k-elf-nm", str(ue)], text=True)
                    rom.update({f[2]: int(f[0], 16) for line in out.splitlines() if len(f := line.split()) == 3})
    stubs = {"status_icon": ("hk_status_icon", 0), "frame_tail": ("hk_frame_tail", 0),
             "frame_entry": ("hk_frame_entry", 8), "boot": ("hk_boot", 0)}
    on = DECL["bridged"](set(sel))
    for b, (stub, skip) in stubs.items():
        if b not in on:
            continue
        at = sym[stub] - base + skip
        calls = []
        ops = (b"\x4e\xb9", b"\x4e\xf9") if b == "boot" else (b"\x4e\xb9",)   # boot's last is a jmp
        while rt[at:at + 2] in ops:
            calls.append(int.from_bytes(rt[at + 2:at + 6], "big"))
            at += 6
        want = [sym.get(s, rom.get(s)) for k, s in DECL["BRIDGES"][b] if k in sel]
        check(calls == want and all(want),
              f"{stub}: calls {', '.join(s for k, s in DECL['BRIDGES'][b] if k in sel)} at their addresses")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "hooks"
    print("verify_hooks: selection")
    selection()
    print("verify_hooks: behaviour under Unicorn")
    behaviour()
    print("verify_hooks: frame interrupt and boot chains under Unicorn")
    frames()
    print(f"verify_hooks: installed ({name})")
    installed(name)
    print(f"verify_hooks: {'all passed' if not fails else f'{fails} failed'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
