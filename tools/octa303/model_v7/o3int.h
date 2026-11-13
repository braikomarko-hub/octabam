/* OCTA303 vFable model v7 - the integer control step (code written by Claude).
 * Only int32 add/sub/shift/compare, fmul = (a*b)>>31 (64-bit product), table lookups with linear interpolation and at
 * most 2 integer divides per control step (here: 1, for Dq).  No floating point.  Included by o3k.c.
 * Q formats: octaves Q24; envelopes, coefficients, accent voltages Q31 (1.0 = 0x7FFFFFFF); feedback kh Q24;
 * VCA gain Q28; semitones Q24; Hz Q12 (TRCK). */
#ifndef O3INT_H
#define O3INT_H

/* ---- table blob layout (o3model.int_tables() builds it in the same order; gen_tables.py emits it).  The model keeps
   every entry in an int32; C1S C2S CVS BONS GV TRK OVK hold int16 values (shifted at use) and ship as int16. ---- */
#define NG     513                 /* g(u) = 2^u / (1 + 2^u), u = log2(w r), 1/32 octave from U0 = -13 to +3 */
#define CTN_I  77                  /* the compensation table, 1/8 octave from 4.0 */
enum {
    TB_CUT = 0, TB_ENVB = 128, TB_RESC = 256, TB_ENVD = 384, TB_K = 512, TB_GV = 640,
    TB_AMEG = 768, TB_AMEGA = 896, TB_AVA = 1024, TB_AV = 1152, TB_ASL = 1280, TB_OVK = 1408, TB_TRK = 1536,
    TB_C1B = 1664, TB_C1S = 1792, TB_C2B = 1920, TB_C2S = 2048, TB_CVB = 2176, TB_CVS = 2304,
    TB_BONB = 2432, TB_BONS = 2560, TB_C3 = 2688, TB_BOFF = 2816,
    TB_OCTD = 2944, TB_KCD = 2944 + CTN_I, TB_G = 2944 + 2 * CTN_I, TB_EXP2 = TB_G + NG, TB_LOG2 = TB_EXP2 + 129,
    TB_FM = TB_LOG2 + 65, TB_SC = TB_FM + 66,
    /* scalars */
    S_AATT = 0, S_AV2, S_G0, S_ACCF, S_ACCV, S_VDF, S_VDV, S_VFLOOR, S_VW, S_VFK, S_RCONST, S_CUTX0, S_CUTXS, S_ENVX,
    S_LR0, S_LR1, S_LR2, S_LR3, S_U0, S_LOG098, S_N,
    TB_N = TB_SC + S_N
};
/* ---- per segment (START) knob row ---- */
enum { K_CUT, K_RES, K_ENV, K_DEC, K_ACC, K_ACCON, K_ACCV, K_SLID, K_WAVE, K_DF0, K_POCT = K_DF0 + 12, K_INC0, K_N };

#ifdef O3_DEBUG                    /* V4: every add / sub / shift / fmul of the control step checked for int32 wrap */
long o3_dbg_wrap = 0, o3_dbg_div0 = 0, o3_dbg_line = 0;
static inline int32_t add_(int32_t a, int32_t b, int l) { int32_t r; if (__builtin_add_overflow(a, b, &r)) { o3_dbg_wrap++; o3_dbg_line = l; } return r; }
static inline int32_t sub_(int32_t a, int32_t b, int l) { int32_t r; if (__builtin_sub_overflow(a, b, &r)) { o3_dbg_wrap++; o3_dbg_line = l; } return r; }
static inline int32_t shl_(int32_t a, int n, int l) { int64_t r = (int64_t)a * ((int64_t)1 << n); if (r > INT32_MAX || r < INT32_MIN) { o3_dbg_wrap++; o3_dbg_line = l; } return (int32_t)r; }
static inline int32_t fm_(int32_t a, int32_t b, int l) { int64_t r = ((int64_t)a * b) >> 31; if (r > INT32_MAX || r < INT32_MIN) { o3_dbg_wrap++; o3_dbg_line = l; } return (int32_t)r; }
#define ADD(a, b) add_((a), (b), __LINE__)
#define SUB(a, b) sub_((a), (b), __LINE__)
#define SHL(a, n) shl_((a), (n), __LINE__)
#define FM_(a, b) fm_((a), (b), __LINE__)
#else
#define ADD(a, b) ((a) + (b))
#define SUB(a, b) ((a) - (b))
#define SHL(a, n) ((a) << (n))
#define FM_(a, b) fmul((a), (b))
#endif
#ifdef O3_COUNT                    /* the operation count for the report: multiplies, divides, table lookups, branches */
long o3_cnt[4];
#define CM (o3_cnt[0]++)
#define CD (o3_cnt[1]++)
#define CT (o3_cnt[2]++)
#define CB (o3_cnt[3]++)
#else
#define CM ((void)0)
#define CD ((void)0)
#define CT ((void)0)
#define CB ((void)0)
#endif
#define MUL(a, b) (CM, FM_((a), (b)))
#define ONE 0x7FFFFFFF

