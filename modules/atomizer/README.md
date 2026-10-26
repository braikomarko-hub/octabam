# `atomizer` -- AtoMizer

A granular delay for FX2, by Marko Brajković, after the **Red Panda Particle**
(V1 on the Spin FV-1, 2011; Particle 2, 2019). Particle is Red Panda's name and
pedal: AtoMizer re-derives its behaviour for the Octatrack from the Particle 2
owner's manual (firmware 2.2, July 2023) and Red Panda's public changelog. No
Red Panda code or firmware was read or used. 1,478 DSP words and a 42-word
P table; `atomizer.asm` is proven BIT-IDENTICAL against an integer model of
the same arithmetic, `atomizer_ref.py`.

The mono sum of the track goes into a ring (15,870 words, 360 ms, in RCYC;
8,192 words, 186 ms, in the other feedback modes, whose second half of the
slot is the aux line). Two grain voices read the ring through a
linear-interpolated position (9 fractional bits) and a window, and SPRD pans
each grain at random. What the MODE changes is where each grain starts, how
fast it reads and how often a new one starts:

| MODE | TIME | PARA | The grains |
| --- | --- | --- | --- |
| DDEN (delay + density) | delay | density | IOI from 4 L (PARA 0, the density floor) to L/2; overlapped grains get triangle windows |
| DLFO (delay + LFO) | scan range | LFO rate | the delay scans 0..TIME with a triangle LFO, 0.05..5 Hz |
| DREV (delay + reverse) | delay | direction | each grain plays backwards with probability PARA |
| DPCH (delay + pitch) | delay | jump | each grain jumps an octave up or down with probability PARA |
| DRND (delay + random) | delay | randomness | each grain starts somewhere between the delay and up to PARA x delay earlier |
| PDTN (pitch + detune) | pitch -12..+12 | detune | a pitch shifter; the two voices PARA (to half a semitone) apart |
| PLFO (pitch + LFO) | pitch -12..+12 | LFO rate | the pitch sweeps between unison and TIME with the LFO |
| PDEN (pitch + density) | pitch -12..+12 | density | the pitch shifter, thinned like DDEN |

Pitch uses a table of 512·2^(s/12), interpolated in 1/256 semitone. A grain
that reads faster than the input starts far enough back that it never
overtakes the write head.

## Knobs

| Page | Knob | Range (default) | What it does |
| --- | --- | --- | --- |
| main, A | CHOP | 0–127 (48) | Grain length L: CHOP²/2 + 64 samples, 1.5–184 ms; SYNC: 1/64 .. 1/4 of the tempo. Halved until it fits the MODE and the ring. |
| main, B | TIME | 0–127 (40) | The delay modes: the delay (SYNC: 1/64, 1/32, 3/64, 1/16, 3/32, 1/8, 3/16, 1/4). The pitch modes: -12..+12 semitones (64 is unison). |
| main, C | PARA | 0–127 (64) | The MODE's parameter (table above). |
| main, D | FDBK | 0–127 (0) | RCYC: the wet back into the ring (to 0.95). POST and PING: the post line's feedback. REP, R1/2, R1/4: the repeats, 0..8. RPCT: the probability of a repeat. |
| main, E | FREZ | 0–127 (0) | 0 off -- always releases, whatever came before. 1..126: the ring stops taking input while the track is quiet (a slow envelope under (FREZ/128)²/4). 127: frozen; the grains, the LFO and the scan go on over what the ring holds. |
| main, F | MIX | 0–127 (64) | 0 is exactly dry. To 64 the wet rises to unity over the whole dry; from 64 to 127 the dry fades out (the Particle 2.0.1 BLEND law). |
| SETUP, A | MODE | the eight above (DDEN) | Changing it moves no knob (the Particle 2.2 expert mode). |
| SETUP, B | TONE | 0–127 (127) | A one-pole low-pass in the feedback (RCYC, POST, PING): 0 dark, 127 open. |
| SETUP, C | FBMD | AUTO, RCYC, POST, PING, REP, R1/2, R1/4, RPCT (AUTO) | The feedback mode (below). Moving between RCYC and the others clears the slot: 62 calls of dry, about 22 ms. |
| SETUP, D | SPRD | 0–127 (0) | Random stereo spread of the grains. |
| SETUP, E | SYNC | FREE / SYNC | SYNC: CHOP and TIME are divisions of the Octatrack's tempo, and an attack in the input (a fast envelope over twice a slow one) restarts the grain and the REP slot. |
| SETUP, F | V1 | 0–127 (0) | Reserved for the FV-1's memory colour; does nothing yet. |

