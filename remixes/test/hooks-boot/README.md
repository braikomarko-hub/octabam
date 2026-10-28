# hooks-boot (test remix)

BOOT TRACE beside [PARTS](../../../modules/parts/README.md), with MIDI LOOPBACK (PARTS's
client) and the stock effects. Both take the boot's call after the platform loader
(`0x40000512`), so the registry appends [HOOKS](../../../modules/hooks/README.md), which sends
BOOT TRACE's note 3 and then runs PARTS's activation, which makes the stock call.

`tools/verify/verify_hooks.py hooks-boot` checks the chain in this image after
`make bus REMIX=hooks-boot`; `tools/verify/verify_parts.py hooks-boot` checks the activation.

## Where it has run

Not flashed. Built, and its chain checked (verify_hooks).
