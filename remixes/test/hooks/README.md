# hooks (test remix)

MORPH, REC_TRIG_MUTE and REC THRESHOLD in one image, with STORE (which MORPH saves
through) and the stock effects. Alone, each pair here would be refused: MORPH and
REC_TRIG_MUTE both change the [TRACK]-held key layer, REC_TRIG_MUTE and REC THRESHOLD
both replace the track status icon renderer's state-cache load. The registry appends
[HOOKS](../../../modules/hooks/README.md), which owns both sites and calls each
module's own routine.

`tools/verify/verify_hooks.py hooks` runs the bridged status-icon chain and decodes the
[TRACK]-layer table under Unicorn from the modules' own sources, and checks this image's
two sites once it is built.

## Where it has run

Not flashed. Under Unicorn only (verify_hooks).
