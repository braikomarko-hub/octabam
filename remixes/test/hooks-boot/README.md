# hooks-boot (test remix)

BOOT TRACE beside MIDI PART STATE, with MIDI LOOPBACK (which requires it) and the stock
effects. Both take the boot's call after the platform loader (`0x40000512`), so the registry
appends [HOOKS](../../../modules/hooks/README.md), which sends BOOT TRACE's note 3 and then
runs MIDI PART STATE's activation, which makes the stock call. When radiohagen's STORE native
Part access (sambanks/octabam#824) replaces MIDI PART STATE, the bridge's second participant
becomes STORE's activation.

`tools/verify/verify_hooks.py hooks-boot` checks the chain in this image after
`make bus REMIX=hooks-boot`.

## Where it has run

Not flashed. Built, and its chain checked (verify_hooks).
