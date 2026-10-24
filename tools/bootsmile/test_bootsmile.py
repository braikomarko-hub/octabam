#!/usr/bin/env python3
"""test_bootsmile: modules/bootsmile/bootsmile.s run from its source text in tools/octa303/sim/cfsim.py.

The boot logo loop is a mock: DTCN3 is set to a moment, bs_blit is called as the loop calls the
stock blit (logo record, then a star), and the screen surface's bits are read back through
tools/emu/lcd_view.pixels. Proves: the right frame for every 50 ms slot (against the generator's
own frames), the stars dropped, black after the end and in the black slots, d2-d7/a2-a6 kept, the
generated file up to date, and cfsim's ColdFire lint. Cannot prove: the hook site, the flush, the
real clock rate -- the port's boot (make check) and the unit decide those."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'octa303', 'sim'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'emu'))
sys.path.insert(0, HERE)
from cfsim import CPU, Mem
import gen_bootsmile as g, lcd_view

fails = 0
def check(name, ok, info=''):
    global fails
    print(('PASS  ' if ok else 'FAIL  ') + name + (('   [' + str(info) + ']') if info else ''))
    if not ok: fails += 1

SRC = open(os.path.join(ROOT, 'modules', 'bootsmile', 'bootsmile.s')).read()
fr, slots = g.frames()
planes = [g.plane(f) for f in fr]
check('generated_file_matches_generator', all(f"0x{int.from_bytes(planes[-1][j:j+4],'big'):08x}" in SRC
                                              for j in range(0, 1024, 4)) and f"NSLOTS,   {len(slots)}" in SRC)
mem = Mem(); cpu = CPU(SRC, mem)
check('cfsim_lint_and_load', True, '%d instructions' % len(cpu.prog))
SURF, BITS, SP, DTCN3, LOGO, STAR = 0x400bf10a, 0x46c7e0ea, 0x47000000, 0xfc07c00c, 0x400ba8b2, 0x400c1094
for i, v in enumerate((128, 64, 2, BITS, 0x46c7ca38)): mem.w(SURF + 4 * i, 'l', v)
def clear():
    for i in range(1024): mem.w(BITS + i, 'b', 0)
def blit(img):
    for i, v in enumerate((img, SURF, 8, 10)): mem.w(SP - 16 + 4 * i, 'l', v)
    for i in range(2, 8): cpu.d[i] = 0x5a5a0000 + i
    for i in range(2, 7): cpu.a[i] = 0x6b6b0000 + i
    cpu.a[7] = SP - 16; cpu.call('bs_blit')
    return all(cpu.d[i] == 0x5a5a0000 + i for i in range(2, 8)) and all(cpu.a[i] == 0x6b6b0000 + i for i in range(2, 7))
def shown(): return bytes(mem.r(BITS + i, 'b') for i in range(1024))
ok_regs, bad = True, []
for s, f in enumerate(slots):
    for off_ms in (0, 49):
        clear(); mem.w(DTCN3, 'l', (s * 50 + off_ms) * 132000)
        ok_regs &= blit(LOGO)
        want = planes[f] if f is not None else bytes(1024)
        if shown() != want: bad.append((s, off_ms))
check('every_slot_shows_its_frame', not bad, bad[:5])
check('registers_kept', ok_regs)
clear(); mem.w(DTCN3, 'l', 30 * 50 * 132000); blit(STAR)
check('stars_dropped', shown() == bytes(1024))
for ms in (len(slots) * 50, 3_900, 30_000):
    clear(); mem.w(DTCN3, 'l', ms * 132000); blit(LOGO)
    check(f'black_after_the_end_{ms}ms', shown() == bytes(1024))
mid = slots[len(slots) // 3]
rows = lcd_view.pixels(planes[mid])
check('the_full_smile_is_centred', rows[32 - 26][64] == 1 and rows[32 + 26][64] == 1 and rows[32][64] == 0)
check('the_loop_limit_covers_the_animation', len(slots) * 50 <= g.TOTAL_MS and g.TOTAL_MS // 5 == 760)
print(f"\n{'ALL PASS' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
