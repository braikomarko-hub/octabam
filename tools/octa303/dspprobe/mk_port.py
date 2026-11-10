import pathlib, re, shlex, subprocess, sys
ROOT = pathlib.Path('/home/claude/octabam/.claude/worktrees/acidtrack13')
sys.path.insert(0, str(ROOT / 'tools/emu'))
import port_store
out = pathlib.Path('/home/claude/tc/probeport')
source = (ROOT / 'tools/emu/ot_emu/dsp.cpp').read_text()
marker = 'void DspPair::instrumentBefore(Core& c, const int i, const uint32_t pc)\n\t{'
assert source.count(marker) == 1
probe = r'''
        if(pc == 0x39c || pc == 0x426 || pc == 0x1a2 || pc == 0x221) {
            static FILE* output = std::fopen(std::getenv("O3_DSP_TRACE"), "w");
            static unsigned long lines = 0;
            if(output && lines++ < 400000) {
                const unsigned rec = c.mem->get(dsp56k::MemArea_X, 0x209) & 0xffffff;
                std::fprintf(output, "%d %x %llu %06x %06x |", i, pc, static_cast<unsigned long long>(c.executed),
                             c.mem->get(dsp56k::MemArea_X, 0x418) & 0xffffff, rec);
                if(pc == 0x39c || pc == 0x1a2)
                    for(unsigned k = 0; k < 80; ++k) std::fprintf(output, " %06x", c.mem->get(dsp56k::MemArea_X, rec + k) & 0xffffff);
                else
                    for(unsigned k = 0; k < 32; ++k) std::fprintf(output, " %06x", c.mem->get(dsp56k::MemArea_X, k) & 0xffffff);
                std::fputc('\n', output);
            }
        }
'''
src = out / 'dsp.cpp'
src.write_text('#include <cstdlib>\n' + source.replace(marker, marker + probe))
builddir = port_store.ensure_tree(ROOT)
flags = (builddir / 'CMakeFiles/ot_emu.dir/flags.make').read_text()
args = []
for name in ('CXX_DEFINES', 'CXX_INCLUDES', 'CXX_FLAGS'):
    args += shlex.split(re.search(r'^' + name + r' = (.*)$', flags, re.M)[1])
link = shlex.split((builddir / 'CMakeFiles/ot_emu.dir/link.txt').read_text())
tail = link[link.index('CMakeFiles/ot_emu.dir/main.cpp.o'):]
exe = out / 'ot_emu'
tail[tail.index('-o') + 1] = str(exe)
r = subprocess.run([link[0], *args, str(src), *tail], cwd=builddir, capture_output=True, text=True)
print(r.returncode, r.stderr[-2000:])
