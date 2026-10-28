/* PARTS -- live Part access and coherent replacement, for every module that
 * keeps state in a Part (modules/parts/manifest.py). From radiohagen's MIDI
 * PART STATE (part.s, part-copy.s; modules/midi-loopback/upstream): its
 * MIDI API is kept below as it was, under its own names, for its clients.
 *
 * Context = bank * 4 + Part, 0..63; -1 means unavailable. Read/write take an
 * explicit context, so queued events never consult the current UI selection.
 * Every public entry preserves every register except d0 and the condition
 * codes. remix.inc (parts_inc) supplies:
 *   PT_LO, PT_LEN   the snapshot window: the Part byte offsets every client's
 *                   window covers, LEN a multiple of 4 (0: no snapshot)
 *   PT_MIDI         1 when a client uses MIDI PART STATE's mp_* names
 *   pt_tables       the readable and writable byte bitmaps (pt_rd, pt_wr)
 *   pt_before_calls, pt_replaced_calls   each client's notification
 */
    .include "remix.inc"
    .text
    .global pt_ui_context,pt_midi_play_context,pt_epoch,pt_read,pt_write
    .global pt_native_copy,pt_native_init,pt_snapshot_bank,pt_snapshot_parts
    .global pt_snapshot,pt_part_epochs

    .equ    BANKS,      0x400e21e0      | bank 0's blob; banks every 0x9b340
    .equ    BANK_LEN,   0x9b340
    .equ    WORK,       0x8ed80         | the four working Parts in a bank blob
    .equ    PART_LEN,   0x18b2
    .equ    WORK_END,   0x95048         | WORK + 4 * PART_LEN: per-Part dirty bits
    .equ    BANK_DIRTY, 0x9b332
    .equ    CUR_BANK,   0x46c82456      | the UI's bank blob pointer
    .equ    CUR_PART,   0x100b14cf
    .equ    CS1_PARTS,  0x100a4ece      | the current bank's battery-backed working Parts
    .equ    CS1_DIRTY,  0x100b145e
    .equ    CS1_FLAG,   0x100f8598

/* -> d0 the UI's context (selected bank and Part), or -1. */
pt_ui_context:
    lea -12(%sp),%sp
    movem.l %d1-%d2/%a0,(%sp)
    move.l CUR_BANK,%d0
    subi.l #BANKS,%d0
    cmpi.l #BANK_LEN*16,%d0
    bcc.s .ui_bad
    move.l %d0,%d2
    move.l #BANK_LEN,%d1
    divu.l %d1,%d0
    mulu.l %d0,%d1
    cmp.l %d1,%d2
    bne.s .ui_bad
    lsl.l #2,%d0
    moveq #0,%d1
    move.b CUR_PART,%d1
    cmpi.l #3,%d1
    bhi.s .ui_bad
    add.l %d1,%d0
    bra.s .ui_done
.ui_bad:
    moveq #-1,%d0
.ui_done:
    movem.l (%sp),%d1-%d2/%a0
    lea 12(%sp),%sp
    rts

/* d0 context -> replacement epoch, or -1. It advances when a native copy or
 * initialization replaces that Part; ordinary single-field edits do not. */
pt_epoch:
    cmpi.l #63,%d0
    bhi.s .epoch_bad
    move.l %a0,-(%sp)
    lea pt_part_epochs,%a0
    move.l (%a0,%d0.l*4),%d0
    move.l (%sp)+,%a0
    rts
.epoch_bad:
    moveq #-1,%d0
    rts

/* d0 MIDI track -> the context it plays. A track latched to a bank/Part
 * (0x8000182a / 0x80001832) plays that; an unlatched one the engine's applied
 * bank/Part (0x80001828 / 0x80001829). radiohagen's reading of the MIDI
 * engine (MIDI PART STATE); audio tracks are not established. */
