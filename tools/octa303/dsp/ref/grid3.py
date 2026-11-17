"""Phase 2, second round (code written by Claude): 288 cases, total error, per-window error above 20 Hz, DC, saturations.
Thresholds: see the vFable diary, 17 Nov 2026 15:05."""
import os
import numpy as np, ctypes, itertools, json
from grid import *
from scipy.signal import butter, sosfilt
sos = butter(2, 20/22050, 'hp', output='sos')
W=2048
BASE = [dict(c=c) for c in itertools.product([0,20,40,64,90,127],[0,64,100,127],[0,64,127],[0,1])]
SUB = list(itertools.product([0,64,127],[0,100,127],[0,127],[0,1]))
VAR = [dict(c=c, dec=0) for c in SUB] + [dict(c=c, dec=127) for c in SUB] + [dict(c=c, acc=127) for c in SUB] + \
      [dict(c=c, f0=130.8128) for c in SUB] + [dict(c=c, laws='DEFAULT') for c in SUB]
res=[]
for k in BASE+VAR:
    Mx = m.DEFAULT if k.get('laws') else M
    e = ev(*k['c'], dec=k.get('dec',64), acc=k.get('acc',100), f0=k.get('f0',65.406))
    try: r,_,_ = run(e, None, 0, Mx); y,sat,big = run(e, [24]*5, 0, Mx)
    except AssertionError as x_: print("RIFIUTATO", k, x_); continue
    d=y-r; tot=10*np.log10((d@d+1e-9)/(r@r))
    dh=sosfilt(sos,d); rh=sosfilt(sos,r); n=len(r)//W
    ew=(dh[:n*W].reshape(n,W)**2).mean(1); sw=(rh[:n*W].reshape(n,W)**2).mean(1)
    lim=np.maximum(sw*1e-4, sw.max()*1e-8)
    marg=10*np.log10((ew+1e-12)/lim)          # > 0 = fuori soglia
    q=len(r)//4; dc=abs(y[-q:].mean()-r[-q:].mean())
    res.append(dict(k=str(k),ewmax=float(np.sqrt(ew.max())),tot=tot,wmarg=marg.max(),wrel=float(10*np.log10((ew+1e-12)/(sw+1e-12)).max()),dc=dc,sat=sat,big=big))
A=lambda f: np.array([x[f] for x in res])
print(len(res),'casi')
i=A('tot').argmax(); print('(1) totale: peggiore %.1f dB sotto (%s); mediana %.1f' % (-A('tot').max(), res[i]['k'], -np.median(A('tot'))))
i=A('wmarg').argmax(); print('(2) finestre: margine peggiore %.1f dB rispetto alla soglia (negativo = dentro) (%s); casi fuori: %d' % (A('wmarg').max(), res[i]['k'], (A('wmarg')>0).sum()))
i=A('dc').argmax(); print('(3) continua: scarto massimo %.1f (%s); casi oltre 100: %d' % (A('dc').max(), res[i]['k'], (A('dc')>100).sum()))
print('(4) saturazioni: %d; numero piu grande 2^%.2f' % (A('sat').sum(), np.log2(A('big').max())))
json.dump(res, open(os.path.join(OUT,'grid3_res.json'),'w'), default=float)
print('errore: finestra peggiore in unita (rms, sopra 20 Hz): max %.1f, mediana %.1f; un passo dei 16 bit di uscita = 64' % (A('ewmax').max(), np.median(A('ewmax'))))
