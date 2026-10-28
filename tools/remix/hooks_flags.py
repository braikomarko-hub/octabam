"""The HOOKS flags a participant's remix.inc carries (modules/hooks).

A module whose routine a HOOKS bridge calls (frame_tail, frame_entry, boot)
is built with that bridge's flag: 1 when the remix carries the bridge and
the module is in it -- the routine then returns instead of replaying the
stock instructions -- else 0, its own bytes unchanged. Called from a
participant's Linked.include at build time, not when manifests load.
"""
import functools
import pathlib
import runpy

ROOT = pathlib.Path(__file__).resolve().parents[2]


@functools.cache
def _hooks():
    return runpy.run_path(str(ROOT / "modules/hooks/manifest.py"))


def inc(key, modules) -> str:
    """remix.inc lines for module `key` in a selection of module keys."""
    return _hooks()["flags_inc"](key, modules)