pt_midi_play_context:
    lea -8(%sp),%sp
    movem.l %d1/%a0,(%sp)
    cmpi.l #7,%d0
    bhi.s .play_bad
    lea 0x8000182a,%a0
    moveq #0,%d1
    move.b (%a0,%d0.l),%d1
    lea 0x80001832,%a0
    move.b (%a0,%d0.l),%d0
    andi.l #255,%d0
    cmpi.l #15,%d1
    bhi.s .play_applied
    cmpi.l #3,%d0
    bls.s .play_pack
.play_applied:
    moveq #0,%d1
    move.b 0x80001828,%d1
    moveq #0,%d0
    move.b 0x80001829,%d0
    cmpi.l #15,%d1
    bhi.s .play_bad
    cmpi.l #3,%d0
    bhi.s .play_bad
.play_pack:
    lsl.l #2,%d1
    add.l %d1,%d0
    bra.s .play_done
.play_bad:
    moveq #-1,%d0
.play_done:
    movem.l (%sp),%d1/%a0
    addq.l #8,%sp
    rts

/* Internal: d0 context, d1 Part offset, a0 the bitmap -> a0 the working
 * byte, a1 its bank, d4 the Part, d0 the offset within the working-Part
 * array; d0 = -1 for a context, offset or byte the bitmap does not allow. */
.offset_address:
    cmpi.l #63,%d0
    bhi.s .off_bad
    cmpi.l #PART_LEN-1,%d1
    bhi.s .off_bad
    move.l %d1,%d4
    lsr.l #3,%d4
    move.b (%a0,%d4.l),%d5
    move.l %d1,%d4
    andi.l #7,%d4
    btst %d4,%d5
    beq.s .off_bad
    move.l %d0,%d5
    lsr.l #2,%d5                    | the bank
    move.l %d0,%d4
    andi.l #3,%d4                   | the Part
    move.l #PART_LEN,%d0
    mulu.l %d4,%d0
    add.l %d1,%d0
    move.l #BANK_LEN,%d6
    mulu.l %d6,%d5
    lea BANKS,%a1
    adda.l %d5,%a1
    move.l %a1,%a0
    adda.l #WORK,%a0
    adda.l %d0,%a0
    rts
.off_bad:
    moveq #-1,%d0
    rts

/* d0 context, d1 Part offset -> the byte, or -1: a byte some client of this
 * remix reads (its window). While the Part is being replaced, the outgoing
 * byte (the snapshot). */
pt_read:
    lea -20(%sp),%sp
    movem.l %d4-%d6/%a0-%a1,(%sp)
    lea pt_rd,%a0
    bsr.w .offset_address
    tst.l %d0
    bmi.s .pread_done
    bsr.w .snapshot_address
    moveq #0,%d0
    move.b (%a0),%d0
.pread_done:
    movem.l (%sp),%d4-%d6/%a0-%a1
    lea 20(%sp),%sp
    rts

/* d0 context, d1 Part offset, d2 byte -> 1 accepted, 0 refused: a byte some
 * client of this remix writes. The working byte, the native dirty bits and,
 * for the UI's bank, the battery-backed mirror, under one short mask. */
pt_write:
    lea -24(%sp),%sp
    movem.l %d4-%d7/%a0-%a1,(%sp)
    cmpi.l #255,%d2
    bhi.s .pwrite_bad
    lea pt_wr,%a0
    bsr.w .offset_address
    tst.l %d0
    bmi.s .pwrite_bad
    move.l %d2,%d6
    bsr.w .store
    moveq #1,%d0
    bra.s .pwrite_done
.pwrite_bad:
    moveq #0,%d0
.pwrite_done:
    movem.l (%sp),%d4-%d7/%a0-%a1
    lea 24(%sp),%sp
    rts

/* Internal: a0 working byte, a1 bank, d4 Part, d0 offset within the working
 * array, d6 the byte. Clobbers d5, d7 and a0. */
