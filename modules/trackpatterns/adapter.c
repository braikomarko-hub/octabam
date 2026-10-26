/* TRACK PATTERNS -- the firmware side: reads the sequencer's own state,
 * keeps the engine's state in loader-owned DRAM, and is what the detours
 * call. Every address is cited here or in INVESTIGATION.md.
 *
 * Compiled with -DTP_HOST, the firmware addresses become an array so the
 * glue can be tested on the host (test_adapter.c). */
#include "trackpattern.h"

#ifdef TP_HOST
volatile uint8_t *tp_host_addr(uint32_t address);
#define ADDR(a) tp_host_addr((uint32_t)(a))
#else
#define ADDR(a) ((volatile uint8_t *)(uintptr_t)(a))
#endif
#define U8(a)  (*(volatile uint8_t *)ADDR(a))
#define U32(a) (*(volatile uint32_t *)ADDR(a))

/* --- the sequencer's own state (INVESTIGATION.md "Anchors") --- */
enum {
    SEQ_TRANSPORT  = 0x800065b8u, /* 0 stopped, 1 playing (EUCLID, emu_frames.py) */
    SEQ_BANK       = 0x800065bdu, /* playing bank (DIRECT JUMP)                   */
    SEQ_PATTERN    = 0x800065beu, /* playing pattern                              */
    SEQ_COUNTERS   = 0x800064d0u, /* per-track step counters, tracks 0..15 (KYOTI) */
    BANK_BLOB      = 0x400e21e0u, /* bank 0 in RAM (STEP_LOCKS.md section 1)      */
    BANK_STRIDE    = 0x9b340u,
    PATTERN_STRIDE = 0x8ed8u,
    AUDIO_TRACK    = 0x91au,      /* audio track record stride                    */
    MIDI_TRACKS    = 0x48d0u,     /* MIDI track records: pattern + 0x48d0 + t*0x8b0 */
    MIDI_TRACK     = 0x8b0u,
    TRK_LENGTH     = 0x50u,       /* audio track length (the advance's a4@(80))   */
    MIDI_LENGTH    = 0x28u,       /* MIDI track length (the advance's a4@(18680)) */
    PAT_LENGTH     = 0x8e53u,     /* pattern length (SCALE MODE NORMAL)           */
    PAT_SCALE_MODE = 0x8e55u,     /* 0 NORMAL, else PER TRACK                     */
};

/* --- the keys (INVESTIGATION.md "Anchors") --- */
enum {
    KEY_STATE   = 0x46c7d8eeu, /* + 24 * code: nonzero while the key is held (1; 2
                                  once a layer opened over it); output-matrix reads it too */
    KEY_STRIDE  = 24u,
    KEY_TRACK_1 = 0x10u,       /* TRACK 1..8 are key codes 0x10..0x17              */
    MIDI_MODE   = 0x80000012u, /* nonzero: the TRACK keys address M1..M8 (Play Modes) */
};

/* --- the trig LEDs (INVESTIGATION.md "Anchors"; octabam PANEL.md section 8) --- */
enum {
    LED_ON      = 0x460ba98cu, /* steady on/off bits: LED id n = byte n / 8, bit n % 8;
                                  trig key k is the pair 2k (sample trigs) and 2k + 1 */
    LED_SLOTS   = 0x460e762cu, /* + 14 * slot: the LED callback the dispatcher calls   */
    LED_MAIN    = 0x40043fdcu, /* the main page's: GRID REC trigs, TRACKS mode flashes */
    LED_PATTERN = 0x400353d4u, /* the PATTERN layer's: the patterns on the trig keys   */
    UI_TRACK    = 0x100b14ccu, /* the current track 0..7 (MIDI mode: M1..M8)           */
    LIGHT_TRACK = 0x80000000u, /* the track the running light follows (0x40044516)     */
    UI_PATTERN  = 0x100b14d0u, /* the pattern the UI shows and edits                   */
    UI_PAGE     = 0x460d1e04u, /* the trig page GRID REC shows, 0..3                   */
    GRID_REC    = 0x460d1736u,
    TRIG_MODE   = 0x460d16f0u, /* 0 TRACKS                                             */
    TIMER       = 0xfc07c00cu, /* DTIM3's count: 132 MHz, free-running                 */
    BLINK_SHIFT = 26u,         /* half a period = 2^26 counts, about 0.5 s             */
};

/* Loader-owned DRAM, zeroed at boot (hooks.s): zero = every track follows. */
extern TpState tp_state;
extern char tp_toast[16];

static unsigned tp_playing(void) { return U32(SEQ_TRANSPORT) == 1; }

static unsigned tp_global_pattern(void) {
    unsigned pattern = U8(SEQ_PATTERN);
    return pattern < TP_PATTERNS ? pattern : 0;
}

