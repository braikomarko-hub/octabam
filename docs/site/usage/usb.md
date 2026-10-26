Connect the Octatrack to a computer for USB MIDI and audio. USB storage mode
(DISK MODE) works as in stock OS.

The computer sees one device with MIDI in and out, an audio input (the
Octatrack's output) and, with IN set, an audio output (the computer's
channels into the Octatrack's inputs). Audio is 44.1 kHz, 24-bit (UAC2).

## Settings

![BRAIN > SETTINGS, the USB group: CUE, IN and MAIN.](../../img/usb/settings.png)

*PROJ > BRAIN > SETTINGS, the USB group. `*` marks a value that takes effect
at the next boot.*

| Setting | Default | Values | What it does |
|---|---|---|---|
| TRACKS | PRE | OFF, PRE, POST | Sends the 16 track channels to the computer: tracks 1 to 8, track N on channels 2N-1 and 2N. PRE is before the track's LEVEL, the crossfader, MAIN volume and the master effects. POST is after each track's own LEVEL, mute and solo; MAIN volume is not applied. |
| MAIN | ON | OFF, ON | Sends the MAIN mix (2 channels), the signal sent to the MAIN outputs. It includes LEVEL, the crossfader, MAIN volume and the master effects. |
| CUE | ON | OFF, ON | Sends the CUE mix (2 channels). |
| MASTER | OFF | OFF, ON | Sends track 8's left and right (2 channels). |
| IN | OFF | OFF, AB, CD, ABCD | Takes the computer's channels in as Octatrack inputs. AB: computer channels 1 and 2 are inputs A and B, and C and D stay on the jacks. CD: the same on C and D. ABCD: computer channels 1 to 4 are inputs A to D. |
| MIDI | ON | OFF, ON | USB MIDI in and out. With MIDI OFF the computer sees storage and audio only, and the audio interface numbers change. |

The channels the computer receives are the ones switched on, in the order
TRACKS, MAIN, CUE, MASTER. The counts are 0, 2, 4, 6, 16, 18, 20 or 22
channels. With the defaults it is 20: channels 1 to 16 are the tracks, 17 and
18 are MAIN, 19 and 20 are CUE. At USB full speed the stream is two channels,
the stereo sum.

IN needs at least one of TRACKS, MAIN, CUE or MASTER switched on, because the
computer's stream is timed from the Octatrack's output. If none is on,
changing IN shows **IN NEEDS AN OUTPUT STREAM** and IN stays OFF. IN is served
at USB high speed only.

### Changing a setting

1. Open **PROJ > BRAIN > SETTINGS**. The USB group lists CUE, IN, MAIN, MASTER,
   MIDI and TRACKS.
2. Move to a row with **UP** and **DOWN**.
3. Press **YES** to step through the values, or **LEFT** and **RIGHT** to step
   down and up, stopping at the ends.
4. Switch the Octatrack off and on. A value that ends in `*` takes effect at the
   next boot, and the computer sees the new device when it starts. The values
   are kept in `BRAIN/card.work` on the card.

![The end of the USB group: TRACKS, with * AT NEXT BOOT under the list.](../../img/usb/settings-end.png)

A remix can fix a setting. `octabam` and `octabam-bus` set IN to OFF without
fixing it.

### Without BRAIN

A remix built without BRAIN has no settings menu and no `BRAIN/card.work`.
USB uses the values the image was built with: the defaults above, changed by
the remix's `settings=` (for example
`settings={("octabam.usb", "TRACKS"): "POST"}`). To change one, change the
remix and rebuild; `python3 tools/remix/brain.py resolve <remix>` prints each
setting and where its value came from. This was read from the source and not
run on a unit.

## USB MIDI

MIDI in and out over USB, mirroring the DIN ports. The sequencer, time
stretch, the LFOs and the FX follow USB MIDI clock; this was reported working
on one MKI after the 6 Oct 2026 change, and which of the three was checked is
not recorded.

## Audio in

With IN set, the computer's channels are the Octatrack's inputs, as described
under IN above. While the computer's stream is closed, the jacks are the inputs.

## Reading USB activity

![BRAIN performance: USB counters.](../../img/usb/performance.png)

*PROJ > BRAIN > PERFORMANCE, the USB tab.*

The USB tab counts audio underruns and overruns and dropped MIDI output
messages. It reads **NOT IN THIS IMAGE** when the image has no USB module.
