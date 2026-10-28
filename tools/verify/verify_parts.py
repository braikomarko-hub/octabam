#!/usr/bin/env python3
"""PARTS (modules/parts): the generic Part API, its notifications, its window,
and its installed sites. MIDI PART STATE's API (mp_*), which PARTS carries, is
checked by that module's own gates (verify_midi_part, verify_midi_part_copy),
run by MIDI LOOPBACK.

1. Registration: the snapshot window spans every present client's windows;
   a writable byte outside every window, a window outside a Part and a
   malformed registration are refused; no client, no code or site.
2. Under Unicorn, parts.s assembled with two synthetic clients (windows at
   0x100 and 0x4e2, one writing two bytes, one notified of replacements
   only, the other of both): pt_read and pt_write accept exactly the
   declared bytes, keep every register but d0, and write the working byte,
   the per-Part and bank dirty bits and -- for the UI's bank only -- the
   battery-backed mirror; pt_read serves the snapshot while a Part is being
   replaced; a native initialization and a partial native copy snapshot the
   whole window of each affected Part before the bytes change, notify
   `before` (the working Part, its context) and `replaced` (the context) in
   registration order, advance exactly the affected epochs, and clear the
   snapshot; a handler that clobbers every register changes nothing for the
   caller. Without a MIDI client the mp_* names are absent.
3. Installed (stage image, the remix's own build): the three sites jump into
   the resident entry unit, and pt_resident_activate publishes the runtime's
   wrappers and makes the stock call, returning to the boot.
"""
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import toolpath  # noqa: E402,F401
from remix import registry  # noqa: E402

DECL = runpy.run_path(str(ROOT / "modules/parts/manifest.py"))
fails = 0
B, BS, PS, WORK = 0x400E21E0, 0x9B340, 0x18B2, 0x8ED80


def check(ok, what):
    global fails
    print(f"  [{'PASS' if ok else 'FAIL'}] {what}")
    if not ok:
        fails += 1


SYNTH = (
    ("ALPHA", "al", ("before", "replaced"), ((0x100, 8),), (0x100, 0x101), False),
    ("BETA", "be", ("replaced",), ((0x4E2, 4),), (), False),
)


def _with(clients, fn, *a):
    g = DECL["window"].__globals__
    saved = g["CLIENTS"]
    g["CLIENTS"] = clients
    try:
        return fn(*a)
    finally:
        g["CLIENTS"] = saved


def registration():
    check(DECL["window"]({"MIDI LOOPBACK"}) == (0x4E2, 288), "MIDI LOOPBACK alone: MIDI PART STATE's 288-byte window at 0x4e2")
    check(_with(SYNTH, DECL["window"], {"ALPHA", "BETA"}) == (0x100, 0x3E8),
          "two clients: the window spans both (0x100..0x4e6, a multiple of 4)")
    check(_with(SYNTH, DECL["window"], {"ALPHA"}) == (0x100, 8), "one present client: its window only")
    cases = [
        ([("A", None, (), ((0x100, 2),), (0x200,), False)], "a writable byte outside every window"),
        ([("A", None, (), ((0x18B0, 4),), (), False)], "a window past the Part's end"),
        ([("A", None, ("typo",), (), (), False)], "an unknown event"),
        ([("A", None, ("before",), (), (), False)], "an event with no handler prefix"),
    ]
    for bad, why in cases:
        try:
            _with(bad, DECL["parts_inc"], {"A"})
            check(False, f"refused: {why}")
        except ValueError:
            check(True, f"refused: {why}")
    check(DECL["select"](set()) == {"linked": (), "detours": (), "pokes": (), "claims": None},
          "no client: no unit, site, poke or claim")


def _assemble(work, clients, keys, extra=""):
    inc = _with(clients, DECL["parts_inc"], keys) + extra
    (work / "remix.inc").write_text(inc)
    subprocess.run(["m68k-elf-as", "-mcpu=54455", "-I", str(work), "-I", str(ROOT), "-o", str(work / "p.o"),
                    str(ROOT / "modules/parts/parts.s")], check=True, capture_output=True)
    subprocess.run(["m68k-elf-ld", "-Ttext=0x41000000", "--unresolved-symbols=ignore-all",
                    "-o", str(work / "p.elf"), str(work / "p.o")], check=True, capture_output=True)
    subprocess.run(["m68k-elf-objcopy", "-O", "binary", str(work / "p.elf"), str(work / "p.bin")], check=True)
    nm = subprocess.check_output(["m68k-elf-nm", str(work / "p.elf")], text=True)
    return (work / "p.bin").read_bytes(), {f[2]: int(f[0], 16) for line in nm.splitlines()
                                            if len(f := line.split()) == 3}