.store:
    move.w %sr,%d7
    move.w #0x2700,%sr
    cmp.b (%a0),%d6
    beq.s .store_done
    move.b %d6,(%a0)
    move.l %a1,%a0
    adda.l #WORK_END,%a0
    bset %d4,(%a0)
    moveq #1,%d5
    move.l %a1,%a0
    adda.l #BANK_DIRTY,%a0
    move.l %d5,(%a0)
    /* The battery-backed mirror holds the UI's bank, named by its pointer. */
    cmpa.l CUR_BANK,%a1
    bne.s .store_done
    lea CS1_PARTS,%a0
    move.b %d6,(%a0,%d0.l)
    bset %d4,CS1_DIRTY
    move.l %d5,CS1_FLAG
.store_done:
    move.w %d7,%sr
    rts

/* Internal: the read address remapped into the snapshot while a native copy
 * or initialization replaces this Part. a1 bank, d4 Part, d0 the offset
 * within the working array (inside the window: every readable byte is). */
.snapshot_address:
    .if PT_LEN
    cmpa.l pt_snapshot_bank,%a1
    bne.s .snapshot_done
    move.l pt_snapshot_parts,%d5
    btst %d4,%d5
    beq.s .snapshot_done
    move.l #PART_LEN-PT_LEN,%d5
    mulu.l %d4,%d5
    neg.l %d5
    add.l %d0,%d5
    subi.l #PT_LO,%d5
    lea pt_snapshot,%a0
    adda.l %d5,%a0
.snapshot_done:
    .endif
    rts

    .if PT_MIDI
/* ---- MIDI PART STATE's API (radiohagen), kept under its names ----------- */
    .global mp_ui_context,mp_play_context,mp_read,mp_write,mp_read_key,mp_epoch
    .global mp_snapshot_bank,mp_snapshot_parts,mp_snapshot,mp_part_epochs
    .global mp_native_copy,mp_native_init
    .set mp_ui_context, pt_ui_context
    .set mp_play_context, pt_midi_play_context
    .set mp_epoch, pt_epoch
    .set mp_snapshot_bank, pt_snapshot_bank
    .set mp_snapshot_parts, pt_snapshot_parts
    .set mp_snapshot, pt_snapshot
    .set mp_part_epochs, pt_part_epochs
    .set mp_native_copy, pt_native_copy
    .set mp_native_init, pt_native_init

/* Internal: d0 track,d1 context,d2 SETUP offset -> a0 byte, a1 bank,
 * d0 offset within working-Part array, d4 Part. d0=-1 rejects invalid input.
 * Only the eight reserved positions are accessible through this interface.
 */
.address:
    cmpi.l #7,%d0
    bhi.s .address_bad
    cmpi.l #63,%d1
    bhi.s .address_bad
    cmpi.l #19,%d2
    bhi.s .address_bad
    move.l #0x000db028,%d4 /* bits 3,5,12,13,15,16,18,19 */
    btst %d2,%d4
    beq.s .address_bad
    move.l %d1,%d4
    andi.l #3,%d4
    move.l #36,%d5
    mulu.l %d5,%d0
    add.l %d2,%d0
    addi.l #0x4e2,%d0
    move.l #0x18b2,%d5
    mulu.l %d4,%d5
    add.l %d5,%d0
    move.l %d1,%d5
    lsr.l #2,%d5
    move.l #0x9b340,%d6
    mulu.l %d6,%d5
    lea 0x400e21e0,%a1
    adda.l %d5,%a1
    move.l %a1,%a0
    adda.l #0x8ed80,%a0
    adda.l %d0,%a0
    rts
.address_bad:
    moveq #-1,%d0
    rts

/* d0 track,d1 context,d2 field -> raw byte, or -1 for invalid input.
 * Decoders own field defaults and packed-subfield validation. */
mp_read:
    lea -20(%sp),%sp
    movem.l %d4-%d6/%a0-%a1,(%sp)
    bsr.w .address
    tst.l %d0
    bmi.s .read_done
    bsr.w .snapshot_address
    moveq #0,%d0
    move.b (%a0),%d0
.read_done:
    movem.l (%sp),%d4-%d6/%a0-%a1
    lea 20(%sp),%sp
    rts