/* linear interpolation in a table: x = index Q(fb) (fractional bits fb), clamped by the caller */
static inline int32_t lerp(const int32_t *t, int32_t i, int32_t fr31) { CT; return ADD(t[i], MUL(SUB(t[i + 1], t[i]), fr31)); }

/* 2^x for x Q24 octaves: returns m Q30 in [1, 2) and the integer part */
static inline int32_t exp2_q30(const int32_t *T, int32_t x, int32_t *ip) {
    *ip = x >> 24; int32_t f = x & 0xFFFFFF;               /* [0, 1) Q24 */
    return lerp(T + TB_EXP2, f >> 17, (f & 0x1FFFF) << 14);   /* 129 entries, 1/128 octave */
}
/* log2(x) for x > 0, x in Q(q): result Q24 (count leading zeros = FF1 on the ColdFire, then one table) */
static inline int32_t log2_q24(const int32_t *T, uint32_t x, int q) {
    int nb = 31 - __builtin_clz(x); uint32_t y = x << (31 - nb);    /* [1, 2) Q31 */
    int32_t f = (int32_t)(y & 0x7FFFFFFF);
    return ADD(SHL(nb - q, 24), lerp(T + TB_LOG2, f >> 25, (f & 0x1FFFFFF) << 6));
}

typedef struct {
    /* state */
    int32_t meg, megt, vc, amp, e1, e2, kgov, pst, ptgt, kgmin;
    /* per note (START) */
    int32_t A, wrs, accnet, a_meg, a_va, pitch_oct;
    uint32_t inc0;
    const int32_t *k;
} IS;

/* note-on: the per-note constants (ACC, the accent, the decay chosen by the accent, the soft attack) */
static void is_note(IS *s, const int32_t *T, const int32_t *k) {
    s->k = k;
    int acc = k[K_ACC], on = k[K_ACCON];
    s->A = acc * 16909320;                                  /* acc / 127, Q31 */
    s->wrs = SHL(MUL(s->A, SUB(ONE, s->A)), 2);             /* 4 a (1 - a): the pot's source resistance, 0..1 */
    s->accnet = on && k[K_DF0 + 7] != 2;                    /* SWP SELF: no accent to filter and VCA */
    s->a_meg = on ? T[TB_AMEGA + k[K_DF0 + 5]] : T[TB_AMEG + k[K_DEC]];
    s->a_va = on ? T[TB_AVA] : T[TB_AVA + k[K_DF0 + 6]];
    s->pitch_oct = k[K_POCT]; s->inc0 = (uint32_t)k[K_INC0];
}

