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

## Step 2 (10 Nov 2026, evening): a real hidden DSP stage that reads values and filters the block

- `o3stage.asm` (65 words + linear-mode setup = 71, payload A, at the unused end of SPRING REV's region,
  P:0x015a9): the stock `move x:>$20a,r7` at P:0x426, where both source paths meet before AMP, is a jsr to it.
  For a record signed in words 160-161 (`$3303 $a303`, past anything the FLEX layout writes) it reads the
  coefficient c from word 162 and runs a one-pole low-pass, y += c (x - y), on the 16 stereo samples the stock
  source left at X:0..31, per track, state at Y:$f00 + 2 * (track within the core). Built only with
  `O3_DSPPROBE=1 make bus REMIX=acidtrack` (tools/build/build_bus.py, this branch).
- `octa303.s`: on the frame's last call, long 80 = the signature and long 81 = c (0x0400 + (count & 0x1ff) * 32,
  Q15), so c moves every frame.
- `check_stage.py` on the recording port's trace (pcs 0x39c, 0x426, 0x428): T5 and T6 filtered on 1,498 of 1,501
  frames (the first three carry no record yet), **the model of the stage's arithmetic matches every one, bit for
  bit**, with 32 different coefficients; T7 and T8 (no OCTA303) untouched. The read-back from core 0 still carries
  the audio. `check_stage.log`.
- Not checked: the unit (timing, the uninitialised Y state on a real boot: the port starts at zero, trap-dirty-state),
  the cycle cost on the chip, a START splitting a frame (the stage only reads X:0..31 after the stock source, so the
  layout of the record's samples does not matter to it).
