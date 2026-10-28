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