/* the control step.  In: the current knob row, the pk4 peak (SWP), glvl.  Out: G1..G4, kq, Dq, gq, inc, pqmax. */
static inline void is_step(IS *s, const int32_t *T, const int F, int32_t pk4, int32_t glvl, int32_t *G, int32_t *kq,
                           int32_t *Dq, int32_t *gq, uint32_t *inc, int64_t *pqmax) {
    const int32_t *k = s->k, *S = T + TB_SC;
    const int32_t *df = k + K_DF0;
    int res = k[K_RES];
    /* slide: one pole in Q24 semitones; the increment only when the pitch moved */
    CB; if (s->pst != s->ptgt) {
        int32_t np = ADD(s->pst, MUL(SUB(s->ptgt, s->pst), T[TB_ASL + k[K_SLID]])); CT;
        CB; if (np != s->pst) {
            s->pst = np; int32_t ip; int32_t m = exp2_q30(T, MUL(np, 178956971), &ip);  /* st / 12 */
            uint64_t v = ((uint64_t)s->inc0 * (uint32_t)m) >> 30; CM;
            *inc = (uint32_t)(ip >= 0 ? v << ip : v >> -ip);
        }
    }
    /* MEG */
    s->meg = ADD(s->meg, MUL(SUB(s->megt, s->meg), S[S_AATT]));
    s->megt = MUL(s->megt, s->a_meg);
    int32_t mv = s->meg < s->megt ? s->meg : s->megt; CB;
    /* the accent network: VW = c1 E + c2 vc (D24 on) or c3 vc (off); the ACC dependence (the pot's source resistance
       47 + 50 a(1-a) kOhm) as a chord between the tables at 47 and 59.5 kOhm, weight wrs = 4 a (1 - a) */
    int spd = df[8], swp = df[7];
    int32_t E = s->accnet ? SUB(MUL(s->A, mv), S[S_VDF]) : (int32_t)0x80000000; CB;
    int32_t c1 = ADD(T[TB_C1B + res], MUL(s->wrs, T[TB_C1S + res] << 16)); CT; CT;
    int32_t c2 = ADD(T[TB_C2B + res], MUL(s->wrs, T[TB_C2S + res] << 16)); CT; CT;
    int32_t VW0 = ADD(MUL(c1, E), MUL(c2, s->vc));
    int on = E > VW0; CB;
    int32_t b, Veq;
    if (on) { b = ADD(T[TB_BONB + res], MUL(s->wrs, T[TB_BONS + res] << 16)); CT; CT;
              int32_t cV = ADD(T[TB_CVB + res], MUL(s->wrs, T[TB_CVS + res] << 16)); CT; CT; Veq = MUL(cV, E); }
    else { b = T[TB_BOFF + res]; CT; Veq = 0; }
    CB; if (spd == 2) b >>= 2; else if (spd == 0) b = SHL(b, 2);   /* SLOW: C13 x 4; FAST: C13 / 4 */
    /* alpha = 1 - exp(-b) = b - b^2/2 + b^3/6 (b <= 0.04: error < 1e-7) */
    int32_t b2 = MUL(b, b);
    int32_t alpha = ADD(SUB(b, b2 >> 1), MUL(b2, MUL(b, 357913941)));
    s->vc = ADD(s->vc, MUL(SUB(Veq, s->vc), alpha));
    int32_t VW = on ? ADD(MUL(c1, E), MUL(c2, s->vc)) : MUL(T[TB_C3 + res], s->vc); CT;
    int32_t evv = s->accnet ? SUB(MUL(s->A, mv), S[S_VDV]) : 0;
    int32_t saccv = evv > 0 ? evv : 0; CB;
    /* the cutoff, Q24 octaves */
    int cut = k[K_CUT], env = k[K_ENV];
    int32_t oct = df[10] ? ADD(S[S_CUTX0], S[S_CUTXS] * cut) : T[TB_CUT + cut]; CB; CT;
    oct = ADD(oct, ADD(T[TB_ENVB + env], T[TB_RESC + res])); CT; CT;
    int32_t dep = T[TB_ENVD + env]; CT;
    CB; if (df[11]) { dep = SHL(MUL(SUB(dep, T[TB_ENVD]), S[S_ENVX]), 3); CT; }   /* ENVX: 3.84 (d - d(0)), S_ENVX Q28 */
    oct = ADD(oct, MUL(dep, mv));
    int32_t accf = spd == 2 ? SHL(S[S_ACCF], 1) : S[S_ACCF]; CB;
    oct = ADD(oct, MUL(accf, VW));
    CB; if (k[K_WAVE] & 4) oct = ADD(oct, S[S_RCONST]);
    CB; if (df[2]) {   /* TRCK: Hz += trk x (pitch - C3) in octaves, floor 16 Hz; octave -> Hz -> octave */
        int32_t ip, o2 = oct > (int32_t)(17.9 * 16777216) ? (int32_t)(17.9 * 16777216) : oct; CB;   /* beyond the tables anyway */
        int32_t m = exp2_q30(T, o2, &ip);                                   /* Hz Q12 = m Q30 >> (18 - ip) */
        int32_t fa = m >> (18 - ip);
        int32_t po = ADD(s->pitch_oct, MUL(s->pst, 178956971));            /* Q24 octaves */
        fa = ADD(fa, MUL(T[TB_TRK + df[2]] << 12, SHL(po, 4))); CT;         /* (Q3 << 12 = Q15) x Q28 -> Q12 */
        if (fa < (16 << 12)) fa = 16 << 12; CB;
        oct = log2_q24(T, (uint32_t)fa, 12);
    }
#ifdef O3_TRACE
    { extern int32_t o3_troct; o3_troct = oct; }
#endif
    /* the compensation table: 1/8 octave from 4.0 (as the float path: index clamped to [0, CTN - 1.001]) */
    int32_t xo = SUB(oct, 4 << 24); int ii; int32_t fr;
    if (xo < 0) { ii = 0; fr = 0; } else { ii = xo >> 21; fr = (xo & 0x1FFFFF) << 10;
        if (ii >= CTN_I - 1) { ii = CTN_I - 2; fr = 2145336164; } }      /* 0.999 */
    CB; CB;
    int32_t octd = lerp(T + TB_OCTD, ii, fr), kcd = lerp(T + TB_KCD, ii, fr);   /* Q24, Q30 */
    /* the four poles: G_j = g(octd + log2(pi/FS) + log2 r_j), one table */
    int32_t gam = ONE, gmx = 0;
    for (int j = 0; j < 4; j++) {
        int32_t u = SUB(ADD(octd, S[S_LR0 + j]), S[S_U0]);
        int gi = u >> 19; int32_t gf = (u & 0x7FFFF) << 12;
        if (gi < 0) { gi = 0; gf = 0; } if (gi > NG - 2) { gi = NG - 2; gf = ONE; } CB; CB;
        G[j] = lerp(T + TB_G, gi, gf);
        gam = MUL(gam, G[j]);
        if (G[j] > gmx) gmx = G[j]; CB;
    }
    /* feedback: kh = K(res) kcd (WHST/SELF x 2, OVDR x G^-0.5, governor), Q24, capped at 120 */
    int32_t kh = SHL(MUL(T[TB_K + res], kcd), 1); CT;
    CB; if (swp >= 1) kh = SHL(kh, 1);
    CB; if (df[0] > 25) { kh = MUL(kh, T[TB_OVK + df[0]] << 16); CT; }   /* Q15 << 16 */
    if (F & F_GOV) {
        CB; if (pk4 > 3 * 1048576) { s->kgov = MUL(s->kgov, 2083059138); if (s->kgov < 644245094) s->kgov = 644245094; CB; }   /* x 0.97, floor 0.3 */
        else { int32_t t = ADD(s->kgov >> 1, MUL(s->kgov >> 1, 10737418)); s->kgov = t > (ONE >> 1) ? ONE : SHL(t, 1); CB; } /* x 1.005, cap 1 */
        if (s->kgov < s->kgmin) s->kgmin = s->kgov; CB;
        kh = MUL(kh, s->kgov);
    }
    if (kh > 120 << 24) kh = 120 << 24; CB;
    *kq = kh;
    /* Dq = 1 / (1 + kh gam): one divide (normalised to 16 bits) + one Newton step */
    int32_t D = ADD(1 << 24, MUL(kh, gam));                 /* Q24, in [1, 121] */
    int sh = 31 - __builtin_clz((uint32_t)D) - 15;          /* D >> sh in [2^15, 2^16) */
#ifdef O3_DEBUG
    if ((D >> sh) == 0) o3_dbg_div0++;
#endif
    uint32_t q = 0xFFFFFFFFu / (uint32_t)(D >> sh); CD;     /* ~ 2^32 / (D >> sh) */
    int32_t r = (int32_t)(q << (23 - sh));                  /* 2^24 / D, Q31 */
    int32_t e = SUB(1 << 24, MUL(D, r));                    /* 1 - D r, Q24 */
    r = ADD(r, SHL(MUL(r, e), 7));
    *Dq = r > 2147483626 ? 2147483626 : r; CB;              /* the float path's q31 cap */
    if (F & F_FM) {   /* the FM ceiling: m <= 0.98 / the largest g, as a table position: 32 + 8 log2(0.98 / gmx) */
        int32_t pm = ADD(32 << 24, SHL(SUB(S[S_LOG098], log2_q24(T, (uint32_t)gmx, 31)), 3));
        int64_t pq = (int64_t)(pm >> 8) - 1;
        if (pq > (64 << 16) - 1) pq = (64 << 16) - 1; if (pq < 0) pq = 0; CB; CB;
        *pqmax = pq;
    }
    /* the VCA: amp (attack), the volume decay (VDEC), the accent (ACCV), the gate */
    s->amp = ADD(s->amp, MUL(SUB(ONE, s->amp), s->a_va));
    s->e1 = MUL(s->e1, T[TB_AV + df[3]]); CT;
    s->e2 = MUL(s->e2, S[S_AV2]);
    int32_t vfl = S[S_VFLOOR]; CB; if (df[3] > 64) vfl = ADD(vfl, S[S_VFK] * (df[3] - 64));
    int32_t vdec = ADD(vfl, ADD(MUL(SUB(SUB(ONE, vfl), S[S_VW]), s->e1), MUL(S[S_VW], s->e2)));
    int32_t accv = S[S_ACCV]; CB; if (k[K_ACCV] != 64) { accv = (int32_t)(((int64_t)accv * k[K_ACCV]) >> 6); CM; }   /* Q27 */
    int32_t at = ADD(1 << 27, MUL(accv, saccv));            /* Q27 */
    int32_t g = MUL(MUL(S[S_G0], MUL(s->amp, vdec)), at);   /* Q28 x Q27 -> Q24 */
    CB; if (glvl != 32767) g = MUL(g, glvl * 65538);        /* x glvl / 32767 */
    if (g > 134049955) g = 134049955; if (g < 0) g = 0; CB; CB;   /* 7.99 in Q24 */
    *gq = SHL(g, 4);                                        /* Q28 */
}
#endif
