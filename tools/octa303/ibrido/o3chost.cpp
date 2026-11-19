// o3chost -- coordination, 19 Nov 2026 (code written by Claude): runs gen_o3c.py's chain on the vendored dsp56300
// emulator core, piece by piece, with its own blocks (nothing of the stock payload).
//   o3chost blob.bin org entry ytab.bin in.bin out.bin dis.txt
// in.bin, per piece: int32 n (1..16), int32 u[16], int32 ctl[10].  out.bin, per piece: int32 v[16], int32 instructions.
// ytab.bin: int32 words at Y:0x800.  The voice's state block starts dirty (0x555555) and init is the first piece's
// job? No: the chain has no init; the bench zeroes the state block once, as a new voice (ref303's Track()).
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "dsp56kEmu/dsp.h"
#include "dsp56kEmu/memory.h"
#include "dsp56kEmu/peripherals.h"
#include "dsp56kEmu/disasm.h"
#include "dsp56kEmu/opcodes.h"
using namespace dsp56k;
class AllowAll : public IMemoryValidator { public: bool memValidateAccess(EMemArea, TWord, bool) const override { return true; } };
static const TWord SENTINEL = 0x03f000, AUDIO = 0x5000, CTL = 0x5100, STATE = 0x4000;
static void scramble(DSP& dsp) {
    static uint32_t z = 0x2545f491;
    auto nx = [&]() { z ^= z << 13; z ^= z >> 17; z ^= z << 5; return (TWord)(z & 0xffffff); };
    for (int q = 1; q <= 5; ++q) { dsp.regs().r[q].var = nx(); dsp.regs().n[q].var = nx(); dsp.regs().m[q].var = 0x00000f; }
    dsp.regs().x.var = ((uint64_t)nx() << 24) | nx(); dsp.regs().y.var = ((uint64_t)nx() << 24) | nx();
    dsp.regs().a.var = ((uint64_t)nx() << 24) | nx(); dsp.regs().b.var = ((uint64_t)nx() << 24) | nx();
}
static bool runToRts(DSP& dsp, TWord pc, uint64_t& n) {
    dsp.setPC(SENTINEL); dsp.jsr(pc);
    const uint64_t i0 = dsp.getInstructionCounter();
    for (uint32_t i = 0; i < 5000000; ++i) {
        if (dsp.getPC().toWord() == SENTINEL) { n = dsp.getInstructionCounter() - i0; return true; }
        dsp.execInterpreter();
    }
    return false;
}
static std::vector<uint8_t> slurp(const char* p) { std::vector<uint8_t> v; FILE* f = fopen(p, "rb"); if (!f) { perror(p); exit(2); }
    int c; while ((c = fgetc(f)) != EOF) v.push_back((uint8_t)c); fclose(f); return v; }
int main(int argc, char** argv) {
    if (argc != 8) { fprintf(stderr, "usage: o3chost blob org entry ytab in out dis\n"); return 2; }
    AllowAll val; Memory mem(val, 0x080000, 0x800000, 0x200000);
    Peripherals56362 px; Peripherals56367 py; DSP dsp(mem, &px, &py);
    const TWord org = strtoul(argv[2], 0, 16), entry = strtoul(argv[3], 0, 16);
    auto b = slurp(argv[1]); std::vector<uint32_t> prog;
    for (size_t i = 0; i + 2 < b.size(); i += 3) { TWord w = b[i] | (b[i + 1] << 8) | (b[i + 2] << 16); dsp.memWriteP(org + (TWord)(i / 3), w); prog.push_back(w); }
    dsp.memWriteP(SENTINEL, 0);
    { Opcodes ops; Disassembler d(ops); std::string s; d.disassembleMemoryBlock(s, prog, org, false, true, true);
      FILE* fd = fopen(argv[7], "w"); fputs(s.c_str(), fd); fclose(fd); }
    auto y = slurp(argv[4]);
    for (size_t i = 0; i + 3 < y.size(); i += 4) { int32_t w; memcpy(&w, &y[i], 4); dsp.memWrite(MemArea_Y, 0x800 + (TWord)(i / 4), (TWord)w & 0xffffff); }
    for (TWord k = 0; k < 0x20; ++k) dsp.memWrite(MemArea_X, STATE + k, 0);
    for (int k = 0; k < 8; ++k) dsp.regs().m[k].var = 0xffffff;
    auto in = slurp(argv[5]); FILE* fo = fopen(argv[6], "wb");
    const size_t PC = 27 * 4; uint64_t mx = 0, tot = 0, ns = 0; size_t over = 0;
    for (size_t o = 0; o + PC <= in.size(); o += PC) {
        int32_t w[27]; memcpy(w, &in[o], PC);
        const int n = w[0] & 0xff;
        if (w[0] & 0x100) for (TWord k = 0; k < 0x20; ++k) dsp.memWrite(MemArea_X, STATE + k, 0);   // a new voice
        for (int k = 0; k < 16; ++k) dsp.memWrite(MemArea_X, AUDIO + k, (TWord)w[1 + k] & 0xffffff);
        for (int k = 0; k < 10; ++k) dsp.memWrite(MemArea_X, CTL + k, (TWord)w[17 + k] & 0xffffff);
        for (int g = 0; g < 8; ++g) dsp.memWrite(MemArea_X, AUDIO + n + g, 0x123456 + g);
        scramble(dsp);
        dsp.regs().r[0].var = AUDIO; dsp.regs().r[6].var = CTL; dsp.regs().r[7].var = STATE; dsp.regs().n[7].var = n;
        uint64_t c = 0;
        if (!runToRts(dsp, entry, c)) { fprintf(stderr, "did not return (piece %zu)\n", o / PC); return 1; }
        for (int g = 0; g < 8; ++g) if ((mem.get(MemArea_X, AUDIO + n + g) & 0xffffff) != (TWord)(0x123456 + g)) { ++over; break; }
        if (c > mx) mx = c; tot += c; ns += n;
        int32_t out[17];
        for (int k = 0; k < 16; ++k) { TWord v = mem.get(MemArea_X, AUDIO + k) & 0xffffff; out[k] = (int32_t)(v << 8) >> 8; }
        out[16] = (int32_t)c; fwrite(out, 4, 17, fo);
        if (getenv("O3C_STATES")) { static FILE* fs = fopen(getenv("O3C_STATES"), "wb"); int32_t sv[12];
            for (int q = 0; q < 12; ++q) { TWord v = mem.get(MemArea_X, STATE + q) & 0xffffff; sv[q] = (int32_t)(v << 8) >> 8; } fwrite(sv, 4, 12, fs); fflush(fs); }
    }
    fclose(fo);
    printf("pieces %zu, samples %llu, instructions per sample %.2f (mean incl. prologue), max per piece %llu, pieces writing past their samples %zu\n",
           in.size() / PC, (unsigned long long)ns, ns ? (double)tot / ns : 0.0, (unsigned long long)mx, over);
    return 0;
}