def behaviour():
    from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, UC_HOOK_CODE
    from unicorn import m68k_const as mc
    handlers = {0x47002000 + 16 * i: n for i, n in enumerate(("al_pt_before", "al_pt_replaced", "be_pt_replaced"))}
    extra = "".join(f".set {n}, 0x{a:x}\n" for a, n in handlers.items())
    with tempfile.TemporaryDirectory(prefix="octabam-parts-") as td:
        rt, sym = _assemble(Path(td), SYNTH, {"ALPHA", "BETA"}, extra)
        rt0, sym0 = _assemble(Path(td), SYNTH, {"ALPHA"}, extra)
    check(not any(n.startswith("mp_") for n in sym), "no MIDI client: no mp_* names")
    regs = [getattr(mc, f"UC_M68K_REG_D{i}") for i in range(8)] + [getattr(mc, f"UC_M68K_REG_A{i}") for i in range(7)]
    u = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    u.ctl_set_cpu_model(UC_CPU := mc.UC_CPU_M68K_CFV4E)
    del UC_CPU
    for a, n in ((0x10000000, 0x200000), (0x40000000, 0x08000000)):
        u.mem_map(a, n)
    u.mem_write(0x41000000, rt)
    STACK, DONE, EPI = 0x47008000, 0x4700FFF0, 0x4700FF00
    u.mem_write(DONE, b"\x4e\x71")
    # stock Part initialization's body, after the 8 bytes its gate replays:
    # here an epilogue (movem.l (%sp),%d2-%d7/%a2-%a6 ; lea 88(%sp),%sp ; rts)
    u.mem_write(EPI, bytes.fromhex("4cd77cfc4fef00584e75"))
    log, new_bytes = [], {}
    rd = lambda a, n=4: int.from_bytes(u.mem_read(a, n), "big")   # noqa: E731

    def hook(uc, pc, size, _d):
        if pc in handlers:
            log.append((handlers[pc], uc.reg_read(regs[0]), uc.reg_read(regs[1]),
                        rd(sym["pt_snapshot_bank"]), bytes(uc.mem_read(sym["pt_snapshot"], 4 * 0x3E8))))
            for r in regs:
                uc.reg_write(r, 0xDEAD0000)           # a handler may clobber everything
            sp = uc.reg_read(mc.UC_M68K_REG_A7)
            uc.reg_write(mc.UC_M68K_REG_PC, rd(sp))
            uc.reg_write(mc.UC_M68K_REG_A7, sp + 4)
        elif pc == 0x40005640:                        # stock init: the new bytes, then its epilogue
            for a, v in new_bytes.items():
                uc.mem_write(a, v)
            uc.reg_write(mc.UC_M68K_REG_PC, EPI)
        elif pc == 0x4002089E:                        # stock memcpy after its displaced push
            sp = uc.reg_read(mc.UC_M68K_REG_A7)
            dst, src, n = rd(sp + 8), rd(sp + 12), rd(sp + 16)
            uc.mem_write(dst, bytes(uc.mem_read(src, n)))
            uc.reg_write(regs[2], rd(sp))             # move.l (%sp)+,%d2 ; rts
            uc.reg_write(mc.UC_M68K_REG_A7, sp + 8)
            uc.reg_write(mc.UC_M68K_REG_PC, rd(sp + 4))
    u.hook_add(UC_HOOK_CODE, hook)

    def call(name, *args, sp_args=()):
        vals = [0x1000 + i for i in range(15)]
        for r, v in zip(regs, vals):
            u.reg_write(r, v)
        for r, v in zip(regs, args):
            u.reg_write(r, v)
        sp = STACK - 4 - 4 * len(sp_args)
        u.mem_write(sp, DONE.to_bytes(4, "big") + b"".join(v.to_bytes(4, "big") for v in sp_args))
        u.reg_write(mc.UC_M68K_REG_SR, 0x2000)          # supervisor (its own A7), interrupts open
        u.reg_write(mc.UC_M68K_REG_A7, sp)
        u.emu_start(sym[name], DONE, count=200000)
        out = [u.reg_read(r) for r in regs]
        kept = all(out[i] == (args[i] if i < len(args) else vals[i]) for i in range(1, 15))
        # the caller pops the stack arguments: sp returns just above them
        return out[0], kept, u.reg_read(mc.UC_M68K_REG_A7) == STACK - 4 * len(sp_args)

    def part(ctx):
        return B + (ctx >> 2) * BS + WORK + (ctx & 3) * PS

    # ---- reads and writes
    ctx, other = 2 * 4 + 1, 5 * 4 + 3
    u.mem_write(0x46C82456, (B + 2 * BS).to_bytes(4, "big"))     # the UI's bank: 2
    u.mem_write(part(ctx) + 0x100, b"\x11\x22")
    v, kept, sp = call("pt_read", ctx, 0x101)
    check(v == 0x22 and kept and sp, "pt_read: a declared byte, every register but d0 kept")
    check(all(call("pt_read", c, o)[0] == 0xFFFFFFFF for c, o in ((ctx, 0x108), (ctx, 0x200), (64, 0x100), (ctx, PS))),
          "pt_read: -1 outside the windows, past the Part, or for context 64")
    v, kept, sp = call("pt_write", ctx, 0x101, 0x5A)
    cs1 = 0x100A4ECE + (ctx & 3) * PS + 0x101
    check(v == 1 and kept and rd(part(ctx) + 0x101, 1) == 0x5A and rd(B + 2 * BS + 0x95048, 1) & 2
          and rd(B + 2 * BS + 0x9B332) == 1 and rd(cs1, 1) == 0x5A and rd(0x100B145E, 1) & 2
          and rd(0x100F8598) == 1, "pt_write (UI's bank): byte, Part and bank dirty bits, battery mirror and its flags")
    v, kept, _ = call("pt_write", other, 0x100, 0x33)
    check(v == 1 and rd(part(other) + 0x100, 1) == 0x33 and rd(0x100A4ECE + 3 * PS + 0x100, 1) == 0
          and rd(B + 5 * BS + 0x95048, 1) & 8, "pt_write (another bank): its byte and dirty bits, no mirror write")
    before = bytes(u.mem_read(part(ctx), PS))
    check(all(call("pt_write", ctx, o, 1)[0] == 0 for o in (0x102, 0x4E2, 0x200)) and call("pt_write", ctx, 0x100, 256)[0] == 0
          and bytes(u.mem_read(part(ctx), PS)) == before, "pt_write: 0 and nothing written outside the declared bytes or past 255")
    # ---- the snapshot serves reads while a Part is replaced
    snap = sym["pt_snapshot"]
    u.mem_write(sym["pt_snapshot_bank"], (B + 2 * BS).to_bytes(4, "big"))
    u.mem_write(sym["pt_snapshot_parts"], (1 << 1).to_bytes(4, "big"))
    u.mem_write(snap + 1 * 0x3E8 + 1, b"\x77")
    check(call("pt_read", ctx, 0x101)[0] == 0x77 and call("pt_read", ctx - 1, 0x100)[0] == 0,
          "pt_read during a replacement: the outgoing byte from the snapshot, other Parts native")
    u.mem_write(sym["pt_snapshot_bank"], bytes(8))
    # ---- a native initialization of one Part
    ctx = 3 * 4 + 2
    u.mem_write(part(ctx) + 0x100, bytes(range(1, 9)))
    u.mem_write(part(ctx) + 0x4E2, b"\xaa\xbb\xcc\xdd")
    new_bytes = {part(ctx) + 0x100: bytes(8), part(ctx) + 0x4E2: bytes(4)}
    epochs0 = bytes(u.mem_read(sym["pt_part_epochs"], 256))
    log.clear()
    v, kept, sp = call("pt_native_init", sp_args=(part(ctx),))
    names = [e[0] for e in log]
    check(names == ["al_pt_before", "al_pt_replaced", "be_pt_replaced"],
          "init: before, then replaced to each client in registration order")
    b = log[0]
    window_old = b[4][2 * 0x3E8:2 * 0x3E8 + 0x3E8]
    check(b[1] == part(ctx) and b[2] == ctx and b[3] == B + 3 * BS and window_old[:8] == bytes(range(1, 9))
          and window_old[0x3E2:0x3E6] == b"\xaa\xbb\xcc\xdd",
          "init: before gets the working Part and its context, with the whole outgoing window snapshotted")
    check(all(e[1] == ctx and e[3] == 0 for e in log[1:]), "init: replaced gets the context, after publication")
    ep = bytes(u.mem_read(sym["pt_part_epochs"], 256))
    check([i for i in range(64) if ep[4 * i:4 * i + 4] != epochs0[4 * i:4 * i + 4]] == [ctx]
          and rd(sym["pt_part_epochs"] + 4 * ctx) == int.from_bytes(epochs0[4 * ctx:4 * ctx + 4], "big") + 1,
          "init: exactly the replaced Part's epoch advanced")
    check(kept and sp and rd(sym["pt_snapshot_bank"]) == 0 and rd(sym["pt_snapshot_parts"]) == 0,
          "init: registers and stack kept through clobbering handlers; the snapshot cleared")
    # ---- a partial native copy over two Parts of one bank
    src = 0x47004000
    u.mem_write(src, bytes(range(256)) * 2)
    dst = part(4 * 7 + 1) + 0x4E2                       # Part 1's MIDI window to Part 2's start
    n = PS - 0x4E2 + 0x104
    log.clear()
    call("pt_native_copy", sp_args=(dst, src, n))
    rep = [(e[0], e[1]) for e in log if e[0].endswith("replaced")]
    check(rep == [("al_pt_replaced", 29), ("be_pt_replaced", 29), ("al_pt_replaced", 30), ("be_pt_replaced", 30)],
          "copy over Parts 1 and 2: each replaced Part notified, in Part order, to each client")
    check(bytes(u.mem_read(dst, 16)) == bytes(range(16)), "copy: the stock copy made")
    # ---- a copy that touches no working Part: no snapshot, no notification
    log.clear()
    call("pt_native_copy", sp_args=(B + 7 * BS + 0x100, src, 64))
    check(log == [], "a copy outside the working Parts: no snapshot and no notification")
    del rt0, sym0


