/* PARTS's resident gates (from radiohagen's MIDI PART STATE entry.s). Stock
 * memcpy and Part initialization run before the platform loader has placed
 * the runtime, so the two entries stay in ROM and call stock until the boot's
 * post-loader call (pt_resident_activate) publishes the runtime's wrappers.
 * C ABI volatile a0 is assigned by both native bodies before it is consumed.
 */
    .text
    .global pt_copy_entry,pt_init_entry,pt_copy_target,pt_init_target,pt_resident_activate
    .global mp_copy_target,mp_init_target
    .set mp_copy_target, pt_copy_target   | MIDI PART STATE's names, for its gates
    .set mp_init_target, pt_init_target
pt_copy_entry:
    move.l pt_copy_target,%a0
    cmpa.l #0,%a0
    beq.s .copy_stock
    jmp (%a0)
.copy_stock:
    move.l %d2,-(%sp)               | memcpy 0x40020898's displaced instructions
    move.l 8(%sp),%a1
    jmp 0x4002089e
pt_init_entry:
    move.l pt_init_target,%a0
    cmpa.l #0,%a0
    beq.s .init_stock
    jmp (%a0)
.init_stock:
    lea -88(%sp),%sp                | Part initialization 0x40005638's
    movem.l %d2-%d7/%a2-%a6,(%sp)
    jmp 0x40005640
    .balign 4
pt_copy_target: .long 0
pt_init_target: .long 0

/* 0x40000512: `jsr pt_resident_activate` replaces `jsr 0x4000f938`, after the
 * platform loader has returned. The runtime's wrappers are published, then
 * the stock call is made in its place and returns to the boot. */
pt_resident_activate:
    move.l %d0,-(%sp)
    move.l #pt_native_copy,%d0
    move.l %d0,pt_copy_target
    move.l #pt_native_init,%d0
    move.l %d0,pt_init_target
    move.l (%sp)+,%d0
    jmp 0x4000f938
