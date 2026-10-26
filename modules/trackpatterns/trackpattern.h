/* TRACK PATTERNS -- the per-track pattern engine.
 *
 * The Octatrack plays every track from one global pattern. This engine
 * answers "which pattern of the playing bank should track t read on this
 * step?", so each track can play its own pattern, clip style: a change is
 * queued and lands when that track's own step counter wraps, at the end of
 * its loop. The stock counters, lengths' timing, tempo, swing and the Part
 * (machines, samples, FX) stay the instrument's own.
 *
 * Every field is zero in the stock state: a zeroed table (as the loader's
 * DRAM boots) means every track follows the global pattern.
 *
 * Freestanding: no floating point, no library calls, no allocation. Compile
 * for the unit with generate.py (m68k-elf-gcc -mcpu=5475), test on the host
 * with verify.py. */
#ifndef TRACKPATTERN_H
#define TRACKPATTERN_H
#include <stdint.h>

#define TP_TRACKS 16      /* 0..7 audio T1..T8, 8..15 MIDI M1..M8 */
#define TP_PATTERNS 16    /* per bank */
#define TP_TO_FOLLOW 0xffu /* next[t]: go back to the global pattern */

typedef struct {
    uint8_t src[TP_TRACKS];      /* the pattern the track plays + 1; 0 = follow */
    uint8_t next[TP_TRACKS];     /* queued: pattern + 1, TP_TO_FOLLOW, 0 = none */
    uint8_t last_raw[TP_TRACKS]; /* the stock step the track was last on */
    uint8_t started[TP_TRACKS];  /* the track has stepped since the last restart */
    uint8_t global;              /* the playing pattern last seen (tp_global's id) */
    uint8_t seen;                /* 1 once `global` holds one */
    uint8_t reserved[2];
} TpState;

/* The pattern a track reads: its own, or the global one. */
unsigned tp_pattern(const TpState *s, unsigned track, unsigned global);

/* The playing pattern is `id` now: bank * 16 + pattern (0..255), so a bank
 * change to the same pattern number is a change too. A change from the one
 * last seen clears every override and every queued change (v1: a global
 * pattern change, by key, chain or arranger, brings every track back).
 * Returns 1 when it cleared them. */
unsigned tp_global(TpState *s, unsigned id);

/* Queue `pattern` (0..15) for `track`. Choosing the global pattern queues
 * the way back to following it. While playing the change lands at the
 * track's next loop start (tp_step); while stopped it applies at once.
 * Returns the queued code (pattern + 1, TP_TO_FOLLOW), or 0 for a track or
 * pattern out of range. */
unsigned tp_queue(TpState *s, unsigned track, unsigned pattern, unsigned global,
                  unsigned playing);

/* One stock step: `track`'s counter is on `raw`. A raw step not after the
 * last one (a wrap, a restart, or the same step again under MASTER LENGTH)
 * starts a new pass, and a queued change lands first. Returns the pattern
 * the track reads for this step. */
unsigned tp_step(TpState *s, unsigned track, unsigned raw, unsigned global);

/* The look-ahead form: the pattern the track will read when its counter is
 * on `raw`; `raw == len` (or beyond) is the next pass's first step. Changes
 * nothing, and agrees with what tp_step then returns. */
unsigned tp_peek(const TpState *s, unsigned track, unsigned raw, unsigned len,
                 unsigned global);

/* PLAY: every track starts again from its first step, overrides kept. */
void     tp_restart(TpState *s);

/* The popup text for a queued change, e.g. "T5 > A03", "M2 FOLLOWS".
 * `out` must hold 16 bytes. Returns `out`. */
char    *tp_label(const TpState *s, unsigned track, unsigned bank, char *out);

#endif