def installed(name):
    img_path = ROOT / "out/mainos_bus.bin"
    sel = {m.key: m for m in registry.selected(registry.remix(name))}
    if "PARTS" not in sel or not img_path.exists():
        print(f"  [SKIP] installed: remix {name} carries no PARTS or is not built")
        return
    img = img_path.read_bytes()
    side = img_path.with_suffix(".remix")
    parts = side.read_text().split() if side.exists() else []
    if parts != [name, hashlib.sha256(img).hexdigest()]:
        print(f"  [SKIP] installed: out/mainos_bus.bin is not remix {name}'s build; make bus REMIX={name} first")
        return
    from unicorn import Uc, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN
    from unicorn import m68k_const as mc
    nm = lambda p: {f[2]: int(f[0], 16) for line in subprocess.check_output(["m68k-elf-nm", str(p)], text=True).splitlines()  # noqa: E731
                    if len(f := line.split()) == 3 and f[1] != "U"}
    runtime = nm(ROOT / "out/platform/runtime/runtime.elf")
    res = nm(ROOT / "out/linked/parts/partsentry/u.elf")
    layout = json.loads((ROOT / "out/platform/layout.json").read_text())
    raw = (ROOT / "out/platform/runtime/runtime.bin").read_bytes()
    BASE = 0x40000400
    hooks = {d.site: d for d in sel["PARTS"].detours}
    # a site HOOKS bridges (the boot's call, beside BOOT TRACE) holds HOOKS's
    # stub, which calls pt_resident_activate (verify_hooks checks that chain)
    bridged = {o.site for o in getattr(sel.get("HOOKS"), "overrides", ()) if o.module == "PARTS"}
    ok = True
    for site, d in hooks.items():
        target = int.from_bytes(img[site - BASE + 2:site - BASE + 6], "big")
        if site in bridged:
            ok &= target == runtime.get("hk_boot")
        else:
            ok &= target == res[d.symbol] and not layout["base"] <= target < layout["top"]
    check(ok and len(hooks) == 3, f"the three sites jump into the resident entry unit, outside the runtime"
          + (f" ({len(bridged)} through HOOKS)" if bridged else ""))
    u = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN)
    u.ctl_set_cpu_model(mc.UC_CPU_M68K_CFV4E)
    end = max(BASE + len(img), layout["top"], layout["base"] + len(raw))
    u.mem_map(0x40000000, (end - 0x40000000 + 4095) & ~4095)
    u.mem_map(0x47000000, 0x10000)
    u.mem_write(BASE, img)
    u.mem_write(layout["base"], raw)
    u.mem_write(0x47008000 - 4, (0x40000518).to_bytes(4, "big"))
    u.reg_write(mc.UC_M68K_REG_A7, 0x47008000 - 4)
    u.reg_write(mc.UC_M68K_REG_D0, 0x13579BDF)
    u.emu_start(res["pt_resident_activate"], 0x4000F938, count=50)
    rd = lambda a: int.from_bytes(u.mem_read(a, 4), "big")   # noqa: E731
    check(u.reg_read(mc.UC_M68K_REG_PC) == 0x4000F938 and u.reg_read(mc.UC_M68K_REG_D0) == 0x13579BDF
          and rd(u.reg_read(mc.UC_M68K_REG_A7)) == 0x40000518
          and rd(res["pt_copy_target"]) == runtime["pt_native_copy"]
          and rd(res["pt_init_target"]) == runtime["pt_native_init"],
          "activation: the runtime's wrappers published, d0 kept, the stock call made with the boot's return")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "midi-loopback"
    print("verify_parts: registration")
    registration()
    print("verify_parts: the API under Unicorn")
    behaviour()
    print(f"verify_parts: installed ({name})")
    installed(name)
    print(f"verify_parts: {'all passed' if not fails else f'{fails} failed'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