static unsigned tp_global_bank(void) {
    unsigned bank = U8(SEQ_BANK);
    return bank < 16 ? bank : 0;
}

/* Every entry first follows the global pattern: a change of it (key,
 * chain, arranger, a bank change too) clears the overrides, as v1
 * specifies. */
static unsigned tp_sync(void) {
    unsigned global = tp_global_pattern();
    tp_global(&tp_state, tp_global_bank() * TP_PATTERNS + global);
    return global;
}

/* The tick, once per track step, before the step handler: the pattern
 * argument the handler gets for this track. Tracks 8..15 are M1..M8.
 * `stock` and `stock_bank` are what stock chose: the playing pattern, or
 * (just before a global pattern change lands) the next one, which the tick
 * reads from 0x800065c1 / 0x800065c2 for the step it prepares across the
 * change. Then every track follows stock: the change is about to clear the
 * overrides anyway. */
unsigned tp_seq_pattern(unsigned track, unsigned raw, unsigned stock, unsigned stock_bank) {
    unsigned global = tp_sync();
    unsigned pattern = tp_step(&tp_state, track, raw, global);
    return stock == global && stock_bank == tp_global_bank() ? pattern : stock;
}

/* The rebuild after an edit, and any look-ahead: the pattern the track
 * will read on `raw`. While stopped the next run starts every track over,
 * so a queued change has landed by then. Changes nothing. */
unsigned tp_peek_pattern(unsigned track, unsigned raw, unsigned len, unsigned stock) {
    unsigned global = tp_sync();
    if (stock != global) return stock;
    if (!tp_playing()) return tp_pattern(&tp_state, track, global);
    return tp_peek(&tp_state, track, raw, len, global);
}

/* The pattern whose length a track loops at. */
unsigned tp_length_pattern(unsigned track) {
    unsigned global = tp_sync();
    return tp_pattern(&tp_state, track, global);
}

/* The per-track advance, as it compares the track's counter with its
 * length: the length to use. A track that follows the global pattern
 * keeps `stock_len` (what stock read); a track on another pattern reads the
 * same field from that pattern: its own length under SCALE MODE PER TRACK,
 * the pattern length under NORMAL (the playing pattern's mode decides, as
 * in stock). */
unsigned tp_track_length(unsigned track, unsigned stock_len) {
    unsigned global = tp_sync();
    unsigned pattern = tp_pattern(&tp_state, track, global);
    if (pattern == global || track >= TP_TRACKS) return stock_len;
    unsigned bank = U8(SEQ_BANK);
    if (bank > 15) return stock_len;
    uint32_t playing = BANK_BLOB + bank * BANK_STRIDE + global * PATTERN_STRIDE;
    uint32_t source = BANK_BLOB + bank * BANK_STRIDE + pattern * PATTERN_STRIDE;
    uint32_t at;
    if (!U8(playing + PAT_SCALE_MODE))
        at = source + PAT_LENGTH;
    else if (track < 8)
        at = source + track * AUDIO_TRACK + TRK_LENGTH;
    else
        at = source + MIDI_TRACKS + (track - 8) * MIDI_TRACK + MIDI_LENGTH;
    unsigned len = U8(at);
    return len ? len : stock_len;
}

/* PLAY (or an external start): every track starts its first pass again. */
void tp_transport_start(void) {
    tp_restart(&tp_state);
}

/* The key gesture, from the key handler: queue `pattern` (0..15) for
 * `track` and write the popup text into tp_toast (hooks.s opens the stock
 * toast; key-handler context only). Returns 0 when nothing was queued. */
unsigned tp_key(unsigned track, unsigned pattern) {
    unsigned global = tp_sync();
    unsigned code = tp_queue(&tp_state, track, pattern, global, tp_playing());
    if (!code) return 0;
    tp_label(&tp_state, track, U8(SEQ_BANK), tp_toast);
    return 1;
}

/* PATTERN held and a trig pressed (hooks.s, inside the PATTERN layer's trig
 * handler): with a TRACK key held as well, the trig queues its pattern for
 * that track instead of changing the global pattern. The lowest held TRACK
 * key wins. Returns 0 to leave the press to stock, 1 when it took the press,
 * 2 when it took it and queued a change (tp_toast filled). */
static unsigned tp_held_track(void) {
    for (unsigned n = 0; n < 8; ++n)
        if (U32(KEY_STATE + KEY_STRIDE * (KEY_TRACK_1 + n)))
            return U32(MIDI_MODE) ? n + 8u : n;
    return TP_TRACKS;
}

unsigned tp_gesture(unsigned pattern) {
    unsigned track = tp_held_track();
    return track < TP_TRACKS ? 1u + tp_key(track, pattern) : 0;
}