/* Read native KEY (offset 17) without making it a writable custom field. */
mp_read_key:
    lea -24(%sp),%sp
    movem.l %d2/%d4-%d6/%a0-%a1,(%sp)
    moveq #16,%d2
    bsr.w .address
    tst.l %d0
    bmi.s .key_done
    bsr.w .snapshot_address
    moveq #0,%d0
    move.b 1(%a0),%d0
.key_done:
    movem.l (%sp),%d2/%d4-%d6/%a0-%a1
    lea 24(%sp),%sp
    rts

/* d0 track,d1 context,d2 field,d3 byte -> 1 accepted, 0 invalid.
 * Caller validates semantic range. Update only working state, its current
 * bank CS1 mirror and native dirty bits. Saved Parts/Kit library stay native.
 * A short interrupt mask makes the byte/mirror/dirty update indivisible.
 */
mp_write:
    lea -24(%sp),%sp
    movem.l %d4-%d7/%a0-%a1,(%sp)
    cmpi.l #127,%d3
    bhi.w .write_bad
    bsr.w .address
    tst.l %d0
    bmi.w .write_bad
    move.l %d3,%d6
    bsr.w .store
    moveq #1,%d0
    bra.s .write_done
.write_bad:
    moveq #0,%d0
.write_done:
    movem.l (%sp),%d4-%d7/%a0-%a1
    lea 24(%sp),%sp
    rts
    .endif

/* ---- native Part replacement (MIDI PART STATE's part-copy.s) ------------
 * Publish a native Part replacement coherently without masking interrupts
 * throughout a native copy/clear. While a bank is being replaced, readers see
 * its complete outgoing window (the snapshot). Nested stock calls retain the
 * outer transaction. Reached through the resident entry gates (entry.s),
 * which call the stock routines until pt_resident_activate publishes these.
 */
pt_native_copy:
    lea -24(%sp),%sp
    movem.l %d0-%d1/%a0-%a1,(%sp)
    move.l 28(%sp),%d0
    move.l 36(%sp),%d1
    bsr.w .begin
    move.l %d0,16(%sp)
    movem.l (%sp),%d0-%d1/%a0-%a1
    move.l 36(%sp),-(%sp)
    move.l 36(%sp),-(%sp)
    move.l 36(%sp),-(%sp)
    bsr.w .copy_stock
    lea 12(%sp),%sp
    bra.s .finish
pt_native_init:
    lea -24(%sp),%sp
    movem.l %d0-%d1/%a0-%a1,(%sp)
    move.l 28(%sp),%d0
    move.l #PART_LEN,%d1
    bsr.w .begin
    move.l %d0,16(%sp)
    movem.l (%sp),%d0-%d1/%a0-%a1
    move.l 28(%sp),-(%sp)
    bsr.w .init_stock
    addq.l #4,%sp
.finish:
    tst.l 16(%sp)
    beq.w .finished
    /* Epoch and window publication are one short critical section. No
     * native copying, initialization or client notification runs masked. */
    lea -24(%sp),%sp
    movem.l %d0-%d4/%a0,(%sp)
    move.w %sr,%d3
    move.w #0x2700,%sr
    move.l pt_snapshot_bank,%d0
    subi.l #BANKS,%d0
    move.l #BANK_LEN,%d1
    divu.l %d1,%d0
    move.l %d0,%d4                  | the bank, for the notifications
    lsl.l #4,%d0
    lea pt_part_epochs,%a0
    adda.l %d0,%a0
    move.l pt_snapshot_parts,%d1
    moveq #0,%d2
.epoch_part:
    btst %d2,%d1
    beq.s .epoch_next
    addq.l #1,(%a0)
.epoch_next:
    addq.l #4,%a0
    addq.l #1,%d2
    cmpi.l #4,%d2
    bne.s .epoch_part
    clr.l pt_snapshot_bank
    clr.l pt_snapshot_parts
    move.w %d3,%sr
    /* Each replaced Part, to each client, unmasked: d0 its context. */
    moveq #0,%d2
.replaced_part:
    btst %d2,%d1
    beq.s .replaced_next
    move.l %d4,%d0
    lsl.l #2,%d0
    add.l %d2,%d0
    pt_replaced_calls
