/* TRACK PATTERNS engine. See trackpattern.h. Original code, MIT (LICENSE). */
#include "trackpattern.h"

_Static_assert(sizeof(TpState) == 4 * TP_TRACKS + 4, "state layout");

/* What a queued code makes a track's src. */
static uint8_t landed(uint8_t next) {
    return next == TP_TO_FOLLOW ? 0 : next;
}

unsigned tp_pattern(const TpState *s, unsigned track, unsigned global) {
    if (track >= TP_TRACKS) return global;
    return s->src[track] ? s->src[track] - 1u : global;
}

unsigned tp_global(TpState *s, unsigned id) {
    if (s->seen && s->global == (uint8_t)id) return 0;
    unsigned cleared = 0;
    if (s->seen) {
        for (unsigned t = 0; t < TP_TRACKS; ++t) {
            cleared |= s->src[t] | s->next[t];
            s->src[t] = 0;
            s->next[t] = 0;
        }
    }
    s->global = (uint8_t)id;
    s->seen = 1;
    return cleared != 0;
}

unsigned tp_queue(TpState *s, unsigned track, unsigned pattern, unsigned global,
                  unsigned playing) {
    if (track >= TP_TRACKS || pattern >= TP_PATTERNS) return 0;
    uint8_t code = pattern == global ? TP_TO_FOLLOW : (uint8_t)(pattern + 1u);
    if (!playing) {
        s->src[track] = landed(code);
        s->next[track] = 0;
        return code;
    }
    /* Asking for what the track already plays withdraws a queued change. */
    s->next[track] = landed(code) == s->src[track] ? 0 : code;
    return code;
}

unsigned tp_step(TpState *s, unsigned track, unsigned raw, unsigned global) {
    if (track >= TP_TRACKS) return global;
    if (!s->started[track] || raw <= s->last_raw[track]) {
        if (s->next[track]) {
            s->src[track] = landed(s->next[track]);
            s->next[track] = 0;
        }
    }
    s->started[track] = 1;
    s->last_raw[track] = (uint8_t)raw;
    return tp_pattern(s, track, global);
}

unsigned tp_peek(const TpState *s, unsigned track, unsigned raw, unsigned len,
                 unsigned global) {
    if (track >= TP_TRACKS) return global;
    unsigned wraps = !s->started[track] || (len && raw >= len) || raw <= s->last_raw[track];
    if (wraps && s->next[track]) {
        uint8_t src = landed(s->next[track]);
        return src ? src - 1u : global;
    }
    return tp_pattern(s, track, global);
}

void tp_restart(TpState *s) {
    for (unsigned t = 0; t < TP_TRACKS; ++t) s->started[t] = 0;
}

char *tp_label(const TpState *s, unsigned track, unsigned bank, char *out) {
    unsigned n = 0;
    if (track >= TP_TRACKS) { out[0] = 0; return out; }
    out[n++] = track < 8 ? 'T' : 'M';
    out[n++] = (char)('1' + track % 8);
    uint8_t code = s->next[track] ? s->next[track] : (s->src[track] ? s->src[track] : TP_TO_FOLLOW);
    if (code == TP_TO_FOLLOW) {
        static const char follows[] = " FOLLOWS";
        for (const char *p = follows; *p; ++p) out[n++] = *p;
    } else {
        unsigned pattern = code;            /* 1..16 */
        out[n++] = ' '; out[n++] = '>'; out[n++] = ' ';
        out[n++] = (char)('A' + (bank < 16 ? bank : 0));
        out[n++] = (char)('0' + pattern / 10);
        out[n++] = (char)('0' + pattern % 10);
    }
    out[n] = 0;
    return out;
}