/* --- the trig LEDs --- */

static void tp_led(unsigned id, unsigned on) {
    uint8_t bit = (uint8_t)(1u << (id % 8));
    uint8_t now = U8(LED_ON + id / 8);
    U8(LED_ON + id / 8) = on ? (uint8_t)(now | bit) : (uint8_t)(now & ~bit);
}

/* The slow blink's dark half. */
static unsigned tp_blink_dark(void) { return (U32(TIMER) >> BLINK_SHIFT) & 1u; }

/* `track`'s trigs in `pattern` of the playing bank, 16 steps of `page`:
 * bit k = step 16 * page + k. The trig mask is the track record's first 8
 * bytes, big-endian, step s at bit s (STEP_LOCKS.md; the GRID REC drawing
 * 0x40034bd4 reads its halfword 3 - page). */
static unsigned tp_trigs(unsigned track, unsigned pattern, unsigned page) {
    uint32_t at = BANK_BLOB + tp_global_bank() * BANK_STRIDE + pattern * PATTERN_STRIDE
                + (track < 8 ? track * AUDIO_TRACK : MIDI_TRACKS + (track - 8) * MIDI_TRACK)
                + 6u - 2u * (page & 3u);
    return (unsigned)U8(at) << 8 | U8(at + 1);
}

/* After the LED dispatcher 0x4007e998 has run `slot`'s callback, before the
 * flush (hooks.s): only a track that plays its own pattern changes what
 * stock drew. Stock's running light (both LEDs of the playhead's key) stays.
 *  - The main page, GRID REC: the trigs stay stock's (the pattern the keys
 *    edit) and blink slowly: this track does not play them. In the dark
 *    half every trig LED goes out; the return value asks hooks.s to light
 *    the running light again (tp_playhead).
 *  - The main page, TRACKS trig mode outside GRID REC, where stock shows
 *    only the running light: the trigs of the pattern the track plays on
 *    the keys' first LEDs, blinking slowly, over it, from the 16 steps its
 *    playhead is in (as the running light walks them).
 *  - The PATTERN layer with TRACK n held: the key of the pattern T_n plays
 *    is lit as the current one, a change it has queued as a queued one, and
 *    the global pattern's key as one with content.
 * Returns the running light's track (0x80000000, MIDI as 8 + t) when it
 * has to be drawn again, else -1. */
int tp_leds(unsigned slot) {
    uint32_t callback = U32(LED_SLOTS + 14u * slot);
    unsigned global = tp_sync();
    if (callback == LED_MAIN) {
        unsigned track = U8(UI_TRACK);
        if (track > 7) return -1;
        if (U32(MIDI_MODE)) track += 8;
        unsigned pattern = tp_pattern(&tp_state, track, global);
        if (pattern == global) return -1;
        if (U32(GRID_REC)) {
            if (!tp_blink_dark()) return -1;
            for (unsigned id = 0; id < 32; ++id) tp_led(id, 0);
            return (int)(U8(LIGHT_TRACK) % 8u + (U32(MIDI_MODE) ? 8u : 0u));
        }
        if (U32(TRIG_MODE) == 0 && !tp_blink_dark()) {
            /* the page the track's playhead is on, as stock's running light */
            unsigned trigs = tp_trigs(track, pattern, U8(SEQ_COUNTERS + track) / 16u);
            for (unsigned k = 0; k < 16; ++k)
                if ((trigs >> k) & 1u) tp_led(2 * k, 1);
        }
    } else if (callback == LED_PATTERN) {
        unsigned track = tp_held_track();
        if (track >= TP_TRACKS) return -1;
        unsigned pattern = tp_pattern(&tp_state, track, global);
        unsigned shown = U8(UI_PATTERN) % TP_PATTERNS;
        if (pattern != shown) {
            tp_led(2 * shown, 0);
            tp_led(2 * shown + 1, 1);
        }
        tp_led(2 * pattern, 1);
        tp_led(2 * pattern + 1, 0);
        uint8_t next = tp_state.next[track];
        if (next) {
            unsigned queued = next == TP_TO_FOLLOW ? global : next - 1u;
            tp_led(2 * queued, 1);
            tp_led(2 * queued + 1, 1);
        }
    }
    return -1;
}

/* The running light again, as stock draws it (0x40044526..0x40044574):
 * `step` from the UI step query 0x4009b2b0, shown in GRID REC only when it
 * is on the page shown. */
void tp_playhead(unsigned step) {
    if (U32(GRID_REC) && step / 16u != U32(UI_PAGE)) return;
    tp_led(2 * (step % 16u), 1);
    tp_led(2 * (step % 16u) + 1, 1);
}
