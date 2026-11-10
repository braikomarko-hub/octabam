import sys, pathlib, subprocess, shutil
ROOT = pathlib.Path('.').resolve()
sys.path.insert(0, str(ROOT / 'tools/octa303/v82'))
import play_gate as pg
out = pathlib.Path('/home/claude/tc/probe'); shutil.rmtree(out, ignore_errors=True); out.mkdir(parents=True)
card = pg.fixture('/mnt/user-data/uploads/OCTA303SET/OCTA303', out)
emu = sys.argv[1] if len(sys.argv) > 1 else str(ROOT.parent / 'acidtrack13/out/emu/ot_emu')
cmd = [emu, '--image', 'out/mainos_bus.bin', '--card', str(card), '--set', 'OCTABAM', '--project', 'RIG', '--sequencer',
       '--internal-clock', '--frames', '1500', '--load-ms', '90000', '--dsp', '--main-level', '64',
       '--block-dump', str(out / 'blocks.bin')] + sys.argv[2:]
with (out / 'port.log').open('w') as log:
    r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
print('exit', r.returncode)
