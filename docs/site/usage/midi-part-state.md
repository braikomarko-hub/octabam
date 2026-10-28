Provides the native Part-state access used by MIDI Loopback. Include MIDI PART
STATE when selecting MIDI LOOPBACK in a custom remix. It adds no screen or
control of its own.

Routing settings belong to the native Part: Save, Reload, Clear and Paste use
the existing Part operations. Consumers choose the context for their producer:
Loopback reads each MIDI track's applied Part, independently of the Part selected
for editing or retained by an audio voice.

## Stock compatibility

Stock 1.40C cold project load clamps the routing flags to zero (EXT). Saving
the bank on stock overwrites its INT/BOTH settings. Loading alone does not
rewrite every bank file. Preserve a separate project backup before returning
to stock if those settings matter.

The startup helper resides beside the existing OS entry gates. Its callbacks
are resolved from the selected runtime at build time; native DSP startup and
the runtime memory reservation are unchanged.
