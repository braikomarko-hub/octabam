| TRACK PATTERNS -- the hand-written part of the unit: the detour stubs,
| the register-saving entries they call, and the state the C keeps in
| loader-owned DRAM. generate.py appends this to the compiled
| trackpattern.c + adapter.c.
|
| Sites read from the contributor's original 1.40C (21 Oct 2026,
| INVESTIGATION.md section 4). Each stub is reached by a six-byte `jmp`
| the manifest plants over whole stock instructions (two sites pad an
| eight-byte span with a nop), replays them, and jumps back. None of the
| spans overlaps Play Modes' detours: its step-load and rebuild stubs jump
| back to the instruction right before (tick) or exactly at (rebuild) these
| sites, so the two compose.
        .text
        .balign 4
        .global tp_pattern_entry, tp_peek_entry, tp_length_entry

| tp_pattern_entry(track, raw, stock, stock_bank) -> d0 = the pattern the
| step handler reads. The tick's form: lands a queued change at the track's
| loop start. Saves everything the C may clobber except d0.
tp_pattern_entry:
        lea     -12(%sp),%sp
        movem.l %d1/%a0-%a1,(%sp)
        move.l  28(%sp),-(%sp)          | stock_bank
        move.l  28(%sp),-(%sp)          | stock (shifted by one push)
        move.l  28(%sp),-(%sp)          | raw (by two)
        move.l  28(%sp),-(%sp)          | track (by three)
        jsr     tp_seq_pattern
        lea     16(%sp),%sp
        movem.l (%sp),%d1/%a0-%a1
        lea     12(%sp),%sp
        rts

| tp_peek_entry(track, raw, len, stock) -> d0: the rebuild's form, no
| state change.
tp_peek_entry:
        lea     -12(%sp),%sp
        movem.l %d1/%a0-%a1,(%sp)
        move.l  28(%sp),-(%sp)          | stock
        move.l  28(%sp),-(%sp)          | len
        move.l  28(%sp),-(%sp)          | raw
        move.l  28(%sp),-(%sp)          | track
        jsr     tp_peek_pattern
        lea     16(%sp),%sp
        movem.l (%sp),%d1/%a0-%a1
        lea     12(%sp),%sp
        rts

| tp_length_entry(track, stock_len) -> d0: the length the per-track
| advance compares the track's counter with.
tp_length_entry:
        lea     -12(%sp),%sp
        movem.l %d1/%a0-%a1,(%sp)
        move.l  20(%sp),-(%sp)          | stock_len
        move.l  20(%sp),-(%sp)          | track (shifted by one push)
        jsr     tp_track_length
        addq.l  #8,%sp
        movem.l (%sp),%d1/%a0-%a1
        lea     12(%sp),%sp
        rts

| ---- the detour stubs ------------------------------------------------------
        .global tp_audio_tick, tp_midi_tick, tp_audio_rebuild, tp_midi_rebuild
        .global tp_audio_length, tp_midi_length, tp_pattern_key, tp_led_pass

| 0x400a2d76, the tick's audio pass, pushing 0x4009d1e8(track, bank,
| pattern, step, n): the step is already pushed, the pattern stock chose is
| in d3 (the playing one, or 0x800065c1 for a step of the next pattern),
| the track in d5. Displaced: movel %d3,%sp@- (2) ; movel %sp@(86),%sp@-
| (4, the bank: stored at 0x400a2d64, 82(%sp) here). d0/d1/a0/a1 are not
| read again before the call. The raw step is read from the stock counter
| itself, so Play Modes' mapping (in d0 when both are built) does not reach
| the wrap test.
tp_audio_tick:
        move.l  82(%sp),-(%sp)          | stock's bank
        move.l  %d3,-(%sp)              | stock's pattern
        lea     0x800064d0,%a0
        mvz.b   %a0@(0,%d5:l),%d0       | raw: this track's stock counter
        move.l  %d0,-(%sp)              | raw
        move.l  %d5,-(%sp)              | track 0..7
        jsr     tp_pattern_entry        | d0 := the pattern; d1/a0/a1 kept
        lea     16(%sp),%sp
        move.l  %d0,-(%sp)              | the pattern argument
        move.l  86(%sp),-(%sp)          | displaced: the bank
        jmp     0x400a2d7c              | movel %d5,%sp@- (the track)

