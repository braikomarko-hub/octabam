// o3host -- OCTA303 vFable, phase 3 (17 Nov 2026, written by Claude): runs one FX insert on the dsp56300 emulator
// core, frame by frame, with nothing of the stock payload: its own audio block, parameter block and state block.
//   o3host blob.bin org(hex) init(hex) proc(hex) ytab.bin yaddr(hex) in.bin out.bin
// blob: dsp_asm -out (3 bytes a word, little-endian) loaded at P:org.  ytab: int32 words loaded at Y:yaddr.
// in.bin: per frame 32 int32 (L,R x 16, 24-bit) + 20 int32 (x:(r6+0..19)).  out.bin: per frame 32 int32 + the
// instruction count of the proc call.  ABI as tools/harness/dsp_host: r0 audio, r6 params, r7 state ($84 words), n7 = 16.
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <memory>
#include <cstring>
#include "dsp56kEmu/dsp.h"
#include "dsp56kEmu/memory.h"
#include "dsp56kEmu/peripherals.h"
using namespace dsp56k;
class AllowAll : public IMemoryValidator { public: bool memValidateAccess(EMemArea, TWord, bool) const override { return true; } };
static const TWord SENTINEL = 0x03f000, AUDIO = 0x5000, PARAMS = 0x5100, PARAMS2 = 0x5180, STATE = 0x4000;
// what a call must not lean on: the registers an insert may use arrive with anything in them (m1..m5 not linear, as at init)
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
    if (argc != 9) { fprintf(stderr, "usage: o3host blob org init proc ytab yaddr in out\n"); return 2; }
    AllowAll val; Memory mem(val, 0x080000, 0x800000, 0x200000);
    Peripherals56362 px; Peripherals56367 py; DSP dsp(mem, &px, &py);
    const bool tabP = argv[6][0] == 'p';   // p<hex>: the table goes to P (a module's P table), else to Y
    const TWord org = strtoul(argv[2], 0, 16), init = strtoul(argv[3], 0, 16), proc = strtoul(argv[4], 0, 16), yaddr = strtoul(argv[6] + (tabP ? 1 : 0), 0, 16);
    auto b = slurp(argv[1]);
    for (size_t i = 0; i + 2 < b.size(); i += 3) dsp.memWriteP(org + (TWord)(i / 3), b[i] | (b[i + 1] << 8) | (b[i + 2] << 16));
    dsp.memWriteP(SENTINEL, 0);
    auto y = slurp(argv[5]);
    for (size_t i = 0; i + 3 < y.size(); i += 4) { int32_t w; memcpy(&w, &y[i], 4); if (tabP) dsp.memWriteP(yaddr + (TWord)(i / 4), (TWord)w & 0xffffff); else dsp.memWrite(MemArea_Y, yaddr + (TWord)(i / 4), (TWord)w & 0xffffff); }
    for (TWord k = 0; k < 0x84; ++k) dsp.memWrite(MemArea_X, STATE + k, 0x555555);   // dirty state: init must clear what the loop reads
    for (int k = 0; k < 8; ++k) dsp.regs().m[k].var = (k >= 1 && k <= 5) ? 0x00000f : 0xffffff;   // m1..m5 NOT linear: an insert must set the ones it walks (DSP.md); m0, m6, m7 are the dispatcher's
    uint64_t n = 0;
    dsp.regs().r[6].var = PARAMS; dsp.regs().r[7].var = STATE; dsp.regs().r[1].var = 0x123;
    if (!runToRts(dsp, init, n)) { fprintf(stderr, "init did not return\n"); return 1; }
    if (dsp.regs().r[1].var != 0x123) { fprintf(stderr, "init changed r1\n"); return 1; }
    auto in = slurp(argv[7]); FILE* fo = fopen(argv[8], "wb");
    const size_t FR = 52 * 4; uint64_t mx = 0; size_t over = 0;
    for (size_t o = 0; o + FR <= in.size(); o += FR) {
        int32_t w[52]; memcpy(w, &in[o], FR);
        for (int k = 0; k < 32; ++k) dsp.memWrite(MemArea_X, AUDIO + k, (TWord)w[k] & 0xffffff);
        for (int k = 0; k < 20; ++k) dsp.memWrite(MemArea_X, PARAMS + k, (TWord)w[32 + k] & 0xffffff);
        // w[51] = k (1..15): the frame comes in two pieces, the insert is called for [0,k) and then for [k,16) with r0 moved on
        // (what SONDA 4's run B showed under the port, 17 Nov 2026); 0 = one call of 16 samples.  A guard word after the
        // block tells a call that writes past it.
        const int k = (w[51] >= 1 && w[51] <= 15) ? w[51] : 0;
        for (int g = 0; g < 48; ++g) dsp.memWrite(MemArea_X, AUDIO + 32 + g, 0x123456 + g);      // the unit's X:$20..$4f is the stock code's
        for (int g = 1; g <= 16; ++g) dsp.memWrite(MemArea_X, AUDIO - g, 0x654321 + g);
        scramble(dsp);
        dsp.regs().r[0].var = AUDIO; dsp.regs().r[6].var = PARAMS; dsp.regs().r[7].var = STATE; dsp.regs().n[7].var = k ? k : 16;
        if (!runToRts(dsp, proc, n)) { fprintf(stderr, "proc did not return (frame %zu)\n", o / FR); return 1; }
        if (k) {
            uint64_t n2 = 0;
            // each piece has its own parameter block on the unit (r6 = $263, $2e3, $363 in turn; SONDA 5M): the second
            // piece reads PARAMS2, a copy -- w[50] = 1: its signature cleared; 2: its signature set whatever the first's is
            for (int q = 0; q < 20; ++q) dsp.memWrite(MemArea_X, PARAMS2 + q, (TWord)w[32 + q] & 0xffffff);
            if (w[50] == 1) { dsp.memWrite(MemArea_X, PARAMS2 + 1, 0); dsp.memWrite(MemArea_X, PARAMS2 + 2, 0); }
            if (w[50] == 2) { dsp.memWrite(MemArea_X, PARAMS2 + 1, 0x3a5c00); dsp.memWrite(MemArea_X, PARAMS2 + 2, 0x651700); }
            scramble(dsp);
            dsp.regs().r[0].var = AUDIO + 2 * k; dsp.regs().r[6].var = PARAMS2; dsp.regs().r[7].var = STATE; dsp.regs().n[7].var = 16 - k;
            if (!runToRts(dsp, proc, n2)) { fprintf(stderr, "proc did not return (frame %zu, second piece)\n", o / FR); return 1; }
            n += n2;
        }
        { bool hit = false;
          for (int g = 0; g < 48; ++g) hit |= (mem.get(MemArea_X, AUDIO + 32 + g) & 0xffffff) != (TWord)(0x123456 + g);
          for (int g = 1; g <= 16; ++g) hit |= (mem.get(MemArea_X, AUDIO - g) & 0xffffff) != (TWord)(0x654321 + g);
          if (hit) ++over; }
        if (n > mx) mx = n;
        int32_t out[33];
        for (int k = 0; k < 32; ++k) { TWord v = mem.get(MemArea_X, AUDIO + k) & 0xffffff; out[k] = (int32_t)(v << 8) >> 8; }
        out[32] = (int32_t)n; fwrite(out, 4, 33, fo);
    }
    fclose(fo); printf("frames %zu, max instructions per frame %llu, frames written outside the audio block %zu\n", in.size() / FR, (unsigned long long)mx, over);
    return 0;
}
