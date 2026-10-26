#!/usr/bin/env python3
"""LOAD METER's figures over USB under the ColdFire port: the vendor request
0xc0/0x57 (modules/usb/usbaudio.s) returns lm_stats, lm_dsp and lm_ot as the
meter holds them.

Boots out/mainos_bus.bin with both DSP cores and the frame interrupt
(`--dsp --frame`, no project), enumerates over the scripted host and reads
the three blocks twice, a second of port time apart. Checks:

  blocks     wValue 0, 1, 2 read whole through wIndex offsets (20, 48 and 256 bytes); no reply is a
             multiple of 64 bytes; an offset at the end and wValue 3 STALL
  match      lm_stats read over USB equals the same words peeked from DRAM at
             the symbol's address (runtime.elf), so the request points at the
             meter's cells and not at a neighbour
  advance    lm_stats seq and lm_dsp seq rise between the reads
  window     lm_stats window is 0.5 s of DMA timer 3 (66,000,000 counts) within 2%
  isr        sum <= window, 0 < longest <= window, count > 0
  dsp        both cores' period between 20,000 and 60,000 counts and busy <=
             period, no more than a few bad records
  slots      lm_ot has samples in at least one slot, each with last <= max

SKIPs when the remix has no USB or no LOAD METER, or the port is not built.
What it cannot see: the unit's timers (the port's timer 0 moves in
1,024-count steps and prices each instruction at one step), a project
playing, and the host stack of a real machine; see tools/hw/load_meter.py.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1])); import toolpath  # noqa: E402,F401
sys.path.insert(0, str(ROOT / "tools/hw"))
import load_meter  # noqa: E402
import usb_host  # noqa: E402  (tools/harness)

from remix import registry  # noqa: E402

EMU = ROOT / "out/emu/ot_emu"
IMAGE = ROOT / "out/mainos_bus.bin"
ELF = ROOT / "out/platform/runtime/runtime.elf"


def symbol(name):
    nm = shutil.which("m68k-elf-nm") or shutil.which("m68k-linux-gnu-nm")
    for line in subprocess.run([nm, str(ELF)], capture_output=True, text=True).stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    raise RuntimeError(f"{name} not in {ELF}")


def main():
    if not EMU.is_file():
        print("  [SKIP] verify_usb_load_meter: the port is not built (make emu-cf)")
        return 0
    if not IMAGE.is_file():
        print("  [FAIL] verify_usb_load_meter: no out/mainos_bus.bin (make bus)")
        return 1
    mods = registry.remix(os.environ.get("REMIX")).modules
    if "USB" not in mods or "LOAD METER" not in mods:
        print("  [SKIP] verify_usb_load_meter: the remix has no USB or no LOAD METER")
        return 0
    sock = f"/tmp/ot-usblm-{os.getpid()}.sock"
    emu = subprocess.Popen([str(EMU), "--image", str(IMAGE), "--interactive", "--usb-host", sock,
                            "--main-level", "off", "--dsp", "--frame"],
                           cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, bufsize=1)
    fails = []

    def check(what, ok, detail=""):
        print(f"  [{'PASS' if ok else 'FAIL'}] {what}{'  ' + detail if detail else ''}")
        if not ok:
            fails.append(what)

    def reply():
        while True:
            line = emu.stdout.readline()
            if not line:
                raise RuntimeError("the port exited")
            if line.startswith(("ready", "ok", "err", "peek", "status")):
                return line.split()

    def cmd(c):
        emu.stdin.write(c + "\n")
        emu.stdin.flush()
        r = reply()
        if r[0] == "err":
            raise RuntimeError(f"{c}: {' '.join(r)}")
        return r

    def serve(fn):
        """Run a bench call on a thread while the port runs, as the enumeration does."""
        out = {}

        def t():
            try:
                out["v"] = fn()
            except Exception as e:  # noqa: BLE001
                out["e"] = e
        th = threading.Thread(target=t)
        th.start()
        while th.is_alive():
            cmd("run 20")
            th.join(0.01)
        if "e" in out:
            raise out["e"]
        return out["v"]

    def ctrl_for(b):
        return lambda w, off, n: bytes(serve(lambda: b.ctrl_in(0xc0, 0x57, w, off, n)))

    def blocks(b):
        c = ctrl_for(b)
        return [load_meter.read_block(c, w, n) for w, n in ((0, 20), (1, 48), (2, 256))]

    b = None
    try:
        reply()
        cmd("run 3000")
        res = {}

        def bench():
            res["b"] = usb_host.Bench(sock, timeout=60.0)
            usb_host.enumerate_device(res["b"], hs=True)
        th = threading.Thread(target=bench)
        th.start()
        while th.is_alive():
            cmd("run 50")
            th.join(0.01)
        b = res["b"]
        cmd("run 1500")
        first = blocks(b)
        check("blocks 0, 1, 2 read whole: 20, 48 and 256 bytes", [len(x) for x in first] == [20, 48, 256],
              str([len(x) for x in first]))
        c = ctrl_for(b)
        lens = {n: len(c(2, 0, n)) for n in (64, 128, 192, 256, 255, 100)}
        check("no reply is a multiple of 64 bytes (the next control request would return 0 bytes)",
              all(v % 64 for v in lens.values()) and lens[256] == 255 and lens[100] == 100, str(lens))
        check("wIndex resumes: the byte after a 255-byte reply is the block's last",
              c(2, 255, 1) == first[2][255:], f"{c(2, 255, 1).hex()} vs {first[2][255:].hex()}")
        try:
            c(0, 20, 4)
            check("an offset at the block's end STALLs", False, "a reply came back")
        except Exception as e:  # noqa: BLE001
            check("an offset at the block's end STALLs", True, type(e).__name__)
        try:
            serve(lambda: b.ctrl_in(0xc0, 0x57, 3, 0, 4))
            check("wValue 3 STALLs", False, "a reply came back")
        except Exception as e:  # noqa: BLE001
            check("wValue 3 STALLs", True, type(e).__name__)
        cmd("run 1000")
        second = blocks(b)
        a, c = load_meter.decode(*first), load_meter.decode(*second)

        stats_addr = symbol("lm_stats")
        peeked = bytes.fromhex("".join(cmd(f"peek {stats_addr + 4 * i:#x} 4")[1] for i in range(5)))
        # the unit moves on between the request and the peek: only seq may differ, and by one window at most
        sp, ss = load_meter.decode(peeked, first[1], first[2])["cf"], a["cf"]
        check("lm_stats over USB is the cell at lm_stats", 0 <= sp["seq"] - c["cf"]["seq"] <= 3 and
              abs(sp["window"] - ss["window"]) <= 0.02 * ss["window"], f"seq usb {c['cf']['seq']}, dram {sp['seq']}")
        check("lm_stats and lm_dsp seq rise between the reads",
              c["cf"]["seq"] > a["cf"]["seq"] and c["dsp"]["seq"] > a["dsp"]["seq"],
              f"stats {a['cf']['seq']} -> {c['cf']['seq']}, dsp {a['dsp']['seq']} -> {c['dsp']['seq']}")
        cf = c["cf"]
        check(f"window is 0.5 s of timer 3: {cf['window']}", abs(cf["window"] - 66_000_000) <= 0.02 * 66_000_000)
        check(f"isr: sum {cf['sum']} <= window, longest {cf['longest']}, count {cf['count']}",
              cf["sum"] <= cf["window"] and 0 < cf["longest"] <= cf["window"] and cf["count"] > 0)
        d = c["dsp"]
        ok = all(20000 <= d[k]["period"] <= 60000 and d[k]["busy"] <= d[k]["period"] for k in ("core0", "core1"))
        check(f"dsp: core 0 {d['core0']['busy']}/{d['core0']['period']}, core 1 {d['core1']['busy']}/{d['core1']['period']}; "
              f"bad {d['bad']} of {d['seq'] + d['bad']}", ok and d["bad"] <= 4 + d["seq"] // 100)
        live = [s for s in c["slots"] if s["count"]]
        check(f"lm_ot: {len(live)} slots sampled", bool(live) and all(s["last"] <= s["max"] for s in live))
    except Exception as e:  # noqa: BLE001 -- a hang or a stall is the finding
        check(f"the probe completed ({type(e).__name__}: {e})", False)
    finally:
        if b is not None:
            b.sock.close()
        try:
            cmd("quit")
            emu.wait(timeout=30)
        except Exception:  # noqa: BLE001
            emu.kill()
    print(f"verify_usb_load_meter: {'OK' if not fails else str(len(fails)) + ' FAILED'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