| 0x400a39c0, the tick's MIDI pass, pushing 0x4009cf4c(track, bank,
| pattern, step, n): pattern in d4, bank in d3 (both from 0x400a39b0),
| MIDI track 0..7 in d7. Displaced: movel %d4,%sp@- ; movel %d3,%sp@- ;
| movel %d7,%sp@- (6). The MIDI counters follow the audio ones:
| 0x800064d8[t].
tp_midi_tick:
        move.l  %d3,-(%sp)              | stock's bank
        move.l  %d4,-(%sp)              | stock's pattern
        lea     0x800064d8,%a0
        mvz.b   %a0@(0,%d7:l),%d0       | raw
        move.l  %d0,-(%sp)              | raw
        move.l  %d7,%d0
        addq.l  #8,%d0
        move.l  %d0,-(%sp)              | the engine's tracks 8..15
        jsr     tp_pattern_entry
        lea     16(%sp),%sp
        move.l  %d0,-(%sp)              | the pattern argument
        move.l  %d3,-(%sp)              | displaced: the bank
        move.l  %d7,-(%sp)              | displaced: the track
        jmp     0x400a39c6              | the call

| 0x4009dc8c, the working-set rebuild 0x4009da20 (after an edit) for an
| audio track: step in d2, track in d6. Displaced: mvsb 0x800065be,%d4
| (6) ; movel %d4,%sp@- (2) -- the manifest pads the eight bytes with a
| nop. d4 keeps the global pattern, as stock leaves it; only the pushed
| argument changes. d0 is loaded with the bank next.
tp_audio_rebuild:
        mvs.b   0x800065be,%d4          | displaced: the global pattern
        move.l  %d4,-(%sp)              | stock's pattern
        clr.l   -(%sp)                  | len: not known here (0)
        move.l  %d2,-(%sp)              | raw
        move.l  %d6,-(%sp)              | track 0..7
        jsr     tp_peek_entry           | d0 := the pattern
        lea     16(%sp),%sp
        move.l  %d0,-(%sp)              | the pattern argument
        jmp     0x4009dc94              | mvsb 0x800065bd,%d0 (the bank)

| 0x4009e3e2, the rebuild's MIDI branch (d6 > 7: the engine's 8..15): the
| step is still in d2. Displaced: mvsb 0x800065be,%d2 (6) ; movel %d2,%sp@-
| (2), padded with a nop. Stock leaves the global pattern in d2.
tp_midi_rebuild:
        mvs.b   0x800065be,%d0          | stock's pattern
        move.l  %d0,-(%sp)
        clr.l   -(%sp)                  | len
        move.l  %d2,-(%sp)              | raw (the step, not yet overwritten)
        move.l  %d6,-(%sp)              | track 8..15
        jsr     tp_peek_entry
        lea     16(%sp),%sp
        mvs.b   0x800065be,%d2          | displaced: d2 as stock leaves it
        move.l  %d0,-(%sp)              | the pattern argument
        jmp     0x4009e3ea              | mvsb 0x800065bd,%d3 (the bank)

