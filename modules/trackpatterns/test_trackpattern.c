/* Host tests for the TRACK PATTERNS engine (run by verify.py). No firmware. */
#include <stdio.h>
#include <string.h>
#include "trackpattern.h"

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; \
    printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* Play `steps` stock steps of one track looping at `len` from stock step
 * `from`, recording the pattern read on each. */
static void play(TpState *s, unsigned track, unsigned len, unsigned from, unsigned steps,
                 unsigned global, unsigned *out) {
    for (unsigned i = 0; i < steps; ++i) out[i] = tp_step(s, track, (from + i) % len, global);
}

static void test_stock(void) {
    TpState s; memset(&s, 0, sizeof s);
    unsigned out[40];
    play(&s, 0, 16, 0, 40, 3, out);
    for (unsigned i = 0; i < 40; ++i) CHECK(out[i] == 3, "zeroed state follows the global pattern");
    for (unsigned t = 0; t < TP_TRACKS; ++t) CHECK(tp_pattern(&s, t, 7) == 7, "every track follows");
    CHECK(tp_pattern(&s, 20, 5) == 5, "out of range follows");
}

/* A change lands exactly at the track's own loop end, at any length. */
static void test_lands_at_loop_end(void) {
    for (unsigned len = 1; len <= 64; ++len) {
        TpState s; memset(&s, 0, sizeof s);
        tp_global(&s, 0);
        unsigned out[200];
        play(&s, 4, len, 0, 1, 0, out);                       /* T5 on its first step */
        unsigned at = len > 2 ? len / 2 : 0;
        if (len > 1) play(&s, 4, len, 1, at, 0, out);         /* ... and on to step `at` */
        CHECK(tp_queue(&s, 4, 2, 0, 1) == 3, "queue A03 for T5 (len %u)", len);
        CHECK(tp_pattern(&s, 4, 0) == 0, "not yet: still A01 (len %u)", len);
        unsigned start = (at + 1) % len;
        unsigned rest = len - 1 - at;                          /* steps left in this pass */
        play(&s, 4, len, start, rest + 2 * len, 0, out);
        for (unsigned i = 0; i < rest; ++i) CHECK(out[i] == 0, "len %u: still A01 at %u", len, i);
        for (unsigned i = rest; i < rest + 2 * len; ++i) CHECK(out[i] == 2, "len %u: A03 from the loop start (%u)", len, i);
    }
}

static void test_follow_and_withdraw(void) {
    TpState s; memset(&s, 0, sizeof s);
    tp_global(&s, 1);                                          /* global A02 */
    unsigned out[64];
    play(&s, 9, 8, 0, 3, 1, out);                              /* M2 */
    tp_queue(&s, 9, 5, 1, 1);                                  /* A06 */
    play(&s, 9, 8, 3, 5 + 8, 1, out);
    CHECK(out[4] == 1 && out[5] == 5 && out[12] == 5, "M2 on A06 from its next loop");
    play(&s, 9, 8, 0, 3, 1, out);                              /* mid-pass: steps 1..3 */
    CHECK(tp_queue(&s, 9, 1, 1, 1) == TP_TO_FOLLOW, "the global pattern's key queues FOLLOW");
    play(&s, 9, 8, 3, 5 + 1, 1, out);
    CHECK(out[4] == 5 && out[5] == 1, "back on A02 at its loop end");
    /* Withdraw: ask for what the track already plays before it lands. */
    tp_queue(&s, 9, 7, 1, 1);
    CHECK(s.next[9] == 8, "A08 queued");
    tp_queue(&s, 9, 1, 1, 1);
    CHECK(s.next[9] == 0, "the global pattern again withdraws it (the track follows already)");
    play(&s, 9, 8, 1, 16, 1, out);
    for (unsigned i = 0; i < 16; ++i) CHECK(out[i] == 1, "nothing landed");
}

static void test_global_change_clears(void) {
    TpState s; memset(&s, 0, sizeof s);
    unsigned out[8];
    CHECK(tp_global(&s, 0) == 0, "first sight is not a change");
    tp_queue(&s, 0, 4, 0, 0);                                  /* stopped: T1 on A05 at once */
    tp_queue(&s, 1, 6, 0, 1);                                  /* playing: T2 queues A07 */
    CHECK(tp_pattern(&s, 0, 0) == 4 && s.next[1] == 7, "set and queued");
    CHECK(tp_global(&s, 0) == 0, "the same global pattern changes nothing");
    CHECK(tp_global(&s, 2) == 1, "a new global pattern clears");
    CHECK(tp_pattern(&s, 0, 2) == 2 && s.next[1] == 0, "every track follows A03");
    play(&s, 1, 4, 0, 8, 2, out);
    for (unsigned i = 0; i < 8; ++i) CHECK(out[i] == 2, "T2's queued change is gone");
    CHECK(tp_global(&s, 2) == 0, "nothing to clear the second time");
    tp_queue(&s, 0, 4, 2, 0);                                  /* T1 on A05 */
    CHECK(tp_global(&s, 1 * 16 + 2) == 1, "B03, the same pattern number in bank B, clears");
    tp_global(&s, 255);                                        /* P16 */
    tp_queue(&s, 0, 4, 15, 0);
    CHECK(tp_global(&s, 255) == 0 && tp_pattern(&s, 0, 15) == 4, "P16 seen again changes nothing");
}

