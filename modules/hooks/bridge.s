| HOOKS -- the bridged stock sites (modules/hooks/manifest.py says why each).
| remix.inc sets hk_<bridge> to 1 for each bridge this remix needs and fills
| its macro; a bridge that is off emits nothing.
        .text
        .include "remix.inc"

        .if     hk_status_icon
| renderer 0x4004bee2: `jsr hk_status_icon` replaces `lea 0x400c0cb8,%a0`.
| Each participant is called as its own detour would be: d3 the track, a4
| the state; each may rewrite a4 and ends with the lea redone, so a0 is the
| cache on return. d0, d1 and a1 are reloaded by the renderer before use.
        .global hk_status_icon
hk_status_icon:
        hk_status_icon_chain
        rts
        .endif

        .if     hk_track_key
| the [TRACK]-held layer's records: code, 0, press, release, 16 zero bytes
| (stock's layout, 0x1a bytes; repeat 0), then stock's 0xff terminator.
        .macro  HKREC code, press, release
        .byte   \code, 0
        .long   \press, \release
        .space  16
        .endm
        .balign 2
        .global hk_track_keys
hk_track_keys:
        hk_track_key_records
        .byte   0xff, 0
        .space  24
        .endif

        .if     hk_frame_tail
| frame interrupt epilogue 0x4000d9a6, jmp'd to on every exit path: each
| participant (built with HK_FRAME_TAIL: it returns), then the epilogue.
| d0-a6 are saved at (sp) by the prologue, so every register is free.
        .global hk_frame_tail
hk_frame_tail:
        hk_frame_tail_chain
        movem.l (%sp),%d0-%d7/%a0-%a6   | the stock epilogue, once
        lea     252(%sp),%sp
        .global hk_frame_tail_rte       | (a label only: verify_hooks stops here)
hk_frame_tail_rte:
        rte
        .endif

        .if     hk_frame_entry
| frame interrupt entry 0x4000aad0: the stock prologue once, then each
| participant (built with HK_FRAME_ENTRY: entered after its replay, it
| returns), then the interrupt's body.
        .global hk_frame_entry
hk_frame_entry:
        lea     -252(%sp),%sp           | the stock prologue, once
        movem.l %d0-%d7/%a0-%a6,(%sp)
        hk_frame_entry_chain
        jmp     (0x4000aad8).l
        .endif

        .if     hk_boot
| 0x40000512: `jsr hk_boot` replaces `jsr 0x4000f938`. Each participant but
| the last is called (built with HK_BOOT: it returns); the last tail-jumps
| to 0x4000f938, which returns to the boot.
        .global hk_boot
hk_boot:
        hk_boot_chain
        .endif

        .if     hk_chromatic
| CHROMATIC, BLACKPYRAMIDS_303 beside SCALE QUANTIZER. Each stub is entered
| as the participants' own detours were: same registers, same stack (the
| octave keys' handler reads the key at 8(%sp)).
| .hk_is_bp: Z clear when the UI track (0x100b14cc) is a BLACKPYRAMIDS track
| (its ot_track_is, C ABI). Keeps every register; movem, lea and rts keep CCR.
.hk_is_bp:
        lea     -16(%sp),%sp
        movem.l %d0-%d1/%a0-%a1,(%sp)
        moveq   #0,%d0
        move.b  0x100b14cc,%d0
        move.l  %d0,-(%sp)
        jsr     ot_track_is
        addq.l  #4,%sp
        tst.l   %d0
        movem.l (%sp),%d0-%d1/%a0-%a1
        lea     16(%sp),%sp
        rts
| .hk_sanitize: ot_chrom_sanitize (an octave above 1 on another track -> 0;
| nothing on a BLACKPYRAMIDS track). Keeps every register.
.hk_sanitize:
        lea     -16(%sp),%sp
        movem.l %d0-%d1/%a0-%a1,(%sp)
        jsr     ot_chrom_sanitize
        movem.l (%sp),%d0-%d1/%a0-%a1
        lea     16(%sp),%sp
        rts

        .global hk_octkey, hk_keyidx, hk_octdraw
| 0x40045918, FUNC + LEFT/RIGHT: both handlers go on at 0x40045920.
hk_octkey:
        bsr.w   .hk_is_bp
        beq.s   1f
        jmp     ot_oct_hook
1:      bsr.w   .hk_sanitize
        jmp     qz_octkey
| 0x40050254, the key's index: both go on at 0x4005025c (8 bytes replayed).
hk_keyidx:
        bsr.w   .hk_sanitize
        jmp     qz_keyidx
| 0x40044968, the keyboard picture: a BLACKPYRAMIDS track the full image
| (its own branch, d1 = 1); another track SCALE QUANTIZER's, which goes on
| at stock's bne 0x40044970.
hk_octdraw:
        bsr.w   .hk_is_bp
        beq.s   1f
        moveq   #1,%d1
        jmp     (0x40044988).l
1:      jmp     qz_octdraw
        .endif