| 0x400a3d88, the per-track advance (audio, track 0..7 in d3): the new
| counter in d1, the length stock read in d0 (track +0x50 under PER TRACK,
| the pattern's +0x8e53 under NORMAL). Displaced: mvzb %d1,%d1 ; mvsb
| %d0,%d0 ; cmpl %d1,%d0 (6); the bgts that follows tests our compare.
tp_audio_length:
        mvz.b   %d1,%d1                 | displaced
        mvs.b   %d0,%d0                 | displaced
        move.l  %d0,-(%sp)              | the length stock read
        move.l  %d3,-(%sp)              | track 0..7
        jsr     tp_length_entry         | d0 := this track's length; d1 kept
        addq.l  #8,%sp
        cmp.l   %d1,%d0                 | displaced compare
        jmp     0x400a3d8e              | bgts 0x400a3dae

| 0x400a3ea8, the same for the MIDI tracks (d3 = 8..15, the engine's own
| numbering; the length from the MIDI record's +0x28).
tp_midi_length:
        mvz.b   %d1,%d1
        mvs.b   %d0,%d0
        move.l  %d0,-(%sp)
        move.l  %d3,-(%sp)              | track 8..15
        jsr     tp_length_entry
        addq.l  #8,%sp
        cmp.l   %d1,%d0
        jmp     0x400a3eae              | bgts 0x400a3eca

| 0x40056b50, inside the PATTERN layer's trig press handler 0x40056b2c(code)
| (key map 0x400bef04: PATTERN held, or latched by a tap, and a trig
| pressed): d2 = the trig, 0..15, a2 = the screen redraw 0x400418e0.
| Stock has already cancelled the latch's timer and marked a trig pressed
| (0x460d173e = -1); next it selects the global pattern (the first trig of
| this hold) or chains (another). With a TRACK key held, tp_gesture takes
| the press instead: this stub redraws as stock does, opens the toast, has
| stock prepare every track's step again, and joins stock where it marks
| the trig in the hold's mask (0x40056ba4), so the releases of the trig and
| of PATTERN close the layer as stock. Key-handler context: the toast and
| the rebuild are safe here (as Play Modes' pm_key_entry). d0/d1/a0/a1 are
| free (stock reloads them); d2/a2 survive the C. Displaced: tstw
| 0x460d1ab6 (6); the bnes after it tests the replayed one.
        .equ    TOAST_TIME, 0x3c        | 1 s at the 60 Hz UI tick (> 0, Kyoti)
tp_pattern_key:
        move.l  %d2,-(%sp)              | the trig: the pattern 0..15
        jsr     tp_gesture              | 0 stock, 1 taken, 2 taken and queued
        addq.l  #4,%sp
        tst.l   %d0
        beq.s   .Lkey_stock
        move.l  %d0,-(%sp)
        jsr     (%a2)                   | stock's redraw, as after its select
        move.l  (%sp)+,%d0
        subq.l  #1,%d0
        beq.s   .Lkey_taken
        pea     TOAST_TIME
        pea     tp_toast
        jsr     0x4005a2b8              | the stock toast (text, duration)
        addq.l  #8,%sp
        pea     0xffffffff              | -1: every track's prepared step
        jsr     0x4009da20              | the rebuild an edit calls
        addq.l  #4,%sp
.Lkey_taken:
        jmp     0x40056ba4              | stock: mark the trig, then 0x40027de4
.Lkey_stock:
        tst.w   0x460d1ab6              | displaced
        jmp     0x40056b56              | bnes 0x40056b98

| 0x4007e9b6, inside the LED dispatcher 0x4007e998(slot): it calls the LED
| callback the RAM table holds for the slot (0x460e762c + 14 * slot: the
| main page's 0x40043fdc, the PATTERN layer's 0x400353d4, ...), then
| restores d2 and tail-calls the flush 0x400136a8 at 0x4007e9bc. The stub
| replays the call, lets tp_leds adjust the trig LEDs the callback drew
| (steady bits 0x460ba98c, nothing else), and joins stock before the
| flush, which sends what changed. When tp_leds put the trig LEDs out
| (GRID REC's dark half) it names a track, and the stub draws that track's
| running light again from stock's own answers: running 0x4009b290(track)
| == 1, then the step 0x4009b2b0(track) (Play Modes' mapped step when it
| is installed), as 0x40044516..0x40044528 do. d2 = the slot, kept by
| every callee; d0/d1/a0/a1 are free (the flush takes none). No branch
| lands inside the span (the dispatcher's beqs goes to 0x4007e9bc).
| Displaced: movel %d2,%sp@- ; jsr %a0@ ; addql #4,%sp (6).
tp_led_pass:
        move.l  %d2,-(%sp)              | displaced: the slot
        jsr     (%a0)                   | displaced: the slot's LED callback
        addq.l  #4,%sp                  | displaced
        move.l  %d2,-(%sp)
        jsr     tp_leds                 | a track on its own pattern: the trig LEDs
        addq.l  #4,%sp
        tst.l   %d0
        bmi.s   .Lled_done
        move.l  %d0,-(%sp)              | the running light's track
        move.l  %d0,-(%sp)
        jsr     0x4009b290              | running?
        addq.l  #4,%sp
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bne.s   .Lled_drop
        jsr     0x4009b2b0              | its step (the track is still on the stack)
        move.l  %d0,(%sp)
        jsr     tp_playhead             | light its key again
.Lled_drop:
        addq.l  #4,%sp
.Lled_done:
        jmp     0x4007e9bc              | movel %sp@+,%d2 ; jmp 0x400136a8 (the flush)

| Explicitly initialised, loader-owned DRAM, zeroed: every track follows
| the global pattern until a change is queued. The C's _Static_assert pins
| TpState at 4 x 16 + 4 bytes.
        .balign 4
        .global tp_state, tp_toast
tp_state:
        .zero   68
tp_toast:
        .zero   16                      | popup text, e.g. "T5 > A03"
