| TRACK MENU v1 (prototype, 24 Oct 2026) -- hold a track key ~1 s: that track's menu.
|
| NAVIGATION ONLY. Every value lives in this unit and nothing reads it yet: MORPH keeps its own
| window and settings ([TRACK]+[UP]), no Euclidean pattern is printed, ERGOSUM has no engine.
| v1 is the shape the owner asked for after trying v0 on his MKI (24 Oct 2026, evening): a small
| chooser first, as the stock TRACKS / CHROMATIC / SLOTS list, then the function's page, its
| settings drawn as the stock's own knobs (the PLAYBACK page's 0x400479b4). Nothing is saved.
|
|   T held ~1 s, no other key --> the CHOOSER of that track: MORPH, EUCLACID, ERGOSUM (it opens
|                                on the function last used on that track; stays open when T is
|                                let go)
|     UP / DOWN ---------------> the choice;  YES --> its PAGE;  NO or the same T --> closed
|   on a PAGE (title "T5 MORPH" white on black, the settings as knobs A..F):
|     knobs A..F --------------> the settings (ARMED: nothing changes in the sound yet)
|     LEFT / RIGHT ------------> EUCLACID's two pages (the other functions have one)
|     the SAME T --------------> closes; toast "Tn START" (v1: the start is only shown)
|     NO ----------------------> back to the chooser
|     YES / CUE (EUCLACID) ----> "PRINT" / "UNDO" flashed in the title bar (v1: shown only)
|   other T keys, trigs, page  > swallowed while the menu is open; PLAY and STOP keep working
|   keys, FUNC, PATTERN, BANK, REC, MIDI, TEMPO, LEVEL
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
        .set    NOPTS,    3             | MORPH, EUCLACID, ERGOSUM
        .set    T_MASKS,  0x00240000    | rows 4..7 as a long: FUNC 0x2d (bit 21), CUE 0x2a (bit 18)
        .set    KNOB,     0x400479b4    | the stock knob: (x, y, slot, value, flags, fmt, surface)
        .set    K_FLAGS,  8             | flags bit 3: the plain layout (PLAYBACK page 2 passes 8)
        .set    FMT_D,    0x4003c178    | the stock formatter fmt(buf, value): "%d"

        .set    WINW,     116           | the page
        .set    WINH,     64
        .set    LISTW,    64            | the chooser, as small as the stock TRACKS list
        .set    LISTH,    30
        .set    L_Y0,     19            | its rows, 8 px apart: 19 11 3
        .set    L_X,      6
        .set    Y_TITLE,  54
        .set    X_LAB,    6
        .set    X_VAL,    110
        .set    K_Y1,     26            | the knob rows (y up): A B C (or the one row of four) ...
        .set    K_Y2,     0             | ... and D E F; a knob is 20 wide, its name at y + 20
        .set    Y_FOOT,   8             | MORPH's line under its one row of knobs
        .set    SETSZ,    32            | the settings of a track, bytes

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
| tm_open -- d0 = the track: the chooser. The timer keeps running (it watches T's release and the
| flash).
tm_open:
        move.l  %d0,tm_t
        clr.l   tm_rebuilt
        clr.l   tm_flash
        bsr     tm_set_a0               | the chooser starts on the function last used here
        mvz.b   (%a0),%d0
        moveq   #NOPTS-1,%d1
        cmp.l   %d1,%d0
        bls     to_1
        moveq   #0,%d0
to_1:   move.l  %d0,tm_sel
        clr.l   tm_pg
        bsr     tm_win_list
        tst.l   tm_win
        beq     tm_untimer              | no window: nothing open, the timer goes
        pea     TM_LAYER
        jsr     LPUSH
        addq.l  #4,%sp
        moveq   #1,%d0
        move.l  %d0,tm_pushed
        bra     tm_draw