.replaced_next:
    addq.l #1,%d2
    cmpi.l #4,%d2
    bne.s .replaced_part
    movem.l (%sp),%d0-%d4/%a0
    lea 24(%sp),%sp
.finished:
    lea 24(%sp),%sp
    rts
.copy_stock:
    move.l %d2,-(%sp)
    move.l 8(%sp),%a1
    jmp 0x4002089e
.init_stock:
    lea -88(%sp),%sp
    movem.l %d2-%d7/%a2-%a6,(%sp)
    jmp 0x40005640

/* d0 destination,d1 length. Only resident bank writes intersecting working
 * Parts need a snapshot. Native copies spanning multiple banks are not a
 * live Part operation. Snapshot preparation only reads unchanged bytes:
 * interrupts remain enabled, including throughout native initialization.
 */
.begin:
    lea -32(%sp),%sp
    movem.l %d1-%d6/%a0-%a1,(%sp)
    tst.l pt_snapshot_bank
    bne.w .no_begin
    tst.l %d1
    beq.w .no_begin
    move.l %d0,%d2
    subi.l #BANKS,%d2
    cmpi.l #16*BANK_LEN,%d2
    bcc.w .no_begin
    move.l %d2,%d3
    move.l #BANK_LEN,%d4
    divu.l %d4,%d3
    move.l %d3,%d6                  | the bank, for the notifications
    mulu.l %d3,%d4
    sub.l %d4,%d2
    add.l %d2,%d1
    bcs.w .no_begin
    cmpi.l #BANK_LEN,%d1
    bhi.w .no_begin
    cmpi.l #WORK,%d1
    bls.w .no_begin
    cmpi.l #WORK_END,%d2
    bcc.w .no_begin
    addi.l #BANKS,%d4
    move.l %d4,%d5
    /* Publish the exact overlapped Parts, including partial copies. */
    moveq #0,%d0
    moveq #0,%d3
    move.l #WORK,%d4
.mask_part:
    cmp.l %d4,%d1
    bls.s .mask_next
    move.l %d4,%a0
    adda.l #PART_LEN,%a0
    cmpa.l %d2,%a0
    bls.s .mask_next
    bset %d3,%d0
.mask_next:
    addi.l #PART_LEN,%d4
    addq.l #1,%d3
    cmpi.l #4,%d3
    bne.s .mask_part
    move.l %d0,pt_snapshot_parts
    .if PT_LEN
    move.l %d5,%a0
    adda.l #WORK+PT_LO,%a0
    lea pt_snapshot,%a1
    moveq #4,%d3
.snapshot_part:
    move.l #PT_LEN/4,%d4
.snapshot_words:
    move.l (%a0)+,(%a1)+
    subq.l #1,%d4
    bne.s .snapshot_words
    adda.l #PART_LEN-PT_LEN,%a0
    subq.l #1,%d3
    bne.s .snapshot_part
    .endif
    move.l %d5,pt_snapshot_bank
    /* Each affected Part, to each client, before the native bytes change:
     * d0 its working Part's address, d1 its context. */
    moveq #0,%d3
.before_part:
    move.l pt_snapshot_parts,%d2
    btst %d3,%d2
    beq.s .before_next
    move.l #PART_LEN,%d0
    mulu.l %d3,%d0
    add.l %d5,%d0
    addi.l #WORK,%d0
    move.l %d6,%d1
    lsl.l #2,%d1
    add.l %d3,%d1
    pt_before_calls
.before_next:
    addq.l #1,%d3
    cmpi.l #4,%d3
    bne.s .before_part
    moveq #1,%d0
    bra.s .begin_done
.no_begin:
    moveq #0,%d0
.begin_done:
    movem.l (%sp),%d1-%d6/%a0-%a1
    lea 32(%sp),%sp
    rts

    .balign 4
pt_snapshot_bank: .long 0
pt_snapshot_parts: .long 0
pt_part_epochs: .space 64*4
pt_snapshot: .space 4*PT_LEN
    pt_tables
