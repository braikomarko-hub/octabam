# BOOT SMILE

At power-on, in place of the Elektron logo: a white smile on black grows from the centre, stays a
moment, then melts down off the screen. The LED wave of the stock boot stays. The boot animation
lasts 3.8 s instead of 2.8 s.

```
  ·      ( )     (  ◡  )    (• ◡ •)  …  (• ◡ •)    melting    black
 0 s            0.9 s                  1.9 s                  3.5 s  3.8 s
```

Code: written by Claude (Anthropic); idea and tests on the Octatrack: MaMarko.
The frames are generated: edit `tools/bootsmile/gen_bootsmile.py` (the drawing) or
`tools/bootsmile/bootsmile_code.s` (the code) and run it; it rewrites `bootsmile.s`.

## How (measured from the user's 1.40C)

- The boot logo is `FUN_4005596c(surface)` on the screen surface `0x400bf10a` (128 × 64, bits =
  the LCD plane `0x46c7e0ea`). Its loop clears the surface, blits the logo record `0x400ba8b2` and
  the stars through `%fp` (= `0x400128a8`, loaded once at `0x400559b4`), flushes, runs the LED
  wave, until DTIM3's counter says 559 × 5 ms.
- The build points that `%fp` at `bs_blit`: for the logo it copies the frame of the moment
  (DTCN3 / 6,600,000 = the 50 ms slot; 132,000 ticks a millisecond, from the stock's own
  559 = 2.8 s) into the plane; the stars are dropped. The 559 is poked to 760.

## Measured

- `tools/bootsmile/test_bootsmile.py`: the source under cfsim: every 50 ms slot shows its frame,
  stars dropped, black after the end, registers kept, the generated file up to date.

## On the unit

Not yet. `tools/bootsmile/boot_shots.py` photographs the boot under the port.

## Open

- Inferred: that the flush `0x40013abc` sends the plane as it stands (as for the stock logo).