| tm_win_list / tm_win_page -- (re)create the window at the chooser's / the page's size. A window
| already open is destroyed first with tm_swap set, so its closed callback leaves the layer and the
| timer alone. tm_win = 0 if WCREATE gave none.
tm_win_list:
        clr.l   tm_onpage
        moveq   #LISTW,%d0
        moveq   #LISTH,%d1
        bra     tw_1
tm_win_page:
        moveq   #1,%d0
        move.l  %d0,tm_onpage
        moveq   #WINW,%d0
        moveq   #WINH,%d1
tw_1:   move.l  %d0,tm_ww
        move.l  %d1,tm_wh
        tst.l   tm_win
        beq     tw_2
        moveq   #1,%d0
        move.l  %d0,tm_swap
        pea     tm_win
        jsr     WDESTROY
        addq.l  #4,%sp
        clr.l   tm_swap
        clr.l   tm_win
tw_2:   pea     tm_closed
        pea     5                       | TEMPO class, as MORPH and EUCLID FILL
        clr.l   -(%sp)
        clr.l   -(%sp)
        move.l  tm_wh,%d0
        move.l  %d0,-(%sp)
        move.l  tm_ww,%d0
        move.l  %d0,-(%sp)
        jsr     WCREATE
        lea     24(%sp),%sp
        move.l  %d0,tm_win
        beq     tw_9
        move.l  %d0,-(%sp)
        jsr     WFRAME
        addq.l  #4,%sp
tw_9:   rts

| tm_close -- the window, the layer and the timer gone; safe when already closed.
tm_close:
        tst.l   tm_win
        beq     tm_closed
        pea     tm_win
        jsr     WDESTROY
        addq.l  #4,%sp
tm_closed:                              | WCREATE's callback: another window of the class took over
        tst.l   tm_swap
        bne     tc_9                    | our own swap between the chooser and a page
        clr.l   tm_win
        clr.l   tm_onpage
        bsr     tm_untimer
        tst.l   tm_pushed               | once: WDESTROY may call tm_closed itself
        beq     tc_9
        clr.l   tm_pushed
        pea     TM_LAYER
        jsr     LPOP
        addq.l  #4,%sp
tc_9:   rts

| tm_set_a0 -- a0 = this track's settings (SETSZ bytes: the function last used first). Clobbers d1.
tm_set_a0:
        lea     tm_set,%a0
        move.l  tm_t,%d1
        lsl.l   #5,%d1                  | SETSZ = 32
        add.l   %d1,%a0
        rts

| tm_cur -- the page on screen: a0 = the track's settings, a1 = its page record, d0 = the page's
| index within its function (EUCLACID 0 or 1), d1 = the function's page count. Clobbers nothing
| else.
tm_cur:
        bsr     tm_set_a0
        move.l  tm_sel,%d0
        lea     OPTS,%a1
        lsl.l   #4,%d0                  | 16 bytes an option
        add.l   %d0,%a1
        move.l  8(%a1),%d1              | its page count
        move.l  tm_pg,%d0
        cmp.l   %d1,%d0
        bcs     cu_1
        moveq   #0,%d0
        move.l  %d0,tm_pg
cu_1:   move.l  4(%a1),%a1              | its first page record
        move.l  %d0,-(%sp)
        lsl.l   #4,%d0                  | 16 bytes a page record
        add.l   %d0,%a1
        move.l  (%sp)+,%d0
        rts

| ---- the menu's keys: handler(keycode @4, event @8), event 1 = press
| NO: on a page, back to the chooser; on the chooser, closed.
tm_no:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        tst.l   tm_onpage
        beq     tm_close
        clr.l   tm_flash
        bsr     tm_win_list
        tst.l   tm_win
        beq     tm_close
        bra     tm_draw
k_9:    rts

| UP / DOWN: the chooser's choice (wraps); on a page, nothing.
tm_up:
        moveq   #NOPTS-1,%d0            | -1, modulo the options
        bra     ku_1
tm_down:
        moveq   #1,%d0