## Feedback modes (FBMD)

- **AUTO**: POST in DDEN, RCYC in every other MODE (the Particle 2.2.0 default).
- **RCYC**: recycle -- the ring takes the input plus FDBK x TONE(wet), so the
  repeats go back through the grains.
- **POST**: the grains go into a separate delay line (7,678 words) with FDBK x
  TONE feedback; its time is the delay (2 L in the pitch modes).
- **PING**: two lines of 3,839 words; the grains enter on the left and each
  repeat changes side.
- **REP**: slots of L samples: a live slot is captured, then the next N slots
  (FDBK: 0..8) replay it, then live again.
- **R1/2**, **R1/4**: a fresh capture every N + 1 slots; in between, each slot
  replays the capture with probability 1/2 or 1/4, else plays live.
- **RPCT**: each slot replays the last capture with probability FDBK, else
  plays live and is captured.

A replayed slot crossfades in and out over min(128, L/4) samples, so slot
edges do not click.

## Memory and cost

The FX2 slot from the allocator (read at init, `x:>$213`), up to +$3DFD:
15,870 words (SIDECHAIN_COMPRESSOR's window sits above). State in r7 +
$00..$5f, all zeroed at init; the slot is cleared (256 words a call, dry
meanwhile) before the first wet sample and on every layout change.

`cycle_count.py`: 599 cycles a sample per instance, pricing a grain start on
every sample and the worst feedback mode; four on a core 2,396 of the 3,120
usable. `dsp_host` measured 283–346 executed instructions a sample per
instance in steady state (the dispatcher included), 359 in the worst block.

## Measured

All gates of `tools/verify/verify_atomizer.py` pass on this tree, 20 Oct 2026
(`dsp_host`, a private image with the stock code built in and AtoMizer in the
space of DELAY, SPRING REV, PLATE REV and DARK REV, as `remixes/test/atomizer`
places it):

- **reference**: every MODE, every FBMD, FREZ held and by threshold, SYNC with
  a tempo, SPRD, MIX and TONE: the DSP output is bit-identical to
  `atomizer_ref.py` over 1.6 s, on core 0 and (a set) on core 1.
- **automation**: every knob moving every 23 blocks, MODE and FBMD included
  (252 layout changes), with and without a trig split: bit-identical.
- **dry**: MIX 0 is the input sample for sample, knobs still and moving.
- **idle**: with FDBK 0 every feedback mode falls to exact digital silence.
- **isolation**: eight instances, four a core, under the write guard: no stray
  write, each identical alone. **garbage**: a garbage instance block renders as
  a zeroed one.

What none of them can see: the unit itself (memory-contention stalls, the
real cycle wall with other effects loaded), and how it sounds -- the model is
the reference, not the pedal.

## Open

- **The FX id.** Every free FX2 id (0x04..0x1f) is claimed in this tree, and a
  16K-buffer effect may not take a stock id FX1 lists (an FX1 slot is 3,072
  words). Development uses DELAY's (0x08, FX2 only); a remix that keeps the
  stock DELAY needs the owner to free an id.
- **Code space.** 1,520 words with the table: a remix needs a harvested run that
  large (here SPRING REV + PLATE REV + DARK REV).
- Not yet: the V1 colour (the FV-1's 1s3e10m memory and 32 kHz band limit),
  the LFO restart at the pattern start (the Particle's TAP), a smoothed MIX.
