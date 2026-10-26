Scrape: this track’s input with internal noise, amplitude-modulated by an
audio-rate LFO — or, with SETUP **SRC=NBR**, by the previous track’s
envelope. HPF/COLR shape the **noise** only; dry stays unfiltered.
Soft clip + **FDBK** on the noise only, then BAL dry↔noise. Always wet —
there is no dry/wet MIX.

Replaces **COMB FILTER** on FX2 (id `0x13`). DSP words sit in harvested **PLATE REV**.

## Access

Select a track, press FX2, pick **VOID**. Page 1: BAL, RATE, COLR, HPF, DRV, FDBK.
Page 2 (SETUP): SHPE, DPTH, WID on the top row; **SRC** bottom left.

![FX2 SETUP with VOID selected.](../../img/void/setup.png)

*FX2 SETUP: SHPE, DPTH, WID (top); SRC bottom left.*

![VOID main page.](../../img/void/main.png)

*VOID main page: BAL, RATE, COLR, HPF, DRV, FDBK.*

A Part saved under an older VOID layout will not match — re-pick VOID or
stamp defaults after flashing.

## Operation

- **BAL** — dry↔noise (**0 = full dry always**, **127 = pure noise**). AM, DRV and
  FDBK never touch the dry.
- **COLR** / **HPF** — darken or thin the **noise** only; dry is untouched.
  COLR open (127) is bright; HPF 0 bypasses.
- **SRC** (SETUP): **LFO** (default) uses RATE/SHPE; **NBR** AM’s the **noise**
  from the previous track’s keybus — quiet → noise stops (RATE idle). On
  track 1, NBR reads T1’s own keybus lane (`Y:$800`) — it follows itself.
- **DPTH** (SETUP): same in both modes — how hard the modulator opens the noise.
- **WID** (SETUP): stereo grit from a second noise through the same
  HPF/COLR/DRV (no FDBK) and AM — `L/R = mid ± (w/2)·side` (mono keeps
  the LFO’d mid); **0 = mono**.
- **FDBK** with **DRV** screams; past ~50 with drive used to rail to DC silence —
  feedback is AC-coupled now so it keeps scraping.

## Parameters

| Page | Knob | Range | Default | What it does |
|---|---|---|---|---|
| 1 | BAL | 0..127 | 0 | dry↔noise (0 = exact dry, 127 = pure noise) |
| 1 | RATE | 0..127 | 72 | LFO rate; idle when SRC=NBR |
| 1 | COLR | 0..127 | 64 | noise low-pass; 127 = open |
| 1 | HPF | 0..127 | 0 | noise high-pass; 0 = bypass |
| 1 | DRV | 0..127 | 0 | soft-clip on noise only |
| 1 | FDBK | 0..127 | 0 | one-sample feedback on noise only |
| 2 | SHPE | SIN / SQR / SAW | SIN | LFO shape; idle when SRC=NBR |
| 2 | DPTH | 0..127 | 127 | AM depth on noise only (default max) |
| 2 | WID | 0..127 | 0 | mono → stereo grit |
| 2 | SRC | LFO / NBR | LFO | AM source |
