"""OCTA303 vFable, the 303 voice on the DSP -- phase 2's grid (code written by Claude): today's integer model against
the reference that computes the per-sample loop as a DSP56300 would (o3d_sample in o3k.c).  Run build.sh first."""
import sys, os, ctypes, itertools, json, numpy as np
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
OUT = os.path.join(ROOT, 'out', 'octa303', 'dsp')
import importlib.util
def _load():
    """the model's wrapper (model_v7/o3model.py) bound to the DSP reference kernel, under a name of its own: a caller
    may have the plain model loaded as o3model too (the engine's tests)"""
    old = os.environ.get('O3K_LIB'); os.environ['O3K_LIB'] = os.environ.get('O3K_DSP_LIB') or os.path.join(OUT, 'libo3k_dsp.so')
    try:
        sp = importlib.util.spec_from_file_location('o3model_dsp', os.path.join(ROOT, 'tools', 'octa303', 'model_v7', 'o3model.py'))
        mod = importlib.util.module_from_spec(sp); sp.loader.exec_module(mod)
    finally:
        if old is None: del os.environ['O3K_LIB']
        else: os.environ['O3K_LIB'] = old
    return mod
m = _load()
M = m.load_laws(os.path.join(ROOT, 'tools', 'octa303', 'model_v7', 'leggi_A_v5.json'))
L = m._lib; L.o3_get_dsat.restype = ctypes.c_longlong; L.o3_get_dbig.restype = ctypes.c_longlong
STEP = 5088   # 16 x 318 samples: about 130 BPM sixteenths
# (semitones from C2, accent, slide into next, rest)
PAT = [(0,0,0,0),(0,1,0,0),(12,0,1,0),(7,0,0,0),(0,0,0,1),(3,1,0,0),(15,0,1,0),(12,1,0,0),
       (0,0,0,0),(10,0,0,0),(0,1,1,0),(24,0,0,0),(5,0,0,1),(0,1,0,0),(19,0,1,0),(-5,0,0,0)]
def ev(cut,res,env,wave,dec=64,acc=100,f0=65.406):
    retrig=[]; slides=[]; gate=[]
    for k,(st,a_,sl,rest) in enumerate(PAT):
        t=k*STEP
        if rest: continue
        prev_slide = k>0 and PAT[k-1][2] and not PAT[k-1][3]
        if prev_slide: slides.append((t, float(st)))
        elif k>0: retrig.append((t, acc if a_ else 0, float(st)))
        if not sl: gate.append(t + STEP//2)
    return dict(freq_hz=f0, cut=cut,res=res,env=env,dec=dec,acc=0,wave=wave,retrig=retrig,slides=slides,gate_off=gate,nsamp=16*STEP)
def run(e, bits=None, rnd=0, M=None):
    M = M or globals()['M']
    if bits is None: L.o3_set_dref(0, None, 0)
    else: L.o3_set_dref(1, (ctypes.c_int*5)(*bits), rnd)
    y, dg = m.render_engine(e, M, want_diag=True); y = y.astype(np.float64)
    rc = L.o3_last_rc()
    assert rc == 0, rc
    s, b = L.o3_get_dsat(), L.o3_get_dbig(); L.o3_set_dref(0, None, 0)
    return y, s, b
def db(ref, y):
    d = y-ref; tot = 10*np.log10((d@d+1e-9)/(ref@ref))
    W=2048; n=len(ref)//W
    er = (d[:n*W].reshape(n,W)**2).sum(1); sr=(ref[:n*W].reshape(n,W)**2).sum(1)
    return tot, 10*np.log10((er.max()+1e-9)/sr.max())
CASES = list(itertools.product([0,20,40,64,90,127],[0,64,100,127],[0,64,127],[0,1]))