ku_1:   moveq   #1,%d1
        cmp.l   8(%sp),%d1
        bne     k_9
        tst.l   tm_onpage
        bne     k_9
        add.l   tm_sel,%d0
        moveq   #NOPTS,%d1
        cmp.l   %d1,%d0
        blt     ku_2
        sub.l   %d1,%d0
ku_2:   move.l  %d0,tm_sel
        bra     tm_draw

| LEFT / RIGHT: on a page of a function with more than one (EUCLACID), the other page.
tm_left:
tm_right:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        tst.l   tm_onpage
        beq     k_9
        bsr     tm_cur                  | d0 = this page, d1 = the count
        moveq   #2,%d0
        cmp.l   %d0,%d1
        bne     k_9                     | one page: nothing to turn
        move.l  tm_pg,%d0
        eori.l  #1,%d0
        move.l  %d0,tm_pg
        clr.l   tm_flash
        bra     tm_draw

| YES: on the chooser, open the choice's page (and remember it for this track); on a EUCLACID
| page, PRINT flashed. CUE: on a EUCLACID page, UNDO flashed.
tm_yes:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        tst.l   tm_onpage
        bne     ky_page
        bsr     tm_set_a0
        move.l  tm_sel,%d0
        move.b  %d0,(%a0)               | the function last used on this track
        clr.l   tm_pg
        clr.l   tm_flash
        bsr     tm_win_page
        tst.l   tm_win
        beq     tm_close
        bra     tm_draw
ky_page:
        lea     S_PRINT,%a0
        bra     ky_1
tm_cue:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        tst.l   tm_onpage
        beq     k_9
        lea     S_UNDO,%a0
ky_1:   moveq   #1,%d0
        cmp.l   tm_sel,%d0
        bne     k_9                     | only EUCLACID prints
        move.l  %a0,tm_fstr
        moveq   #FLASH,%d0
        move.l  %d0,tm_flash
        bra     tm_draw

| a track key while the menu is open: the menu's own track starts from a page (v1: closes and
| says so) and closes the chooser silently; any other track key is swallowed.
tm_trk:
        moveq   #1,%d0
        cmp.l   8(%sp),%d0
        bne     k_9
        move.l  4(%sp),%d0
        sub.l   #0x10,%d0
        cmp.l   tm_t,%d0
        bne     k_9
        tst.l   tm_onpage
        beq     tm_close
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

| tm_enc -- encoder (index @4, delta @8): on a page, its knob `index`, the value +delta, clamped.
tm_enc:
        tst.l   8(%sp)
        beq     k_9
        tst.l   tm_onpage
        beq     k_9
        bsr     tm_cur                  | a0 = settings, a1 = page record
        move.l  4(%sp),%d0              | index
        cmp.l   8(%a1),%d0
        bcc     k_9                     | no knob for this encoder on this page
        move.l  4(%a1),%a1              | the knobs
        lsl.l   #4,%d0                  | 16 bytes a knob
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
| the chooser:            the page:
|  ┌──────────┐           ███ T5 EUCLACID ████████ 1/2 █   the title bar, inverted
|  │█ MORPH  █│            PLSA  ROTA  PLSB                the knobs' names, the stock knobs,
|  │  EUCLACID│             (o)   (o)   (o)                their values under them (drawn by
|  │  ERGOSUM │              4     0     0                 the knob itself)
|  └──────────┘            ROTB  SLDE  SROT ...
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
        tst.l   tm_onpage
        bne     td_page
| the chooser: the three names, the choice's row inverted
        lea     OPTS,%a2
        moveq   #0,%d7
        moveq   #L_Y0,%d5
td_l1:  moveq   #L_X,%d0
        move.l  %d5,%d1
        move.l  (%a2),%a0
        bsr     tm_text
        cmp.l   tm_sel,%d7
        bne     td_l2
        pea     -1
        move.l  %d5,%d0
        addq.l  #6,%d0
        move.l  %d0,-(%sp)              | y2
        pea     LISTW-3                 | x2
        move.l  %d5,%d0
        subq.l  #1,%d0
        move.l  %d0,-(%sp)              | y1
        pea     2                       | x1
        move.l  %a5,-(%sp)
        jsr     INVERT
        lea     24(%sp),%sp