static void test_stopped_applies_at_once(void) {
    TpState s; memset(&s, 0, sizeof s);
    tp_global(&s, 0);
    tp_queue(&s, 15, 9, 0, 0);
    CHECK(tp_pattern(&s, 15, 0) == 9 && s.next[15] == 0, "M8 on A10 at once while stopped");
    unsigned out[4];
    tp_restart(&s);
    play(&s, 15, 16, 0, 4, 0, out);
    CHECK(out[0] == 9 && out[3] == 9, "PLAY plays A10 from step 1");
}

/* The look-ahead names what then plays, also across the loop end and
 * with a change pending. */
static void test_peek(void) {
    for (unsigned len = 1; len <= 33; len += 4) {
        TpState s; memset(&s, 0, sizeof s);
        tp_global(&s, 0);
        unsigned predicted = tp_peek(&s, 2, 0, len, 0);
        for (unsigned i = 0; i < 4 * len; ++i) {
            unsigned raw = i % len;
            if (i == len + 1) {                                /* the key stub then has stock */
                tp_queue(&s, 2, 11, 0, 1);                     /* prepare its steps again     */
                predicted = tp_peek(&s, 2, raw, len, 0);
            }
            unsigned now = tp_step(&s, 2, raw, 0);
            CHECK(now == predicted, "len %u step %u: look-ahead %u, played %u", len, i, predicted, now);
            CHECK(tp_peek(&s, 2, raw + 1 < len ? raw + 1 : len, len, 0) == tp_peek(&s, 2, raw + 1 < len ? raw + 1 : 0, len, 0),
                  "len %u: raw == len and raw 0 agree", len);
            predicted = tp_peek(&s, 2, raw + 1 < len ? raw + 1 : len, len, 0);
        }
    }
}

/* PLAY restarts the counters: a pending change lands on the first step;
 * MASTER LENGTH restarts (the same step twice) are loop starts too. */
static void test_restart(void) {
    TpState s; memset(&s, 0, sizeof s);
    tp_global(&s, 0);
    unsigned out[20];
    play(&s, 6, 16, 0, 5, 0, out);
    tp_queue(&s, 6, 3, 0, 1);
    tp_restart(&s);
    CHECK(tp_step(&s, 6, 0, 0) == 3, "PLAY: the queued change lands on step 1");
    TpState m; memset(&m, 0, sizeof m);
    tp_global(&m, 0);
    for (unsigned r = 0; r < 15; ++r) tp_step(&m, 6, r, 0);
    tp_step(&m, 6, 0, 0);                                      /* 15 steps under master 16: 0..14, 0 */
    tp_queue(&m, 6, 8, 0, 1);
    CHECK(tp_step(&m, 6, 0, 0) == 8, "the same step again (master restart) is a loop start");
}

static void test_label(void) {
    TpState s; memset(&s, 0, sizeof s);
    char out[16];
    tp_global(&s, 0);
    tp_queue(&s, 4, 2, 0, 1);
    CHECK(strcmp(tp_label(&s, 4, 0, out), "T5 > A03") == 0, "label %s", out);
    tp_queue(&s, 9, 15, 0, 0);
    CHECK(strcmp(tp_label(&s, 9, 15, out), "M2 > P16") == 0, "label %s", out);
    tp_queue(&s, 9, 0, 0, 1);
    CHECK(strcmp(tp_label(&s, 9, 15, out), "M2 FOLLOWS") == 0, "label %s", out);
    CHECK(strcmp(tp_label(&s, 0, 0, out), "T1 FOLLOWS") == 0, "label %s", out);
    CHECK(tp_queue(&s, 16, 0, 0, 1) == 0 && tp_queue(&s, 0, 16, 0, 1) == 0, "out of range");
}

int main(void) {
    test_stock();
    test_lands_at_loop_end();
    test_follow_and_withdraw();
    test_global_change_clears();
    test_stopped_applies_at_once();
    test_peek();
    test_restart();
    test_label();
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("TRACK PATTERNS engine: all host tests passed\n");
    return 0;
}
