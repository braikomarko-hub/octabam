#!/usr/bin/env python3
"""TRACK PATTERNS gate. Reads no firmware and runs no emulator.

1. Compiles the engine and the adapter for the host and runs their tests
   (test_trackpattern.c, test_adapter.c): stock when nothing is set, a
   change landing at each track's own loop start for lengths 1-64, the way
   back to following, a global pattern change clearing every override,
   stopped changes applying at once, the look-ahead naming what then
   plays, restarts and MASTER LENGTH's repeated step, MIDI tracks, the
   popup text, a bank change, the key gesture on fake key memory.
2. With m68k-elf-gcc on the PATH, compiles the ColdFire unit, refuses any
   call outside it (generate.py) and checks trackpatterns.s is current.

What it cannot show: the detours running in the firmware (emulator or unit).
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CC = shutil.which('cc') or shutil.which('clang') or shutil.which('gcc')
FLAGS = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-O2']


def host(name, sources, defines=()):
    with tempfile.TemporaryDirectory() as td:
        exe = pathlib.Path(td) / name
        subprocess.run([CC, *FLAGS, *defines, '-o', str(exe), *sources], cwd=HERE, check=True)
        result = subprocess.run([str(exe)], capture_output=True, text=True)
        print(result.stdout.strip())
        if result.returncode:
            sys.exit(f'[FAIL] {name}')


if __name__ == '__main__':
    if not CC:
        sys.exit('[FAIL] no host C compiler')
    host('engine', ['trackpattern.c', 'test_trackpattern.c'])
    host('adapter', ['trackpattern.c', 'adapter.c', 'test_adapter.c'], ['-DTP_HOST'])
    if shutil.which('m68k-elf-gcc'):
        mode = '--check' if (HERE / 'trackpatterns.s').exists() else '--dry'
        if subprocess.run([sys.executable, 'generate.py', mode], cwd=HERE).returncode:
            sys.exit('[FAIL] ColdFire unit (see the message above)')
        if mode == '--dry':
            print('[NOTE] trackpatterns.s not generated yet: run python3 generate.py')
    else:
        print('[SKIP] m68k-elf-gcc not on PATH: ColdFire compile not checked')
    print('[PASS] TRACK PATTERNS ' + ('engine, glue and ColdFire unit' if shutil.which('m68k-elf-gcc')
                                      else 'engine and glue (host only)') + ' -- emulator and one MKII (OCTABAM3); instruction counts in README "Cost", chip cycles not measured')