td_l2:  lea     16(%a2),%a2
        subq.l  #8,%d5
        addq.l  #1,%d7
        moveq   #NOPTS,%d0
        cmp.l   %d0,%d7
        blt     td_l1
        bra     td_end
td_page:
        bsr     tm_cur
        move.l  %d0,%d6                 | the page within the function
        move.l  %d1,%d4                 | the function's page count
        move.l  %a0,%a3                 | the settings
        move.l  %a1,%a4                 | the page record
| title: "T5 MORPH", "1/2" on the right when the function has two pages (or the flash)
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
td_pg:  moveq   #1,%d0
        cmp.l   %d0,%d4
        beq     td_bar                  | one page: no number
        move.l  %d4,-(%sp)
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
td_bar: pea     -1
        pea     Y_TITLE+7
        pea     WINW-3
        pea     Y_TITLE-2
        pea     2
        move.l  %a5,-(%sp)
        jsr     INVERT
        lea     24(%sp),%sp
| the knobs: their positions from the page's layout (12(a4) = a table of x, y per knob)
        move.l  4(%a4),%a2              | the first knob record
        move.l  12(%a4),%a6             | its positions: x, y bytes per knob
        moveq   #0,%d7                  | the knob
td_k1:  cmp.l   8(%a4),%d7
        bcc     td_foot
        mvz.b   (%a6),%d2               | x
        mvz.b   1(%a6),%d3              | y
| the name, centred on x + 9 at y + 20
        move.l  %d2,%d0
        add.l   #9,%d0
        move.l  %d3,%d1
        add.l   #20,%d1
        move.l  (%a2),%a0
        bsr     tm_ctext
| the stock knob draws the circle, the pointer and the value (through the formatter) under it
        mvz.b   4(%a2),%d0
        mvz.b   (%a3,%d0.l),%d0         | the value
        move.l  %a5,-(%sp)              | surface
        move.l  8(%a2),-(%sp)           | formatter
        pea     K_FLAGS
        move.l  %d0,-(%sp)              | value
        move.l  %d7,-(%sp)              | slot
        move.l  %d3,-(%sp)              | y
        move.l  %d2,-(%sp)              | x
        jsr     KNOB
        lea     28(%sp),%sp
        lea     16(%a2),%a2
        addq.l  #2,%a6
        addq.l  #1,%d7
        bra     td_k1
| MORPH: the cycle under its knobs, as its own window shows it ("CYCLE 128 STEPS")
td_foot:
        tst.l   tm_sel
        bne     td_end
        mvz.b   1(%a3),%d0              | STEPS (0 = TRK)
        mvz.b   2(%a3),%d1              | x
        tst.l   %d0
        bne     tf_1
        move.l  %d1,-(%sp)
        pea     F_CYTRK
        bra     tf_2
tf_1:   mulu.w  %d1,%d0
        move.l  %d0,-(%sp)
        pea     F_CYCLE
tf_2:   pea     tm_buf
        jsr     SPRINTF
        lea     12(%sp),%sp
        moveq   #X_LAB,%d0
        moveq   #Y_FOOT,%d1
        lea     tm_buf,%a0
        bsr     tm_text
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
| EUCLID FILL do). tm_ctext -- the same centred on x = d0. Clobbers d0, d1, a0, a1.
tm_ctext:
        move.l  %d1,tm_ry
        moveq   #1,%d1
        move.l  %d1,tm_half
        move.l  tm_ry,%d1
        bra     tr_0
tm_rtext:
        clr.l   tm_half
tr_0:   move.l  %a0,tm_rstr
        move.l  %d0,tm_rx
        move.l  %d1,tm_ry
        move.l  %a0,-(%sp)
        pea     -1
        pea     FONT
        jsr     TWIDTH
        lea     12(%sp),%sp
        tst.l   tm_half
        beq     tr_2
        asr.l   #1,%d0
