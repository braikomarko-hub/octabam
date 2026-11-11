"""OCTA303 vFable: the 303 gate (o3_gate in modules/octa303/octa303.s) in Python, field for field.

The gate is part of the shell: it opens at a START and closes 3.5 of the step's 6 clocks later (Whittle), held
open through a slide on the next step; GATE OFF leaves the note to the AMP page.  test_octa303 runs o3_gate and
gate_frame side by side.  The constants are read from octa303.s itself.  Code written by Claude (Anthropic).
"""
import os, re
SRC = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'modules', 'octa303', 'octa303.s'))
C = {m.group(1): int(m.group(2)) for m in re.finditer(r'^\s+\.set\s+(GATE_\w+),\s+(-?\d+)', open(SRC).read(), re.M)}
FIELDS = ('gmode', 'gate', 'glvl', 'gstep', 'lstep', 'ltick', 'idle', 'kmax', 'tps', 'gnew', 'gel', 'gend',
          'gsel', 'fcnt', 'fpt', 'fseen', 'gelf', 'fskip', 'stopd')

class GateState:
    """The gate's fields of a track's state (the S_ fields of the same names), all 0 at boot."""
    def __init__(self):
        for f in FIELDS: setattr(self, f, 0)
        self.latched = 0

def gate_frame(st, seq):
    """v6.5, once a frame (the frame's last call) on a 303 track: seq = (hold, step, tick, slides,
    length[, running]) as the unit reads them -- the track's AMP HOLD from the live lane, the sequencer's step
    word and tick byte, the OR of the track record's trigless-trig and trigless-lock masks (bit s =
    step s), the track's length.
    v6.5d: the gate is timed from the note's START, in ticks (gel), not from the step word: on the
    unit a START reaches the renderer about a tick after the step word moves (measured, 12 Oct 2026:
    the step-word gate closed ~1/3 of a step after the note).  Half a step = tps ticks counted
    twice (gend = tps, +2 tps a tie)."""
    hold, s, k, mask, L = seq[:5]
    run = 1 if (seq[5] if len(seq) > 5 else 1) == 1 else 0   # v7.4: the transport word (0x800065b8): 1 = running;
                                                       # 0 stopped and rewound, 2 stopped by the STOP key (STEM_REC.md)
    if not 1 <= L <= 64: L = 16
    s = s % L
    moved = s != st.lstep or k != st.ltick
    restart = st.idle >= C["GATE_IDLE"]                   # standing still for GATE_IDLE frames (no transport seen)
    if not run: st.stopd = 1                           # v7.4: a STOP seen; the next move while running is a PLAY
    if s != st.lstep:                                  # a new step: the last one's ticks
        if st.kmax >= 1: st.tps = st.kmax + 1
        st.kmax = 0; st.idle = 0
    elif k != st.ltick: st.idle = 0
    elif st.idle < C["GATE_IDLE"]: st.idle += 1
    if k > st.kmax: st.kmax = k
    st.lstep, st.ltick = s, k
    if st.tps == 0: st.tps = C["GATE_TPS0"]
    if moved and st.gel < 4096: st.gel += 1            # ticks since the START
    f = min(st.fcnt + 1, 4095)                         # v7.0: the frames a tick, measured
    if moved and run:                                  # v7.4: a move while stopped (STOP resets the step word) is no tick
        if st.stopd or restart or not st.fseen:        # PLAY (v7.5: also the first move a fresh state sees, the first
                                                       # PLAY after boot): the position reset and the first tick come a frame apart
            st.stopd = 0; st.fskip = C["GATE_FSKIP"]      # (measured under the port): neither interval is a tick, and
            st.gel = 0; st.gelf = 0                    # the last note's clock restarts (no 1-frame snap before the START)
        if st.fskip: st.fskip -= 1
        elif st.fseen: st.fpt = f
    if moved: st.fseen = 1; f = 0
    st.fcnt = f
    if st.gelf < 65535: st.gelf += 1                   # v7.0: the frames since the START
    if st.gnew:                                        # a 303 START: the note's step, the clock from 0
        st.gnew = 0; st.gate = 1; st.gel = 0; st.gelf = 0
        st.gend = (7 * st.tps + 3) // 6                # v7.0: 3.5 of the step's 6 clocks, doubled (Whittle)
        cur = (s - 1) % L                              # v7.4: the step word holds the NEXT step (measured under the
        st.gstep = (cur + 1) % L if 2 * k >= st.tps else cur   # port: b2 = b4 + 1): the note's step is one less
    if not st.gsel:                                    # v7.0: SETUP's GATE OFF: the AMP decides
        st.gmode = 0; st.glvl = 32767; return
    st.gmode = 1
    if st.idle >= C["GATE_IDLE"]:                         # the sequencer stopped: the AMP decides
        st.gate = 1; return
    due = (2 * st.gelf >= st.gend * st.fpt) if st.fpt else (2 * st.gel >= st.gend)
    if st.gate and due:                                # 3.5 clocks (+ a step a tie) since the START
        nxt = (st.gstep + 1) % L
        if (mask >> nxt) & 1:                          # the next step slides: still on
            st.gstep = nxt; st.gend += 2 * st.tps
        else:
            st.gate = 0
