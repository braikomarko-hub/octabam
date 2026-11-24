// o3host -- OCTA303 vFable, phase 3 (17 Nov 2026, written by Claude): runs one FX insert on the dsp56300 emulator
// core, frame by frame, with nothing of the stock payload: its own audio block, parameter block and state block.
//   o3host blob.bin org(hex) init(hex) proc(hex) ytab.bin yaddr(hex) in.bin out.bin
// blob: dsp_asm -out (3 bytes a word, little-endian) loaded at P:org.  ytab: int32 words loaded at Y:yaddr (p<yaddr>: at P,
// x<yaddr>: at X).
// in.bin: per frame 32 int32 (L,R x 16, 24-bit) + 20 int32 (x:(r6+0..19)).  out.bin: per frame 32 int32 + the
// instruction count of the proc call.  ABI as tools/harness/dsp_host: r0 audio, r6 params, r7 state ($84 words), n7 = 16.
// B3 phase 2 (22 Nov 2026): init is run as the dispatcher would leave the core -- Y:$0bf0..$0d0f filled first (random
// words in the insert's place Y:$0c00..$0cf9, known guard words on both sides), every register scrambled, m1..m5 not
// linear, m0 = $ff, and the dispatcher's r0 r1 r6 r7 n7 m0 m6 m7 holding known values that must come back unchanged.
// Options (environment, so that older callers are unchanged):
//   O3_NOINIT=1          init is not called (a control: the output must then be wrong)
//   O3_YDUMP=file        Y:$0bf0..$0d0f after init, 288 int32 (and the guard check is printed)
//   O3_YPOKE=addr:val    after init, Y:addr = val (a control: one wrong word in the place)
//   O3_INIT2=f           a second instance (its own state block) is set up at frame f: its init runs between the first
//                        instance's calls (after the frame's first piece), then its proc runs on its own block every frame
// B3 phase 2c (22 Nov 2026), init's check of its copy:
//   O3_SPOKE=i:+d | i:=v | i:sj   before init, the table's SOURCE word i (as loaded, P / X / Y) += d, := v, or swapped
//                        with word j; several, comma separated
//   O3_REINIT=f          before frame f the source is put back as loaded and init runs again on the same state block
//   O3_STATEFILL=v       the state blocks start as v (default $555555); with O3_NOINIT=1: a block no init has written
//   O3_MEMCHK=1          X, Y and P $0000..$ffff not loaded by the host are filled with tagged words first; at the end the
//                        words changed outside the state block, the audio and parameter blocks and Y:$0c00..$0cf9 are counted
//   O3_XDUMP=file        the state block (first instance, $84 words) after the last frame, int32
// ACIDF11 (24 Nov 2026), the record and the audio of different frames, as on Marko's unit (his recordings of 24 Nov):
//   O3_HWLAG=L | E       the record's halfword 11 (x:(r6+5)) is the PREVIOUS frame's (L: the record one frame late on the
//                        payloads) or the NEXT frame's (E: one frame early); the first / last frame keeps its own;
//                        A: the previous frame's on odd frames only (late every other frame); 2: two frames late
//   O3_RECLAG=L | E      the same for the whole record, words 0..17 (gv, signature, level, DRIV, halfword 11 ...; 18, 19
//                        are this bench's own controls, kept)
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <memory>
#include <cstring>
#include "dsp56kEmu/dsp.h"
#include "dsp56kEmu/memory.h"
#include "dsp56kEmu/peripherals.h"
#include "dsp56kEmu/agu.h"
using namespace dsp56k;
class AllowAll : public IMemoryValidator { public: bool memValidateAccess(EMemArea, TWord, bool) const override { return true; } };
static const TWord SENTINEL = 0x03f000, AUDIO = 0x5000, PARAMS = 0x5100, PARAMS2 = 0x5180, STATE = 0x4009;   // (reviewer B3p2: not 16-aligned, so a modulo m catches short walks)
static const TWord STATE2 = 0x4209, AUDIO2 = 0x5200, YLO = 0x0bf0, YPLACE = 0x0c00, YPEND = 0x0cfa, YHI = 0x0d10;
// what a call must not lean on: the registers an insert may use arrive with anything in them (m1..m5 not linear, as at init)
// An m register is written as DSP::set_m (private) writes it: the emulator's AGU reads the mask and the modulo set_m
// derives, so a write to regs().m[q].var alone leaves the old ones in force -- before B3 phase 2, "m1..m5 not linear"
// here was linear in effect.  Only linear and modulo values are used here.
static void set_m(DSP& dsp, int q, TWord v) {
    dsp.regs().m[q].var = v;
    if ((v & 0xffff) == 0xffff) { dsp.regs().mModulo[q] = 0; dsp.regs().mMask[q] = 0xffffff; return; }
    if ((v & 0xffff) == 0 || (v & 0xffff) > 0x7fff) { fprintf(stderr, "o3host: m value %06x not supported\n", v); exit(2); }
    dsp.regs().mMask[q] = AGU::calcModuloMask(v); dsp.regs().mModulo[q] = v + 1;
}
static const TWord MNL = 0x000002;   // m1..m5 at entry: modulo 3 (reviewer B3p2: $f with a 16-aligned state block missed proc's m2)
static void scramble(DSP& dsp) {
    static uint32_t z = 0x2545f491;
    auto nx = [&]() { z ^= z << 13; z ^= z >> 17; z ^= z << 5; return (TWord)(z & 0xffffff); };
    for (int q = 1; q <= 5; ++q) { dsp.regs().r[q].var = nx(); dsp.regs().n[q].var = nx(); set_m(dsp, q, MNL); }
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
// init as the dispatcher calls it: r0 = the audio block, r1 = the id, r6 / r7 / n7 / m0 / m6 / m7 the dispatcher's.  -> false if
// it does not return or leaves one of those (or an m2..m5 neither as it was nor linear) changed
static bool runInit(DSP& dsp, TWord init, TWord state, uint64_t& n) {
    scramble(dsp);
    for (int q = 1; q <= 5; ++q) set_m(dsp, q, MNL);
    const TWord want[8] = { AUDIO, 0x123, PARAMS, state, 0x00abcd, 0x0000ff, 0x00ffff, 0x00ffff };   // r0 r1 r6 r7 n7 m0 m6 m7
    dsp.regs().r[0].var = want[0]; dsp.regs().r[1].var = want[1]; dsp.regs().r[6].var = want[2]; dsp.regs().r[7].var = want[3];
    dsp.regs().n[7].var = want[4]; set_m(dsp, 0, want[5]); set_m(dsp, 6, want[6]); set_m(dsp, 7, want[7]);
    if (!runToRts(dsp, init, n)) { fprintf(stderr, "init did not return\n"); return false; }
    const TWord got[8] = { (TWord)dsp.regs().r[0].var, (TWord)dsp.regs().r[1].var, (TWord)dsp.regs().r[6].var, (TWord)dsp.regs().r[7].var,
                           (TWord)dsp.regs().n[7].var, (TWord)dsp.regs().m[0].var, (TWord)dsp.regs().m[6].var, (TWord)dsp.regs().m[7].var };
    static const char* nm[8] = { "r0", "r1", "r6", "r7", "n7", "m0", "m6", "m7" };
    bool ok = true;
    for (int k = 0; k < 8; ++k) if ((got[k] & 0xffffff) != want[k]) { fprintf(stderr, "init changed %s\n", nm[k]); ok = false; }
    for (int q = 2; q <= 5; ++q) { TWord v = (TWord)dsp.regs().m[q].var & 0xffffff; if (v != MNL && v != 0xffffff) { fprintf(stderr, "init left m%d neither as found nor linear\n", q); ok = false; } }
    for (int k = 0; k < 8; ++k) set_m(dsp, k, (k >= 1 && k <= 5) ? MNL : 0xffffff);   // proc's entry as before B3
    return ok;
}
static std::vector<uint8_t> slurp(const char* p) { std::vector<uint8_t> v; FILE* f = fopen(p, "rb"); if (!f) { perror(p); exit(2); }
    int c; while ((c = fgetc(f)) != EOF) v.push_back((uint8_t)c); fclose(f); return v; }
int main(int argc, char** argv) {
    if (argc != 9) { fprintf(stderr, "usage: o3host blob org init proc ytab yaddr in out\n"); return 2; }
    AllowAll val; Memory mem(val, 0x080000, 0x800000, 0x200000);
    Peripherals56362 px; Peripherals56367 py; DSP dsp(mem, &px, &py);
    const bool tabP = argv[6][0] == 'p', tabX = argv[6][0] == 'x';   // p<hex>: the table goes to P (a module's P table); x<hex>: to X
                                                                      // (where the build parks it, XTABLE / XHARVEST); else to Y
    const TWord org = strtoul(argv[2], 0, 16), init = strtoul(argv[3], 0, 16), proc = strtoul(argv[4], 0, 16), yaddr = strtoul(argv[6] + (tabP || tabX ? 1 : 0), 0, 16);
    const char* e_memchk = getenv("O3_MEMCHK"); const bool memchk = e_memchk && e_memchk[0] == '1';
    auto tag = [](int area, TWord a) { return (TWord)((0x300000 * (TWord)(area + 1)) ^ (a * 0x9e5) ^ 0x0a5a5a) & 0xffffff; };
    if (memchk) for (TWord a = 0; a < 0x10000; ++a) { dsp.memWrite(MemArea_X, a, tag(0, a)); dsp.memWrite(MemArea_Y, a, tag(1, a)); dsp.memWriteP(a, tag(2, a)); }
    auto b = slurp(argv[1]);
    for (size_t i = 0; i + 2 < b.size(); i += 3) dsp.memWriteP(org + (TWord)(i / 3), b[i] | (b[i + 1] << 8) | (b[i + 2] << 16));
    dsp.memWriteP(SENTINEL, 0);
    auto y = slurp(argv[5]);
    std::vector<TWord> src;
    for (size_t i = 0; i + 3 < y.size(); i += 4) { int32_t w; memcpy(&w, &y[i], 4); src.push_back((TWord)w & 0xffffff); }
    auto putSrc = [&](size_t i, TWord v) { if (tabP) dsp.memWriteP(yaddr + (TWord)i, v); else dsp.memWrite(tabX ? MemArea_X : MemArea_Y, yaddr + (TWord)i, v); };
    for (size_t i = 0; i < src.size(); ++i) putSrc(i, src[i]);
    if (const char* e = getenv("O3_SPOKE")) {                       // the source spoiled before init
        for (const char* q = e; q && *q; ) {
            char* c; const size_t i = strtoul(q, &c, 10); if (*c != ':' || i >= src.size()) { fprintf(stderr, "O3_SPOKE?\n"); return 2; }
            const char op = c[1]; char* d; long v = strtol(c + 2, &d, 0);
            TWord w = src[i];
            if (op == '+') putSrc(i, (TWord)(w + v) & 0xffffff);
            else if (op == '=') putSrc(i, (TWord)v & 0xffffff);
            else if (op == 's' && (size_t)v < src.size()) { putSrc(i, src[v]); putSrc(v, w); }
            else { fprintf(stderr, "O3_SPOKE?\n"); return 2; }
            q = *d == ',' ? d + 1 : 0;
        }
    }
    const char* e_sf = getenv("O3_STATEFILL"); const TWord sfill = e_sf ? (TWord)strtoul(e_sf, 0, 16) & 0xffffff : 0x555555;
    for (TWord k = 0; k < 0x84; ++k) { dsp.memWrite(MemArea_X, STATE + k, sfill); dsp.memWrite(MemArea_X, STATE2 + k, sfill); }   // dirty state: init must clear what the loop reads
    { uint32_t z = 0x6a09e667;                                  // Y:$0bf0..$0d0f: the place random, the guards known
      for (TWord a = YLO; a < YHI; ++a) { z ^= z << 13; z ^= z >> 17; z ^= z << 5;
          dsp.memWrite(MemArea_Y, a, (a >= YPLACE && a < YPEND) ? (TWord)(z & 0xffffff) : (TWord)(0x9a0000 + a)); } }
    std::vector<TWord> snap[3];                                  // O3_MEMCHK: everything as the host set it up
    if (memchk) for (TWord a = 0; a < 0x10000; ++a) { snap[0].push_back(mem.get(MemArea_X, a)); snap[1].push_back(mem.get(MemArea_Y, a)); snap[2].push_back(mem.get(MemArea_P, a) & 0xffffff); }
    const char* e_reinit = getenv("O3_REINIT"); const long reinit = e_reinit ? strtol(e_reinit, 0, 10) : -1; uint64_t nreinit = 0;
    uint64_t n = 0, ninit = 0;
    const char* e_noinit = getenv("O3_NOINIT"); const char* e_ydump = getenv("O3_YDUMP"); const char* e_ypoke = getenv("O3_YPOKE"); const char* e_init2 = getenv("O3_INIT2");
    const long init2 = e_init2 ? strtol(e_init2, 0, 10) : -1;
    if (!(e_noinit && e_noinit[0] == '1')) { if (!runInit(dsp, init, STATE, ninit)) return 1; }
    else for (int k = 0; k < 8; ++k) set_m(dsp, k, (k >= 1 && k <= 5) ? MNL : 0xffffff);
    int guards = 0;
    for (TWord a = YLO; a < YHI; ++a) if (!(a >= YPLACE && a < YPEND) && (mem.get(MemArea_Y, a) & 0xffffff) != (TWord)(0x9a0000 + a)) ++guards;
    if (e_ydump) { FILE* fy = fopen(e_ydump, "wb"); for (TWord a = YLO; a < YHI; ++a) { int32_t v = (int32_t)(mem.get(MemArea_Y, a) & 0xffffff); fwrite(&v, 4, 1, fy); } fclose(fy); }
    if (e_ypoke) { TWord pa = strtoul(e_ypoke, 0, 16); const char* c = strchr(e_ypoke, ':'); dsp.memWrite(MemArea_Y, pa, c ? (TWord)strtoul(c + 1, 0, 16) & 0xffffff : 0); }
    std::vector<TWord> yafter; for (TWord a = YLO; a < YHI; ++a) yafter.push_back(mem.get(MemArea_Y, a) & 0xffffff);
    uint64_t ninit2 = 0; bool second = false;
    auto in = slurp(argv[7]); FILE* fo = fopen(argv[8], "wb");
    const size_t FR = 52 * 4; uint64_t mx = 0; size_t over = 0;
    const char* e_hwl = getenv("O3_HWLAG"); const char* e_rcl = getenv("O3_RECLAG");
    const char lagc = e_hwl && e_hwl[0] ? e_hwl[0] : e_rcl && e_rcl[0] ? e_rcl[0] : 0;
    const int lagd0 = lagc == 'L' || lagc == 'A' ? -1 : lagc == 'E' ? 1 : lagc == '2' ? -2 : 0;
    const int lagw0 = e_rcl && e_rcl[0] ? 32 : 37, lagw1 = e_rcl && e_rcl[0] ? 50 : 38;   // the words taken from the other frame
    for (size_t o = 0; o + FR <= in.size(); o += FR) {
        int32_t w[52]; memcpy(w, &in[o], FR);
        const int lagd = lagc == 'A' && !((o / FR) & 1) ? 0 : lagd0;
        if (lagd) {
            const long oo = (long)o + lagd * (long)FR;
            if (oo >= 0 && oo + (long)FR <= (long)in.size()) { int32_t v[52]; memcpy(v, &in[oo], FR); for (int q = lagw0; q < lagw1; ++q) w[q] = v[q]; }
        }
        for (int k = 0; k < 32; ++k) dsp.memWrite(MemArea_X, AUDIO + k, (TWord)w[k] & 0xffffff);
        for (int k = 0; k < 20; ++k) dsp.memWrite(MemArea_X, PARAMS + k, (TWord)w[32 + k] & 0xffffff);
        // w[51] = k (1..15): the frame comes in two pieces, the insert is called for [0,k) and then for [k,16) with r0 moved on
        // (what SONDA 4's run B showed under the port, 17 Nov 2026); 0 = one call of 16 samples.  A guard word after the
        // block tells a call that writes past it.
        const int k = (w[51] >= 1 && w[51] <= 15) ? w[51] : 0;
        if ((long)(o / FR) == reinit) {                           // the source put back, and init again (same state block)
            for (size_t i = 0; i < src.size(); ++i) putSrc(i, src[i]);
            if (!runInit(dsp, init, STATE, nreinit)) return 1;
        }
        for (int g = 0; g < 48; ++g) dsp.memWrite(MemArea_X, AUDIO + 32 + g, 0x123456 + g);      // the unit's X:$20..$4f is the stock code's
        for (int g = 1; g <= 16; ++g) dsp.memWrite(MemArea_X, AUDIO - g, 0x654321 + g);
        scramble(dsp);
        dsp.regs().r[0].var = AUDIO; dsp.regs().r[6].var = PARAMS; dsp.regs().r[7].var = STATE; dsp.regs().n[7].var = k ? k : 16;
        if (!runToRts(dsp, proc, n)) { fprintf(stderr, "proc did not return (frame %zu)\n", o / FR); return 1; }
        if ((long)(o / FR) == init2) {                            // the second instance's init, while the first plays
            if (!runInit(dsp, init, STATE2, ninit2)) return 1;
            second = true;
        }
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
        if (second) {                                             // the second instance's call, on its own block (its output is not kept)
            for (int q = 0; q < 32; ++q) dsp.memWrite(MemArea_X, AUDIO2 + q, (TWord)w[q] & 0xffffff);
            scramble(dsp);
            dsp.regs().r[0].var = AUDIO2; dsp.regs().r[6].var = PARAMS; dsp.regs().r[7].var = STATE2; dsp.regs().n[7].var = 16;
            uint64_t n3 = 0;
            if (!runToRts(dsp, proc, n3)) { fprintf(stderr, "proc did not return (frame %zu, second instance)\n", o / FR); return 1; }
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
    fclose(fo);
    if (memchk) {
        auto inX = [&](TWord a, TWord lo, TWord len) { return a >= lo && a < lo + len; };
        size_t cx = 0, cy = 0, cp = 0;
        for (TWord a = 0; a < 0x10000; ++a) {
            const bool okX = inX(a, STATE, 0x84) || inX(a, STATE2, 0x84) || inX(a, AUDIO - 16, 16 + 32 + 48) || inX(a, PARAMS, 20) || inX(a, PARAMS2, 20) || inX(a, AUDIO2, 32);
            if (!okX && mem.get(MemArea_X, a) != snap[0][a]) ++cx;
            if (!inX(a, YPLACE, YPEND - YPLACE) && mem.get(MemArea_Y, a) != snap[1][a]) ++cy;
            if ((mem.get(MemArea_P, a) & 0xffffff) != snap[2][a]) ++cp;
        }
        printf("memchk: words changed outside the allowed blocks X %zu Y %zu P %zu\n", cx, cy, cp);
    }
    if (const char* e = getenv("O3_XDUMP")) { FILE* fx = fopen(e, "wb"); for (TWord a = STATE; a < STATE + 0x84; ++a) { int32_t v = (int32_t)(mem.get(MemArea_X, a) & 0xffffff); fwrite(&v, 4, 1, fx); } fclose(fx); }
    int ymoved = 0; { size_t q = 0; for (TWord a = YLO; a < YHI; ++a, ++q) if ((mem.get(MemArea_Y, a) & 0xffffff) != yafter[q]) ++ymoved; }
    printf("frames %zu, max instructions per frame %llu, frames written outside the audio block %zu\n", in.size() / FR, (unsigned long long)mx, over);
    if (reinit >= 0) printf("re-init instructions %llu\n", (unsigned long long)nreinit);
    printf("init instructions %llu, second init %llu, Y guard words changed by init %d, Y:$0bf0..$0d0f changed after init %d\n",
           (unsigned long long)ninit, (unsigned long long)ninit2, guards, ymoved);
    return 0;
}