tr_2:   move.l  tm_rx,%d1
        sub.l   %d0,%d1
        bpl     tr_1
        moveq   #0,%d1
tr_1:   move.l  %d1,%d0
        move.l  tm_ry,%d1
        move.l  tm_rstr,%a0
        bra     tm_text

| ---- formatters for the stock knob: fmt(buf @4, value @8) -> the value's label, at most 5
| characters (the stock's buffer runs five on hardware, faults at ten: PARAM_PAGES.md section 7).
fm_steps:                               | MORPH's STEPS: 0 = TRK
        move.l  8(%sp),%d0
        beq     fs_trk
        move.l  %d0,-(%sp)
        pea     F_NUM
        move.l  12(%sp),-(%sp)          | buf (4(sp) before the two pushes)
        jsr     SPRINTF
        lea     12(%sp),%sp
        rts
fs_trk: lea     V_TRK,%a0
        bra     fm_s
fm_mode:  lea     LS_MODE,%a0
        bra     fm_list
fm_arm:   lea     LS_ARM,%a0
        bra     fm_list
fm_emode: lea     LS_EMODE,%a0
        bra     fm_list
fm_op:    lea     LS_OP,%a0
        bra     fm_list
fm_live:  lea     LS_LIVE,%a0
        bra     fm_list
fm_offon: lea     LS_OFFON,%a0
        bra     fm_list
fm_evry:  lea     LS_EVRY,%a0
        bra     fm_list
fm_gmode: lea     LS_GMODE,%a0
        bra     fm_list
fm_ratio: lea     LS_RATIO,%a0
fm_list:
        move.l  8(%sp),%d0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%a0
fm_s:   move.l  %a0,-(%sp)
        pea     F_STR
        move.l  12(%sp),-(%sp)          | buf (4(sp) before the two pushes)
        jsr     SPRINTF
        lea     12(%sp),%sp
        rts

| ---------------------------------------------------------------- the functions and their pages
| option record, 16 bytes: name, first page record, page count, 0.
| page record, 16 bytes: title, knobs, knob count, positions (x, y bytes per knob).
| knob record, 16 bytes: name (4 characters, as the stock's); the byte's offset in the track's
| settings, min, max, 0; the formatter fmt(buf, value); 0.
        .macro  KN name, off, min, max, fmt
        .long   \name
        .byte   \off, \min, \max, 0
        .long   \fmt, 0
        .endm

        .balign 4
OPTS:   .long   O_MORPH, PG_MORPH, 1, 0
        .long   O_EUCL,  PG_EUCL,  2, 0
        .long   O_ERGO,  PG_ERGO,  1, 0
PG_MORPH: .long O_MORPH, KN_MORPH, 4, XY_ROW4
PG_EUCL:  .long O_EUCL,  KN_EUCL,  6, XY_SIX
          .long O_EUCL,  KN_LIVE,  5, XY_SIX
PG_ERGO:  .long O_ERGO,  KN_ERGO,  4, XY_SIX
XY_ROW4:  .byte 6, K_Y1, 34, K_Y1, 62, K_Y1, 90, K_Y1
XY_SIX:   .byte 10, K_Y1, 48, K_Y1, 86, K_Y1, 10, K_Y2, 48, K_Y2, 86, K_Y2
        .balign 4
KN_MORPH:                               | MORPH's window, the same ranges (the 41.625 egg left out)
        KN      N_STEP,  1, 0, 64, fm_steps
        KN      N_MULT,  2, 1, 16, FMT_D
        KN      N_MODE,  3, 0, 1, fm_mode
        KN      N_MRPH,  4, 0, 1, fm_arm
KN_EUCL:                                | EUCLACID's main page
        KN      N_PLSA,  5, 0, 64, FMT_D
        KN      N_ROTA,  6, 0, 63, FMT_D
        KN      N_PLSB,  7, 0, 64, FMT_D
        KN      N_ROTB,  8, 0, 63, FMT_D
        KN      N_SLDE,  9, 0, 64, FMT_D
        KN      N_SROT, 10, 0, 63, FMT_D
KN_LIVE:                                | EUCLACID's SETUP page, with the new modes
        KN      N_MODE, 11, 0, 3, fm_emode
        KN      N_OP,   12, 0, 3, fm_op
        KN      N_LIVE, 13, 0, 4, fm_live
        KN      N_ONLY, 14, 0, 1, fm_offon
        KN      N_EVRY, 15, 0, 6, fm_evry
KN_ERGO:                                | ERGOSUM (RENE_CARTESIANO_idea.md): no engine yet
        KN      N_MODE, 16, 0, 3, fm_gmode
        KN      N_RATI, 17, 0, 8, fm_ratio
        KN      N_SNAK, 18, 1, 16, FMT_D
        KN      N_ARM,  19, 0, 1, fm_arm

LS_MODE:  .long V_SMOOTH, V_HOLD
LS_ARM:   .long V_OFF, V_ARM
LS_EMODE: .long V_EUCL, V_AUREO, V_DENS, V_NEST
LS_OP:    .long V_OR, V_XOR, V_AND, V_SUB
LS_LIVE:  .long V_OFF, V_ROT, V_DENS, V_MUTA, V_OPER
LS_OFFON: .long V_OFF, V_ON
LS_EVRY:  .long V_1, V_2, V_4, V_8, V_16, V_32, V_64
LS_GMODE: .long V_LIN, V_XY, V_SNAKE, V_DIAG
LS_RATIO: .long R_11, R_12, R_23, R_34, R_13, R_25, R_35, R_37, R_57

O_MORPH:  .asciz "MORPH"
O_EUCL:   .asciz "EUCLACID"
O_ERGO:   .asciz "ERGOSUM"
N_STEP:   .asciz "STEP"
N_MULT:   .asciz "MULT"
N_MODE:   .asciz "MODE"
N_MRPH:   .asciz "MRPH"
N_PLSA:   .asciz "PLSA"
N_ROTA:   .asciz "ROTA"
N_PLSB:   .asciz "PLSB"
N_ROTB:   .asciz "ROTB"
N_SLDE:   .asciz "SLDE"
N_SROT:   .asciz "SROT"
N_OP:     .asciz "A+B"
N_LIVE:   .asciz "LIVE"
N_ONLY:   .asciz "ONLY"
N_EVRY:   .asciz "EVRY"
N_RATI:   .asciz "RATI"
N_SNAK:   .asciz "SNAK"
N_ARM:    .asciz "ARM"
V_TRK:    .asciz "TRK"
V_SMOOTH: .asciz "SMTH"
V_HOLD:   .asciz "HOLD"
V_OFF:    .asciz "OFF"
V_ON:     .asciz "ON"
V_ARM:    .asciz "ARM"
V_EUCL:   .asciz "EUCL"
V_AUREO:  .asciz "GOLD"
V_DENS:   .asciz "DENS"
V_NEST:   .asciz "NEST"
V_OR:     .asciz "OR"
V_XOR:    .asciz "XOR"
V_AND:    .asciz "AND"
V_SUB:    .asciz "A-B"
V_ROT:    .asciz "ROT"
V_MUTA:   .asciz "MUTA"
V_OPER:   .asciz "OPER"
V_LIN:    .asciz "LIN"
V_XY:     .asciz "XY"
V_SNAKE:  .asciz "SNAKE"
V_DIAG:   .asciz "DIAG"
R_11:     .asciz "1:1"
R_12:     .asciz "1:2"
R_23:     .asciz "2:3"
R_34:     .asciz "3:4"
R_13:     .asciz "1:3"
R_25:     .asciz "2:5"
R_35:     .asciz "3:5"
R_37:     .asciz "3:7"
R_57:     .asciz "5:7"
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
F_STR:    .asciz "%s"
F_NUM:    .asciz "%d"
F_START:  .asciz "T%d START"
F_CYCLE:  .asciz "CYCLE %d STEPS"
F_CYTRK:  .asciz "CYCLE TRK x %d"

| ---- the menu's layer (pushed while it is open): {next, keys, encoders, +12, +16, -1, -1}
        .balign 4
TM_LAYER:
        .long   0, TM_KEYS, TM_ENCS, 0, 0, -1, -1
TM_KEYS:
        KEYREC  0x34, tm_left, 0                    | LEFT:  EUCLACID's other page
        KEYREC  0x21, tm_right, 0                   | RIGHT: EUCLACID's other page
        KEYREC  0x33, tm_up, 0                      | UP:    the chooser's choice
        KEYREC  0x20, tm_down, 0                    | DOWN:  the chooser's choice
        KEYREC  0x32, tm_no, 0                      | NO:    page -> chooser -> closed
        KEYREC  0x31, tm_yes, 0                     | YES:   open the page; PRINT (shown only)
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
        KEYREC  0x22, 0, 0                         | SRC: swallowed
        KEYREC  0x23, 0, 0                         | AMP: swallowed
        KEYREC  0x24, 0, 0                         | LFO: swallowed
        KEYREC  0x25, 0, 0                         | FX1: swallowed
        KEYREC  0x26, 0, 0                         | FX2: swallowed
        KEYREC  0x29, 0, 0                         | REC: swallowed
        KEYREC  0x2d, 0, 0                         | FUNC: swallowed
        KEYREC  0x2e, 0, 0                         | PATTERN: swallowed
        KEYREC  0x2f, 0, 0                         | BANK: swallowed
        KEYREC  0x35, 0, 0                         | MIDI: swallowed
        .byte   0xff, 0
        .space  24
TM_ENCS:
        .byte   0, 0                               | A: the page's knob
        .long   tm_enc, 0, 0, 0, 0
        .byte   1, 0                               | B
        .long   tm_enc, 0, 0, 0, 0
        .byte   2, 0                               | C
        .long   tm_enc, 0, 0, 0, 0
        .byte   3, 0                               | D
        .long   tm_enc, 0, 0, 0, 0
        .byte   4, 0                               | E
        .long   tm_enc, 0, 0, 0, 0
        .byte   5, 0                               | F
        .long   tm_enc, 0, 0, 0, 0
        .byte   6, 0                                | LEVEL: swallowed (a null handler)
        .long   0, 0, 0, 0, 0
        .byte   0xff, 0
        .long   0, 0, 0, 0, 0

| ---------------------------------------------------------------- state (DRAM, writable)
| per track, 32 bytes: the function last used (0 MORPH, 1 EUCLACID, 2 ERGOSUM); MORPH: STEPS
| (0 = TRK), x, MODE, MORPH (armed); EUCLACID: PLSA, ROTA, PLSB, ROTB, SLDE, SROT; its SETUP: MODE,
| OP, LIVE, ONLY, EVRY; ERGOSUM: MODE, RATIO, SNAKE, ARMED; the rest free. Defaults: MORPH's
| (16 x 8 SMOOTH), EUCLACID's (PLSA 4, the rest 0), ERGOSUM's (LIN, 1:1, snake 1).
        .macro  TSET
        .byte   0, 16, 8, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .endm
        .balign 4
tm_set:
        TSET
        TSET
        TSET
        TSET
        TSET
        TSET
        TSET
        TSET
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
tm_onpage:  .long 0                         | 0 = the chooser, 1 = a function's page
tm_sel:     .long 0                         | the chooser's choice = the page's function
tm_pg:      .long 0                         | the page within the function (EUCLACID 0, 1)
tm_swap:    .long 0                         | our own window swap: tm_closed leaves things alone
tm_ww:      .long 0
tm_wh:      .long 0
tm_half:    .long 0
tm_fstr:    .long 0
tm_rx:      .long 0
tm_ry:      .long 0
tm_rstr:    .long 0
tm_buf:     .space 24
tm_tbuf:    .space 16
