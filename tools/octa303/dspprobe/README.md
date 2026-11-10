# OCTA303 DSP probe (10 Nov 2026): does a value from the ColdFire reach the DSP every frame?

The first brick of the hybrid idea (MaMarko): the 303's filter and VCA as a hidden DSP stage at the per-track
source seam (where ANALOG BD and BLKPYRAMD render), the VCO and envelopes on the ColdFire.

This branch's `octa303.s` is a **probe, not a release**: each sample's R long carries a per-track sample count in
its low 16 bits (`S_PRB`). Under the port (`ot_emu`, the acidtrack bus image, play_gate's fixture: T5/T6 OCTA-303
every step, 300 BPM, 1,500 frames):

- `run.py` + `check_blocks.py`: the host-port blocks (`--block-dump`). T5 and T6 are in core 0's block
  (`0x800021d0` / `0x80002c50`, 336 B a track: two 8-word headers, then 16 samples × L hi, L lo, R hi, R lo).
  1,500 frames, no gap; the count continuous over 23,984 samples (0 breaks). `check_blocks.log`.
- `mk_port.py`: a local port that records DSP X memory at payload A's source seam (P:0x39c: the record at
  `x:$209`, the track `x:$418`) and after the stock source (P:0x426: X:0..31). `dsp_check.log`: 1,501 records a
  track at the seam, the count continuous (0 breaks), one record a frame (67,802-76,948 DSP instructions apart),
  and the stock source's 24-bit output = the record's words (24,016/24,016: L = hi16 << 8, R = hi16 << 8 | the
  low half's top byte).

What it cannot see: the unit's timing (the port runs a frame when the work is done) and the host-port masking
trap (TRAPS.md trap-host-mask, host commands, not these blocks). The same path carries ANALOG BD's control
records on hardware.
Written by Claude (Anthropic).
