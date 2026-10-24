| TRACK MENU v0 (prototype, 24 Oct 2026) -- hold a track key ~1 s: that track's menu.
|
| NAVIGATION ONLY. Every value lives in this unit and nothing reads it yet: MORPH keeps its own
| window and settings ([TRACK]+[UP]), and no Euclidean pattern is printed. v0 is for trying the
| gesture, the pages and the keys on the unit before any behaviour is wired in. Nothing is saved.
|
|   T held ~1 s, no other key --> the menu of that track opens (and stays open when T is let go)
|   LEFT / RIGHT --------------> page: MORPH, EUCLACID, EUCL LIVE (the page is remembered per
|                                track while the unit is on)
|   knobs A..F ----------------> the page's settings (ARMED: nothing changes in the sound yet)
|   the SAME T ----------------> closes the menu; toast "Tn START" (v0: the start is only shown)
|   NO ------------------------> closes the menu, nothing starts
|   YES / CUE (EUCLACID pages) > "PRINT" / "UNDO" flashed in the title bar (v0: shown only)
|   other T keys, trigs, page  > swallowed while the menu is open; PLAY and STOP keep working
|   keys, FUNC, PATTERN, BANK, REC, MIDI, TEMPO, UP, DOWN, LEVEL
|
| The long press (measured from the user's 1.40C, 24 Oct 2026):
|   * the eight track records of the MKI key table 0x400bfc10 and of the MKII one 0x400c01f4 have
|     press = release = repeat = 0x40040250 (one handler for every event), the sub-map 0x400d164a
|     (the [TRACK]-held layer) and repeat delay 30. The build repoints only their PRESS field at
|     tm_tpress, which calls the stock handler first and then arms the long press.
|   * a soft timer (TIMER 0x40031a0c, the period MORPH and BRAIN use: two ticks, ~17 ms) counts
|     while the track key stays the only one held: HELD 0x460fab40 = 1 << t (written by the stock
|     track handler) and the panel's key rows 0x46100b18[0..7] (docs/firmware/PANEL.md 4b) show no
|     key that was not already down at the press. FUNC or CUE down at the press (mute, cue): no
|     menu. Another key, another track, or the release before the time: cancelled.
|   * a key held while a layer is pushed keeps its cached handlers (docs/firmware/MAINMENU.md 6c):
|     T still has the stock handler when the menu opens, so its release reaches the stock (which
|     pops the [TRACK] layer and clears HELD). Once HELD shows T up, the menu's layer is popped
|     and pushed again, so the next press of T reaches tm_trk.
| Inferred, not measured: that a soft timer callback may create a window (MORPH creates its window
| from a key handler; the stock defers window work to timer callbacks, FUN_40063660); that +32
| bit 0x20 of the window table 0x46c7d34c (tools/emu/lcd_view.py) marks every visible window; that
| the panel rows read 0 for keys that are up (no stuck bit: the snapshot at the press covers one).
| Not seen by the long press: a knob turned while T is held (encoders are not in the key rows).

        .text
        .globl  tm_tpress, tm_tick, tm_set

        .macro  KEYREC code, press, release
        .byte   \code, 0
        .long   \press, \release
        .space  16
        .endm

        .set    STOCK_TKEY, 0x40040250  | the stock track key handler (press, release, repeat)
        .set    HELD,     0x460fab40    | held track keys, bit t (stock, as MORPH reads it)
        .set    ROWS,     0x46100b18    | the panel's key rows: key code = row * 8 + bit
        .set    MIDIMODE, 0x80000012    | nonzero = MIDI mode
        .set    WINTAB,   0x46c7d34c    | five 56-byte window entries; +32 bit 0x20 = visible
        .set    NOTIFY,   0x4005a2b8    | (text, dur): the toast, key-handler context
        .set    WCREATE,  0x4005829c    | (w, h, 0, 0, class, closed) -> window
        .set    WFRAME,   0x40056f4c    | (window)
        .set    WDESTROY, 0x40055db4    | (&window)
        .set    CLEAR,    0x40035624    | (surface)
        .set    FONT,     0x400ba876    | the small UI font, 6 px
        .set    TEXT,     0x40012bd8    | (font, surface, x, y, limit, str)
        .set    TWIDTH,   0x40012f30    | (font, limit, str) -> pixels
        .set    INVERT,   0x40012254    | (surface, x1, y1, x2, y2, -1): an EOR bar
        .set    SPRINTF,  0x40013a08
        .set    LPUSH,    0x40031494    | (layer)
        .set    LPOP,     0x4003146c    | (layer)
        .set    TIMER,    0x40031a0c    | (period, callback) -> slot
        .set    UNTIMER,  0x40031abc    | (slot)
        .set    SCRDIRTY, 0x46c7c72c

        .set    TICK,     2             | the soft timer: two ticks, ~17 ms
        .set    LONG,     58            | ~1 s of ticks for the long press
        .set    FLASH,    40            | ~0.7 s: PRINT / UNDO in the title bar
        .set    NPAGES,   3
        .set    T_MASKS,  0x00240000    | rows 4..7 as a long: FUNC 0x2d (bit 21), CUE 0x2a (bit 18)

        .set    WINW,     116
        .set    WINH,     64
        .set    Y_TITLE,  54
        .set    Y_ROW0,   44            | six rows, 8 px apart: 44 36 28 20 12 4
        .set    X_LAB,    6
        .set    X_VAL,    110

| ---------------------------------------------------------------- the long press
| tm_tpress -- the PRESS field of the eight stock track records: handler(code @4, event @8).
| The stock handler first, unchanged; then, if no menu is open and not in MIDI mode, the long
| press of this track starts counting. d0/d1/a0/a1 only (d2-d7 are the caller's).
tm_tpress:
        move.l  8(%sp),-(%sp)           | event
        move.l  8(%sp),-(%sp)           | code (4(sp) before the first push)
        jsr     STOCK_TKEY
        addq.l  #8,%sp
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     tp_9                    | press only
        tst.l   tm_win
        bne     tp_9                    | a menu is open: its layer has the track keys
        mvz.b   MIDIMODE,%d0
        bne     tp_9                    | MIDI tracks: not in v0
        move.l  4(%sp),%d0
        sub.l   #0x10,%d0
        moveq   #7,%d1
        cmp.l   %d1,%d0
        bhi     tp_9                    | not a track key (unsigned: below 0x10 too)
        move.l  ROWS+4,%d1              | rows 4..7: FUNC or CUE down = mute / cue, not a menu
        and.l   #T_MASKS,%d1
        bne     tp_x
        move.l  %d0,tm_cand
        clr.l   tm_count
        addq.l  #8,%d0                  | row 2 is the third byte of the first long
        moveq   #1,%d1
        lsl.l   %d0,%d1
        not.l   %d1
        and.l   ROWS,%d1                | the keys down at the press, this track's excepted
        move.l  %d1,tm_snap0
        move.l  ROWS+4,%d1
        move.l  %d1,tm_snap1
        tst.l   tm_timer
        bpl     tp_9                    | already ticking
        pea     tm_tick
        pea     TICK
        jsr     TIMER
        addq.l  #8,%sp
        move.l  %d0,tm_timer
tp_9:   rts
tp_x:   moveq   #-1,%d0
        move.l  %d0,tm_cand
        rts

| tm_tick -- the soft timer, while a long press counts or a menu is open. d0/d1/a0/a1 only, but
| for tm_draw (which saves what it uses).
tm_tick:
        tst.l   tm_win
        bne     tk_open
        move.l  tm_cand,%d0
        bmi     tm_untimer              | nothing to do: the timer goes
        moveq   #1,%d1
        lsl.l   %d0,%d1
        cmp.l   HELD,%d1
        bne     tk_cancel               | released, or another track too
        addq.l  #8,%d0                  | a key that was not down at the press: cancelled
        moveq   #1,%d1
        lsl.l   %d0,%d1
        or.l    tm_snap0,%d1
        not.l   %d1
        and.l   ROWS,%d1
        bne     tk_cancel
        move.l  tm_snap1,%d1
        not.l   %d1
        and.l   ROWS+4,%d1
        bne     tk_cancel
        addq.l  #1,tm_count
        move.l  tm_count,%d0
        moveq   #LONG,%d1
        cmp.l   %d1,%d0
        blt     tk_9
        bsr     tm_anywin               | another window on screen: wait for it to go
        bne     tk_9
        move.l  tm_cand,%d0
        moveq   #-1,%d1
        move.l  %d1,tm_cand
        bra     tm_open
tk_cancel:
        moveq   #-1,%d0
        move.l  %d0,tm_cand
        bra     tm_untimer
tk_open:                                | the menu is open
        tst.l   tm_rebuilt
        bne     tk_o2
        move.l  tm_t,%d0                | T still down: its press went to the stock handler
        moveq   #1,%d1
        lsl.l   %d0,%d1
        and.l   HELD,%d1
        bne     tk_o2
        moveq   #1,%d0                  | T is up (the stock has seen its release): rebuild
        move.l  %d0,tm_rebuilt          | the key cache, so its next press is the menu's
        pea     TM_LAYER
        jsr     LPOP
        addq.l  #4,%sp
        pea     TM_LAYER
        jsr     LPUSH
        addq.l  #4,%sp
tk_o2:  tst.l   tm_flash
        beq     tk_9
        subq.l  #1,tm_flash
        tst.l   tm_flash
        bne     tk_9
        bra     tm_draw                 | the flash is over: the page number again
tk_9:   rts

| tm_anywin -- Z clear (bne) when a window entry is visible. Clobbers d0, d1, a0.
tm_anywin:
        lea     WINTAB+32,%a0
        moveq   #5,%d1
aw_1:   move.l  (%a0),%d0
        and.l   #0x20,%d0
        bne     aw_9
        lea     56(%a0),%a0
        subq.l  #1,%d1
        bne     aw_1
        moveq   #0,%d0                  | none: Z set
aw_9:   rts

tm_untimer:
        move.l  tm_timer,%d0
        bmi     tu_9
        move.l  %d0,-(%sp)
        jsr     UNTIMER
        addq.l  #4,%sp
        moveq   #-1,%d0
        move.l  %d0,tm_timer
tu_9:   rts

| ---------------------------------------------------------------- the menu
| tm_open -- d0 = the track. The timer keeps running (it watches T's release and the flash).
tm_open:
        move.l  %d0,tm_t
        clr.l   tm_rebuilt
        clr.l   tm_flash
        pea     tm_closed
        pea     5                       | TEMPO class, as MORPH and EUCLID FILL
        clr.l   -(%sp)
        clr.l   -(%sp)
        pea     WINH
        pea     WINW
        jsr     WCREATE
        lea     24(%sp),%sp
        move.l  %d0,tm_win
        beq     tm_untimer              | no window: nothing open, the timer goes
        move.l  %d0,-(%sp)
        jsr     WFRAME
        addq.l  #4,%sp
        pea     TM_LAYER
        jsr     LPUSH
        addq.l  #4,%sp
        moveq   #1,%d0
        move.l  %d0,tm_pushed
        bra     tm_draw

| tm_close -- the window, the layer and the timer gone; safe when already closed.
tm_close:
        tst.l   tm_win
        beq     tm_closed
        pea     tm_win
        jsr     WDESTROY
        addq.l  #4,%sp
tm_closed:                              | WCREATE's callback: another window of the class took over
        clr.l   tm_win
        bsr     tm_untimer
        tst.l   tm_pushed               | once: WDESTROY may call tm_closed itself
        beq     tc_9
        clr.l   tm_pushed
        pea     TM_LAYER
        jsr     LPOP
        addq.l  #4,%sp
tc_9:   rts

| tm_cur -- a0 = this track's settings (16 bytes, the page first), a1 = its page record, d0 = the
| page. Clobbers d1.
tm_cur:
        lea     tm_set,%a0
        move.l  tm_t,%d1
        lsl.l   #4,%d1                  | 16 bytes a track
        add.l   %d1,%a0
        mvz.b   (%a0),%d0
        moveq   #NPAGES-1,%d1
        cmp.l   %d1,%d0
        bls     cu_1
        moveq   #0,%d0                  | a stray byte: the first page
        move.b  %d0,(%a0)
cu_1:   lea     PAGES,%a1
        move.l  %d0,%d1
        lsl.l   #2,%d1                  | 12 bytes a page record: 4p + 8p
        add.l   %d1,%a1
        add.l   %d1,%a1
        add.l   %d1,%a1
        rts

| ---- the menu's keys: handler(keycode @4, event @8), event 1 = press
tm_no:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        beq     tm_close
k_9:    rts

tm_left:
        moveq   #NPAGES-1,%d0           | -1, modulo the pages
        bra     kp_1
tm_right:
        moveq   #1,%d0
kp_1:   moveq   #1,%d1
        cmp.l   8(%sp),%d1
        bne     k_9
        move.l  %d0,tm_tmp
        bsr     tm_cur                  | d0 = the page, a0 = the settings
        add.l   tm_tmp,%d0
        moveq   #NPAGES,%d1
        cmp.l   %d1,%d0
        blt     kp_2
        sub.l   %d1,%d0
kp_2:   move.b  %d0,(%a0)
        clr.l   tm_flash
        bra     tm_draw

| YES / CUE: on the EUCLACID pages (2 and 3) the title bar shows PRINT / UNDO for a moment.
tm_yes:
        lea     S_PRINT,%a0
        bra     ky_1
tm_cue:
        lea     S_UNDO,%a0
ky_1:   moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        move.l  %a0,tm_fstr
        bsr     tm_cur
        tst.l   %d0
        beq     k_9                     | the MORPH page: nothing
        moveq   #FLASH,%d0
        move.l  %d0,tm_flash
        bra     tm_draw

| a track key while the menu is open: the menu's own track starts (v0: closes and says so); any
| other track key is swallowed.
tm_trk:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        move.l  4(%sp),%d0
        sub.l   #0x10,%d0
        cmp.l   tm_t,%d0
        bne     k_9
        bsr     tm_close
        move.l  tm_t,%d0
        addq.l  #1,%d0
        move.l  %d0,-(%sp)
        pea     F_START
        pea     tm_tbuf
        jsr     SPRINTF
        lea     12(%sp),%sp
        lea     tm_tbuf,%a0
        move.l  %a0,4(%sp)              | tail-call NOTIFY(text, 0x30) in our caller's frame
        moveq   #0x30,%d0
        move.l  %d0,8(%sp)
        jmp     NOTIFY

| tm_enc -- encoder (index @4, delta @8): the page's row `index`, its value +delta, clamped.
tm_enc:
        tst.l   8(%sp)
        beq     k_9
        bsr     tm_cur                  | a0 = settings, a1 = page record
        move.l  4(%sp),%d0              | index
        cmp.l   8(%a1),%d0
        bcc     k_9                     | no row for this knob on this page
        move.l  4(%a1),%a1              | the rows
        lsl.l   #2,%d0                  | 12 bytes a row
        add.l   %d0,%a1
        add.l   %d0,%a1
        add.l   %d0,%a1
        mvz.b   4(%a1),%d0              | the byte's offset in the settings
        add.l   %d0,%a0
        mvz.b   (%a0),%d0
        add.l   8(%sp),%d0
        mvz.b   5(%a1),%d1              | min
        cmp.l   %d1,%d0
        bge     te_1
        move.l  %d1,%d0
te_1:   mvz.b   6(%a1),%d1              | max
        cmp.l   %d1,%d0
        ble     te_2
        move.l  %d1,%d0
te_2:   move.b  %d0,(%a0)
        bra     tm_draw

| ---- the paint
|  ████ T5 MORPH ███████ 1/3 █   the title bar, inverted (PRINT / UNDO there for a moment)
|  A STEPS              16
|  B x                   8
|  ...                           one row per knob the page uses
tm_draw:
        tst.l   tm_win
        beq     td_99
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  tm_win,%a2
        lea     36(%a2),%a5             | the window's surface
        move.l  %a5,-(%sp)
        jsr     CLEAR
        addq.l  #4,%sp
        bsr     tm_cur
        move.l  %d0,%d6                 | the page
        move.l  %a0,%a3                 | the settings
        move.l  %a1,%a4                 | the page record
| title: "T5 MORPH", then the page "1/3" (or the flash) on the right, then the bar inverted
        move.l  (%a4),-(%sp)
        move.l  tm_t,%d0
        addq.l  #1,%d0
        move.l  %d0,-(%sp)
        pea     F_TITLE
        pea     tm_buf
        jsr     SPRINTF
        lea     16(%sp),%sp
        moveq   #X_LAB,%d0
        moveq   #Y_TITLE,%d1
        lea     tm_buf,%a0
        bsr     tm_text
        tst.l   tm_flash
        beq     td_pg
        move.l  tm_fstr,%a0
        bra     td_pr
td_pg:  pea     NPAGES
        move.l  %d6,%d0
        addq.l  #1,%d0
        move.l  %d0,-(%sp)
        pea     F_PAGE
        pea     tm_buf
        jsr     SPRINTF
        lea     16(%sp),%sp
        lea     tm_buf,%a0
td_pr:  move.l  #X_VAL,%d0
        moveq   #Y_TITLE,%d1
        bsr     tm_rtext
        pea     -1
        pea     Y_TITLE+7
        pea     WINW-3
        pea     Y_TITLE-2
        pea     2
        move.l  %a5,-(%sp)
        jsr     INVERT
        lea     24(%sp),%sp
| the rows
        move.l  4(%a4),%a2              | the first row record
        move.l  8(%a4),%d7              | how many
        moveq   #Y_ROW0,%d5             | y
td_row: tst.l   %d7
        beq     td_end
        moveq   #X_LAB,%d0
        move.l  %d5,%d1
        move.l  (%a2),%a0
        bsr     tm_text
        mvz.b   4(%a2),%d0
        mvz.b   (%a3,%d0.l),%d4         | the value
        mvz.b   7(%a2),%d0              | the kind
        beq     td_num
        subq.l  #1,%d0
        beq     td_list
        tst.l   %d4                     | kind 2: 0 = TRK (the track's length)
        bne     td_num
        lea     V_TRK,%a0
        bra     td_val
td_list:
        move.l  8(%a2),%a0
        move.l  %d4,%d0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%a0
        bra     td_val
td_num: move.l  %d4,-(%sp)
        pea     F_NUM
        pea     tm_buf
        jsr     SPRINTF
        lea     12(%sp),%sp
        lea     tm_buf,%a0
td_val: move.l  #X_VAL,%d0
        move.l  %d5,%d1
        bsr     tm_rtext
        lea     12(%a2),%a2
        subq.l  #8,%d5
        subq.l  #1,%d7
        bra     td_row
td_end: moveq   #1,%d0
        move.l  %d0,SCRDIRTY
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
td_99:  rts

| tm_text -- d0 = x, d1 = y, a0 = str; a5 = surface. Clobbers d0, d1, a0, a1.
tm_text:
        move.l  %a0,-(%sp)
        pea     -1
        move.l  %d1,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %a5,-(%sp)
        pea     FONT
        jsr     TEXT
        lea     24(%sp),%sp
        rts

| tm_rtext -- a0 right-aligned at x = d0, row d1 (the pointer parked across TWIDTH, as MORPH and
| EUCLID FILL do). Clobbers d0, d1, a0, a1.
tm_rtext:
        move.l  %a0,tm_rstr
        move.l  %d0,tm_rx
        move.l  %d1,tm_ry
        move.l  %a0,-(%sp)
        pea     -1
        pea     FONT
        jsr     TWIDTH
        lea     12(%sp),%sp
        move.l  tm_rx,%d1
        sub.l   %d0,%d1
        bpl     tr_1
        moveq   #0,%d1
tr_1:   move.l  %d1,%d0
        move.l  tm_ry,%d1
        move.l  tm_rstr,%a0
        bra     tm_text

| ---------------------------------------------------------------- the pages
| page record, 12 bytes: title, rows, row count. Row record, 12 bytes: label; the byte's offset in
| the track's settings, min, max, kind (0 number, 1 list, 2 number with 0 = TRK); the list's
| string pointers (kind 1).
        .macro  ROW label, off, min, max, kind, list
        .long   \label
        .byte   \off, \min, \max, \kind
        .long   \list
        .endm

        .balign 4
PAGES:  .long   P_MORPH, ROWS_MORPH, 4
        .long   P_EUCL, ROWS_EUCL, 6
        .long   P_LIVE, ROWS_LIVE, 5
ROWS_MORPH:                             | MORPH's window, the same ranges (the 41.625 egg left out)
        ROW     L_STEPS, 1, 0, 64, 2, 0
        ROW     L_MULT,  2, 1, 16, 0, 0
        ROW     L_MODE,  3, 0, 1, 1, LS_MODE
        ROW     L_MORPH, 4, 0, 1, 1, LS_ARM
ROWS_EUCL:                              | EUCLACID's main page
        ROW     L_PLSA,  5, 0, 64, 0, 0
        ROW     L_ROTA,  6, 0, 63, 0, 0
        ROW     L_PLSB,  7, 0, 64, 0, 0
        ROW     L_ROTB,  8, 0, 63, 0, 0
        ROW     L_SLDE,  9, 0, 64, 0, 0
        ROW     L_SROT, 10, 0, 63, 0, 0
ROWS_LIVE:                              | EUCLACID's SETUP page, with the new modes (TRK and PRNT
        ROW     L_EMODE, 11, 0, 3, 1, LS_EMODE  | gone: the menu is the track's, YES/CUE print/undo)
        ROW     L_OP,   12, 0, 3, 1, LS_OP
        ROW     L_LIVE, 13, 0, 4, 1, LS_LIVE
        ROW     L_ONLY, 14, 0, 1, 1, LS_OFFON
        ROW     L_EVRY, 15, 0, 6, 1, LS_EVRY

LS_MODE:  .long V_SMOOTH, V_HOLD
LS_ARM:   .long V_OFF, V_ARM
LS_EMODE: .long V_EUCL, V_AUREO, V_DENS, V_NEST
LS_OP:    .long V_OR, V_XOR, V_AND, V_SUB
LS_LIVE:  .long V_OFF, V_ROT, V_DENS, V_MUTA, V_OPER
LS_OFFON: .long V_OFF, V_ON
LS_EVRY:  .long V_1, V_2, V_4, V_8, V_16, V_32, V_64

P_MORPH:  .asciz "MORPH"
P_EUCL:   .asciz "EUCLACID"
P_LIVE:   .asciz "EUCL LIVE"
L_STEPS:  .asciz "A STEPS"
L_MULT:   .asciz "B x"
L_MODE:   .asciz "C MODE"
L_MORPH:  .asciz "D MORPH"
L_PLSA:   .asciz "A PULSES A"
L_ROTA:   .asciz "B ROTATE A"
L_PLSB:   .asciz "C PULSES B"
L_ROTB:   .asciz "D ROTATE B"
L_SLDE:   .asciz "E SLIDES"
L_SROT:   .asciz "F ROT SLIDE"
L_EMODE:  .asciz "A MODE"
L_OP:     .asciz "B A+B"
L_LIVE:   .asciz "C LIVE"
L_ONLY:   .asciz "D SLIDE ON NOTE"
L_EVRY:   .asciz "E EVERY BARS"
V_TRK:    .asciz "TRK"
V_SMOOTH: .asciz "SMOOTH"
V_HOLD:   .asciz "HOLD"
V_OFF:    .asciz "OFF"
V_ON:     .asciz "ON"
V_ARM:    .asciz "ARMED"
V_EUCL:   .asciz "EUCLID"
V_AUREO:  .asciz "GOLDEN"
V_DENS:   .asciz "DENSITY"
V_NEST:   .asciz "NESTED"
V_OR:     .asciz "OR"
V_XOR:    .asciz "XOR"
V_AND:    .asciz "AND"
V_SUB:    .asciz "A-B"
V_ROT:    .asciz "ROT"
V_MUTA:   .asciz "MUTA"
V_OPER:   .asciz "OPER"
V_1:      .asciz "1"
V_2:      .asciz "2"
V_4:      .asciz "4"
V_8:      .asciz "8"
V_16:     .asciz "16"
V_32:     .asciz "32"
V_64:     .asciz "64"
S_PRINT:  .asciz "PRINT"
S_UNDO:   .asciz "UNDO"
F_TITLE:  .asciz "T%d %s"
F_PAGE:   .asciz "%d/%d"
F_NUM:    .asciz "%d"
F_START:  .asciz "T%d START"

| ---- the menu's layer (pushed while it is open): {next, keys, encoders, +12, +16, -1, -1}
        .balign 4
TM_LAYER:
        .long   0, TM_KEYS, TM_ENCS, 0, 0, -1, -1
TM_KEYS:
        KEYREC  0x34, tm_left, 0                    | LEFT:  the page before
        KEYREC  0x21, tm_right, 0                   | RIGHT: the page after
        KEYREC  0x32, tm_no, 0                      | NO:    close, nothing starts
        KEYREC  0x31, tm_yes, 0                     | YES:   PRINT (shown only)
        KEYREC  0x2a, tm_cue, 0                     | CUE:   UNDO (shown only)
        KEYREC  0x10, tm_trk, 0                     | T1..T8: the menu's own = START (shown only)
        KEYREC  0x11, tm_trk, 0
        KEYREC  0x12, tm_trk, 0
        KEYREC  0x13, tm_trk, 0
        KEYREC  0x14, tm_trk, 0
        KEYREC  0x15, tm_trk, 0
        KEYREC  0x16, tm_trk, 0
        KEYREC  0x17, tm_trk, 0
        KEYREC  0x00, 0, 0                         | trigs: swallowed
        KEYREC  0x01, 0, 0
        KEYREC  0x02, 0, 0
        KEYREC  0x03, 0, 0
        KEYREC  0x04, 0, 0
        KEYREC  0x05, 0, 0
        KEYREC  0x06, 0, 0
        KEYREC  0x07, 0, 0
        KEYREC  0x08, 0, 0
        KEYREC  0x09, 0, 0
        KEYREC  0x0a, 0, 0
        KEYREC  0x0b, 0, 0
        KEYREC  0x0c, 0, 0
        KEYREC  0x0d, 0, 0
        KEYREC  0x0e, 0, 0
        KEYREC  0x0f, 0, 0
        KEYREC  0x18, 0, 0                         | TEMPO: swallowed
        KEYREC  0x20, 0, 0                         | DOWN: swallowed
        KEYREC  0x22, 0, 0                         | SRC: swallowed
        KEYREC  0x23, 0, 0                         | AMP: swallowed
        KEYREC  0x24, 0, 0                         | LFO: swallowed
        KEYREC  0x25, 0, 0                         | FX1: swallowed
        KEYREC  0x26, 0, 0                         | FX2: swallowed
        KEYREC  0x29, 0, 0                         | REC: swallowed
        KEYREC  0x2d, 0, 0                         | FUNC: swallowed
        KEYREC  0x2e, 0, 0                         | PATTERN: swallowed
        KEYREC  0x2f, 0, 0                         | BANK: swallowed
        KEYREC  0x33, 0, 0                         | UP: swallowed
        KEYREC  0x35, 0, 0                         | MIDI: swallowed
        .byte   0xff, 0
        .space  24
TM_ENCS:
        .byte   0, 0                               | A: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   1, 0                               | B: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   2, 0                               | C: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   3, 0                               | D: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   4, 0                               | E: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   5, 0                               | F: the page's row
        .long   tm_enc, 0, 0, 0, 0
        .byte   6, 0                                | LEVEL: swallowed (a null handler)
        .long   0, 0, 0, 0, 0
        .byte   0xff, 0
        .long   0, 0, 0, 0, 0

| ---------------------------------------------------------------- state (DRAM, writable)
| per track, 16 bytes: page; MORPH: STEPS (0 = TRK), x, MODE, MORPH (armed); EUCLACID: PLSA,
| ROTA, PLSB, ROTB, SLDE, SROT; EUCL LIVE: MODE, OP, LIVE, ONLY, EVRY. Defaults: MORPH's
| (16 x 8 SMOOTH) and EUCLACID's (PLSA 4, the rest 0).
        .balign 4
tm_set:
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .balign 4
tm_win:     .long 0                         | the menu's window, 0 = closed
tm_timer:   .long -1                        | the soft timer's slot
tm_pushed:  .long 0                         | the layer is pushed
tm_t:       .long 0                         | the menu's track
tm_cand:    .long -1                        | the track whose long press counts, -1 = none
tm_count:   .long 0                         | ticks since that press
tm_snap0:   .long 0                         | key rows 0..3 at the press (the track's own cleared)
tm_snap1:   .long 0                         | key rows 4..7 at the press
tm_rebuilt: .long 0                         | the layer re-pushed after T's release
tm_flash:   .long 0                         | ticks left of PRINT / UNDO in the title bar
tm_fstr:    .long 0
tm_tmp:     .long 0
tm_rx:      .long 0
tm_ry:      .long 0
tm_rstr:    .long 0
tm_buf:     .space 24
tm_tbuf:    .space 16
