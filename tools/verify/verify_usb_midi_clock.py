#!/usr/bin/env python3
"""USB-MIDI clock and transport under the ColdFire port: a 0xF8 over USB sets the
tempo as a 0xF8 on DIN does, and a START / STOP over USB drives the sequencer as on DIN.

The MIDI clock handler (0x40005a48) builds the tempo, BPM * 24 into
0x80001818 (0x80001814 every 24th tick), from the DTCN0 delta the UART0 ISR
stores at 0x46c83466 for each 0xF8 (0x4001070a). A USB 0xF8 that skips that
stamp steps the sequencer and leaves the tempo where it was.

Boots out/mainos_bus.bin with the USB device model under --interactive (time
advances only on `run`), sets CLOCK RECEIVE, and plays three runs of 48 ticks
after a START, each at a different spacing: DIN, then USB, then USB again.
The spacing is the port's sample count when each 0xF8 was handed over, over
the last 24 ticks. After each run,
0x80001818 must be within 1% of 60 * 44100 / spacing (BPM * 24). Without
the stamp both USB runs read 2400, the DIN run's tempo.

Then, with TRANSPORT RECEIVE set (0x80000029), a START, 48 clocks and a STOP
over DIN and over USB: the transport word (0x800065b8) must read 1 after the
START and not 1 after the STOP, and USB's two readings must equal DIN's.

Depends on the port counting DTCN0 at 256 fs (rtos.h; inferred from the
handler's constant). SKIPs when the remix has no USB or the port is not
built (`make emu-cf`). What this cannot see: a project's patterns playing (no project is loaded; the
transport word is the sequencer's own state), clock bytes bunched in one USB
packet (each tick here is its own transfer), and USB timing on the unit.
"""
import os
import pathlib
import subprocess
import sys
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1])); import toolpath  # noqa: E402,F401
import usb_host  # noqa: E402  (tools/harness)

from remix import registry  # noqa: E402

EMU = ROOT / "out/emu/ot_emu"
IMAGE = ROOT / "out/mainos_bus.bin"
CLOCK_RECEIVE = 0x80000028      # byte, bit 0 (the handler's gate, 0x40005a50)
TEMPO = 0x80001818              # BPM * 24, clamped 600..7320
TRANSPORT_RECEIVE = 0x80000029  # byte, nonzero: START/STOP are taken (docs/firmware/STORAGE.md)
TRANSPORT = 0x800065b8          # longword: 1 = the sequencer plays, 0 = stopped and rewound (docs/firmware/STEM_REC.md 1.7)
CLK_DT = 0x46c83466             # DTCN0 delta between the last two 0xF8
TICKS = 48
RUNS = [("DIN", 25.0), ("USB", 50.0), ("USB", 37.5)]     # ms per tick asked; the port lands them at 25.0, 50.0, 40.0 ms (100, 50, 62.5 BPM)


def main():
    if not EMU.is_file():
        print("  [SKIP] verify_usb_midi_clock: the port is not built (make emu-cf)")
        return 0
    if not IMAGE.is_file():
        print("  [FAIL] verify_usb_midi_clock: no out/mainos_bus.bin (make bus)")
        return 1
    if "USB" not in registry.remix(os.environ.get("REMIX")).modules:
        print("  [SKIP] verify_usb_midi_clock: the remix has no USB")
        return 0
    sock = f"/tmp/ot-usbclk-{os.getpid()}.sock"     # sun_path is 104 bytes on macOS
    emu = subprocess.Popen([str(EMU), "--image", str(IMAGE), "--interactive", "--usb-host", sock, "--main-level", "off"],
                           cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
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

    def run(ms):
        return float(cmd(f"run {ms}")[1].split("=")[1])

    def now():
        return float(next(f for f in cmd("status")[1:] if f.startswith("sample=")).split("=")[1])

    def peek(addr, n=4):
        return int(cmd(f"peek {addr:#x} {n}")[1], 16)

    def send(b, src, byte, ms):
        """One byte, then `ms` of port time. The USB request is in the socket
        before the run starts, so the port takes it at the run's first poll
        (every 256 instructions) as `midi` puts a DIN byte in the FIFO: both
        arrive at the sample the run starts from."""
        if src == "DIN":
            cmd(f"midi {byte:02x}")
            return run(ms)
        b.sock.sendall(f"out 2 {bytes([0x0f, byte, 0, 0]).hex()}\n".encode())
        end = run(ms)
        taken = int(b.wait("out 2", timeout=10).split()[2])
        if taken != 4:
            raise RuntimeError(f"EP2 OUT took {taken} of 4 bytes")
        return end

    b = None
    try:
        reply()
        run(3000)
        res = {}

        def bench():
            res["b"] = usb_host.Bench(sock, timeout=60.0)
            usb_host.enumerate_device(res["b"], hs=True)
        th = threading.Thread(target=bench)
        th.start()
        while th.is_alive():
            run(50)
            th.join(0.01)
        b = res["b"]
        cmd(f"poke {CLOCK_RECEIVE:#x} {peek(CLOCK_RECEIVE, 1) | 1:02x}")
        for src, ms in RUNS:
            send(b, src, 0xfa, 1)
            stamps = []
            for _ in range(TICKS):
                stamps.append(now())
                send(b, src, 0xf8, ms)
            spacing = (stamps[-1] - stamps[-25]) / 24
            want = 60 * 44100 / spacing
            got = peek(TEMPO)
            check(f"{src} clock at {spacing:.1f} samples/tick: tempo {got} (BPM*24), want {want:.0f} +-1%",
                  abs(got - want) <= 0.01 * want, f"0x46c83466 = {peek(CLK_DT)}")
            send(b, src, 0xfc, 250)    # > 1,881,600 DTCN0 counts (167 ms): the handler's resync gap (0x40005a96), so no run inherits the last one's ring
        cmd(f"poke {TRANSPORT_RECEIVE:#x} {peek(TRANSPORT_RECEIVE, 1) | 1:02x}")
        seen = {}
        for src in ("DIN", "USB"):
            send(b, src, 0xfa, 1)
            for _ in range(TICKS):
                send(b, src, 0xf8, 25.0)
            started = peek(TRANSPORT)
            send(b, src, 0xfc, 250)
            seen[src] = (started, peek(TRANSPORT))
        check(f"DIN START runs the sequencer, STOP ends it: transport {seen['DIN'][0]} then {seen['DIN'][1]}",
              seen["DIN"][0] == 1 and seen["DIN"][1] != 1)
        check(f"USB START and STOP leave the transport as DIN's: {seen['USB']} against {seen['DIN']}",
              seen["USB"] == seen["DIN"])
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
    print(f"verify_usb_midi_clock: {'OK' if not fails else str(len(fails)) + ' FAILED'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
