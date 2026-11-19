"""Phase 3: the assembled voice on the emulator against the reference o3d_sample, sample by sample (written by Claude)."""
import sys, os, subprocess, ctypes, numpy as np
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE,'..','ref'))
from grid import *
WORK=os.environ.get('O3_WORK') or OUT; os.makedirs(WORK,exist_ok=True)   # O3_WORK: a run's own files (two runs at once)
DA=os.environ.get('O3_DSP_ASM') or os.path.join(os.environ.get('O3_DSP56300', os.path.join(ROOT,'vendor','dsp56300')),'build','source','dsp_host','dsp_asm')
HOST=os.path.join(OUT,'o3host')
AB=0x5000                          # the bench's audio block (o3host AUDIO); the unit's is X:0
G=8387936; KN=97; PTP=0x1800; ORG=0x1000; CV=4260619; VOL=0x400000      # the AMP VOL word of the tests: 64
DRV=0x100000      # DRIV's word of the tests: 0x100000 = DRIV 0 (the knees and the tables: grid.py, gen_module.drv)
def drvw(r,nf):   # DRIV's word for nf frames: a third at DRIV 0, the rest G = 4097..12953 (Q12) << 8, held as the rest is
    g=r.integers(4097,12954,nf)*256; g[r.random(nf)<0.33]=0x100000; return g
HW0=4095<<3      # halfword 11 with MUFF, FM, SWP neutral (B2: FM's ceiling field at its largest)
def ref(e):
    n=e['nsamp']; C=np.zeros((n//16+1,9),np.int32); X=np.zeros(n,np.int32); H=np.zeros((n//16+1,2),np.int32); L.o3_set_dvol(VOL); L.o3_set_ddrv(DRV)
    L.o3_set_dtrace(C.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)), X.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)))
    L.o3_set_dtrace2(H.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)))
    L.o3_set_dref(1,(ctypes.c_int*5)(24,24,24,24,24),0)
    y=m.render_engine(e,M); rc=L.o3_last_rc(); L.o3_set_dref(0,None,0); L.o3_set_dtrace(None,None); L.o3_set_dtrace2(None); L.o3_set_dvol(0); assert rc==0
    return y,wide(C[:n//16],H[:n//16]),X
def wide(C,H,vol=None,drv=None):
    """the reference's trace (g1..g4 kq dq gt gv gh) and its halfword 11 / FM depth -> the 13 numbers of a frame
    (g1..g4 kq dq gt gv gh vol drv hw fm, o3k.c o3d_run)"""
    W=np.zeros((len(C),13),np.int32); W[:,:9]=C[:,:9]; W[:,9]=VOL if vol is None else vol; W[:,10]=DRV if drv is None else drv
    W[:,11:13]=H; return W
def send(p):                      # a 15-bit payload through the gain ahead of FX1
    assert 0<=p<32768; return (((p<<8)|0x80)*G+(1<<22))>>23
def build(gh):
    src=gen_module.subst(open(HERE+'/o3v.asm.in').read(),pt=str(PTP),ab=str(AB),gh=gh)
    open(WORK+'/o3v.asm','w').write(src)
    r=subprocess.run([DA,'-in',WORK+'/o3v.asm','-org','%x'%ORG,'-out',WORK+'/o3v.bin','-list'],capture_output=True,text=True)
    open(WORK+'/o3v.lst','w').write(r.stdout+r.stderr)
    assert 'assembled' in r.stdout, (r.stdout+r.stderr)[-800:]
    lines=[l for l in r.stdout.splitlines() if l[:6].strip() and l[6:7]==':']
    lab={}
    for l in open(WORK+'/o3v.sym') if os.path.exists(WORK+'/o3v.sym') else []: k,v=l.split(); lab[k]=int(v,16)
    return r.stdout, lab
def frames(C,X,mark=0x7fff):
    """C: frames of 13 numbers (wide()); the halfword 11 into the record, FM's depth into payload 14's bits 8..14"""
    n=len(C); F=np.zeros((n,52),np.int32)
    for f in range(n):
        g1,g2,g3,g4,kq,dq,gt,gv,gh,vol,drv,hw,fm=[int(v) for v in C[f][:13]]
        pay=[mark]
        for c in (g1,g2,g3,g4,kq,dq,gt): assert 0<=c<(1<<23); pay+=[c>>8,c&0xff]
        assert 0<=fm<128 and 0<=hw<32768; pay[14]|=fm<<8
        pay.append(sum(pay[1:])&0x7fff)
        assert gv%2==0 and gv<(1<<16)
        F[f,0:32:2]=X[16*f:16*f+16]; F[f,1:32:2]=[send(p) for p in pay]; F[f,32]=(gv>>1)<<8; F[f,33]=0x3a5c00; F[f,34]=0x651700; F[f,35]=vol; F[f,36]=drv; F[f,37]=hw<<8
    return F
def run_host(F,proc,init):
    kp=np.concatenate([m.KPOS,[m.KPOS[-1]],m.KNEG,[m.KNEG[-1]],DTP,DTN,gen_module.mode_consts()]).astype(np.int32); kp.tofile(WORK+'/ytab.bin')
    F.astype(np.int32).tofile(WORK+'/in.bin')
    r=subprocess.run([HOST,WORK+'/o3v.bin','%x'%ORG,'%x'%init,'%x'%proc,WORK+'/ytab.bin','p%x'%PTP,WORK+'/in.bin',WORK+'/out.bin'],capture_output=True,text=True)
    assert r.returncode==0, r.stdout+r.stderr
    o=np.fromfile(WORK+'/out.bin',np.int32).reshape(-1,33)
    return o[:,:32], o[:,32], r.stdout.strip()
DC=[]
def stress(seed, nf=4000, loud=True):
    """random coefficients and (loud) full-scale L samples: the limiting moves and the table's end are exercised"""
    r=np.random.default_rng(seed); gh=GH
    C=np.zeros((nf,13),np.int32); C[:,9]=r.integers(0,0x7fff,nf)*256
    C[:,11]=HW0|(r.integers(0,3,nf)<<1)                # B2: MUFF's mode at random
    C[:,0:4]=r.integers(1,int(0.98*2**23),(nf,4)); C[:,4]=r.integers(0,120*65536,nf); C[:,5]=r.integers(1,2**23,nf)
    C[:,6]=r.integers(0,2**23,nf); C[:,7]=r.integers(0,2**15,nf)*2; C[:,8]=gh
    C[:,10]=drvw(r,nf)
    hold=r.integers(1,40,nf); k=0                       # coefficients held for a few frames at a time
    for f in range(1,nf):
        if k>0: C[f]=C[f-1]; k-=1
        else: k=int(hold[f])
    X=r.integers(-2**23,2**23,16*nf).astype(np.int32) if loud else r.integers(-2**21,2**21,16*nf).astype(np.int32)
    y=np.zeros(16*nf,np.int32); ip=lambda a:a.ctypes.data_as(ctypes.POINTER(ctypes.c_int32))
    L.o3d_run.restype=ctypes.c_longlong
    sat=L.o3d_run(ip(np.ascontiguousarray(C)),ip(X),nf,ip(y),ip(m.KNEG),ip(m.KPOS))
    out,ni,msg=run_host(frames(C,X),PROC,ORG)
    yl=out[:,0::2].reshape(-1)
    L.o3d_get_dcnt.restype=ctypes.c_longlong; DC.append([int(L.o3d_get_dcnt(k)) for k in range(3)])
    return int((yl!=y).sum()), 16*nf, int(sat), int(abs(y).max())
if __name__=='__main__':
    CASES=[(0,0,127,0),(0,127,127,1),(127,0,127,1),(127,127,127,0),(64,64,64,0),(40,100,64,1),(90,127,0,0),(20,64,127,1),(0,0,127,1),(127,127,127,1),(64,127,64,1),(127,100,0,0)]
    tot=0; totd=0; built=None
    for c in CASES:
        e=ev(*c); y,C,X=ref(e)
        if built is None:
            lst,lab=build(int(C[0][8])); built=1
            sym=dict(l.split() for l in open(WORK+'/o3v.sym')) if os.path.exists(WORK+'/o3v.sym') else {}
            print('simboli',sym); print(lst.splitlines()[-1])
            ls=[l for l in lst.splitlines() if l[6:7]==':']; k=[i for i,l in enumerate(ls) if ' rts' in l][0]
            init=ORG; proc=int(ls[k+1][:6],16); print('init %x proc %x'%(init,proc)); globals()['PROC']=proc; globals()['GH']=int(C[0][8])
        out,ni,msg=run_host(frames(C,X),proc,init)
        yl=out[:,0::2].reshape(-1); yr=out[:,1::2].reshape(-1); n=len(yl)
        d=int((yl!=y[:n]).sum()); d2=int((yr!=yl).sum()); tot+=n; totd+=d
        first=int(np.argmax(yl!=y[:n])) if d else -1
        print(c,'campioni',n,'diversi',d,'(primo %d: dsp %d modello %d)'%(first,yl[first],y[first]) if d else '','R!=L',d2,'| istruzioni a frame max',int(ni.max()),'=> a campione %.1f'%((ni.max())/16))
    print('TOTALE: %d campioni, %d diversi'%(tot,totd))
    FAIL=[totd]
    for seed,loud in ((1,True),(2,True),(3,False),(4,False)):
        d,n,sat,pk=stress(seed,loud=loud)
        print('prova dura %d (%s): campioni %d, diversi %d, saturazioni nel modello %d, picco %d'%(seed,'ingresso a fondo scala' if loud else 'ingresso normale, coefficienti a caso',n,d,sat,pk))
        FAIL.append(d)
        print('   DRIV in questa prova: campioni passati dallo stadio %d, sopra il ginocchio + %d, sopra il ginocchio - %d'%tuple(DC[-1])); FAIL.append(0 if min(DC[-1])>100 else 1)
    # frame non validi: segno giusto ma somma sbagliata; segno sbagliato; destro a fondo scala
    e=ev(64,127,64,1); y,C,X=ref(e); F=frames(C,X)
    F2=F.copy(); F2[200,3]=send(0x1234); F2[201,1]=send(0x7ffe); F2[202,1:32:2]=0x7fffff
    o,_,_=run_host(F2,PROC,ORG)
    print('frame non validi 200,201,202 in silenzio:',bool((o[200:203]==0).all()),'| frame 199 calcolato:',bool((o[199]!=0).any()))
    F3=F.copy(); F3[300,4]=send(0x0100|int(C[300][0]&0xff)); F3[300,31]=send((sum(int(v) for v in [C[300][k]>>8 for k in range(7)])+sum(int(C[300][k]&0xff) for k in range(7))+0x100)&0x7fff)
    o3,_,_=run_host(F3,PROC,ORG)
    print('byte basso sporco (somma giusta) rifiutato:',bool((o3[300]==0).all()),'| ripartenza dopo il silenzio: primo campione del frame 203 =',int(o[203,0]),', del frame 204 =',int(o[204,0]),'(senza interruzione:',int(y[203*16]),int(y[204*16]),')')
    F5=F.copy(); F5[400:410,33]=0x3a0000; F5[410:420,34]=0x650000; o5,_,_=run_host(F5,PROC,ORG)
    print('senza la firma del motore (traccia non OCTA-303): 20 frame lasciati intatti:',bool((o5[400:420]==F5[400:420,:32]).all()),'| frame 399 calcolato:',bool((o5[399]!=F5[399,:32]).any()))
    F4=F.copy(); F4[:,32]|=0x7f; o4,_,_=run_host(F4,PROC,ORG)
    print('byte basso della parola del foglietto sporco: campioni diversi',int((o4[:,0::2].reshape(-1)!=y[:o4.shape[0]*16]).sum()))
    # DRIV's law on the DSP against the ColdFire's own stage (tools/octa303/o3out.py, bit for bit the engine's o3_out): not
    # the same bits (24 points a side here, 257 there), the same curve.  Threshold, written before the run: the largest
    # difference over y = -2^21..2^21 and every DRIV at most 600 (in y's units; the + ceiling is 861584).
    sys.path.insert(0, os.path.join(ROOT,'tools','octa303')); import o3out
    L.o3d_drv_only.restype=ctypes.c_int32; worst=(0,0,0)
    for raw in range(1,128):
        Gq=o3out.driv_gain(raw)
        for yv in range(-(1<<21),(1<<21)+1,4099):
            x=((yv>>6)*Gq)>>6                              # the ColdFire's x = G y
            cf=o3out._drvsat(x,o3out.C['DRV_KP'],o3out.C['DRV_RP'],o3out.C['DRV_WP'],o3out.C['DRV_DP4']) if x>=0 else -o3out._drvsat(-x,o3out.C['DRV_KN'],o3out.C['DRV_RN'],o3out.C['DRV_WN'],o3out.C['DRV_DN4'])
            ds=int(L.o3d_drv_only(yv,Gq<<8))
            if abs(ds-cf)>worst[0]: worst=(abs(ds-cf),raw,yv)
    print('legge di DRIV sul DSP contro lo stadio del ColdFire: scarto massimo %d (DRIV %d, y %d); soglia 600'%worst); FAIL.append(0 if worst[0]<=600 else 1)
    ok=not any(FAIL) and bool((o[200:203]==0).all()) and bool((o3[300]==0).all()) and bool((o5[400:420]==F5[400:420,:32]).all()) and int((o4[:,0::2].reshape(-1)!=y[:o4.shape[0]*16]).sum())==0
    # ---- the frame in pieces (SONDA 4): the dispatcher calls the insert once a piece.  Any cut k = 1..15, a cut that changes
    #      every frame, refused frames among them, an unsigned stretch: the output must be the whole call's, word for word,
    #      and nothing may be written outside the block's 32 words.
    import re as _re
    def outside(msg): return int(_re.search(r'outside the audio block (\d+)', msg).group(1))
    r=np.random.default_rng(11); nf=1500
    C=np.zeros((nf,13),np.int32); C[:,9]=r.integers(0,0x7fff,nf)*256; C[:,11]=HW0|(r.integers(0,3,nf)<<1)
    C[:,0:4]=r.integers(1,int(0.98*2**23),(nf,4)); C[:,4]=r.integers(0,120*65536,nf); C[:,5]=r.integers(1,2**23,nf)
    C[:,6]=r.integers(0,2**23,nf); C[:,7]=r.integers(0,2**15,nf)*2; C[:,8]=GH
    C[:,10]=drvw(r,nf)
    for f in range(1,nf):
        if f%7: C[f]=C[f-1]
    X=r.integers(-2**22,2**22,16*nf).astype(np.int32)
    F0=frames(C,X)
    for f in r.integers(20,nf-20,60): F0[f,1]=send(0x1234)            # a refused frame (the mark)
    for f in r.integers(20,nf-20,30): F0[f,31]^=0x4000                 # a refused frame (the sum)
    F0[700:760,33]=0                                                   # sixty frames without the signature
    whole,_,msg0=run_host(F0,proc,init); ow=outside(msg0)
    pz_bad=0; pz_out=ow; rows=[]
    for k in list(range(1,16))+['a caso']:
        F=F0.copy()
        F[:,51]=k if k!='a caso' else r.integers(0,16,nf)
        o,ni,msg=run_host(F,proc,init)
        d=int((o!=whole).any(axis=1).sum()); pz_bad+=d; pz_out+=outside(msg); rows.append((k,d,outside(msg),int(ni.max())))
    print('frame in pezzi: taglio, frame diversi dalla chiamata intera, frame con scritture fuori dal blocco, istruzioni a frame max')
    print('   '+'  '.join('%s:%d/%d/%d'%r_ for r_ in rows))
    print('frame in pezzi: %d frame per taglio; rifiutati fra questi: %d; diversi in tutto %d; scritture fuori dal blocco in tutto %d (chiamata intera: %d)'%(nf,int((whole[:,0::2]==0).all(axis=1).sum()),pz_bad,pz_out,ow))
    FAIL.append(pz_bad); FAIL.append(pz_out)
    # the two pieces of a frame have each their own record (r6): when the signatures disagree nothing of the engine's may
    # go out.  Frame 300: the second piece's record has no signature -> the first piece as ever, the second silent.
    # Frame 900: only the second piece's record has it -> the first piece untouched, the second silent.
    dis = 0
    for k in (1, 5, 8, 13, 15):
        F = F0.copy(); F[:, 51] = k; F[300, 50] = 1; F[900, 33] = 0; F[900, 34] = 0; F[900, 50] = 2
        o, ni, msg = run_host(F, proc, init)
        a_ = bool((o[300, :2 * k] == whole[300, :2 * k]).all()) and bool((o[300, 2 * k:] == 0).all()) and bool(whole[300].any())
        b_ = bool((o[900, :2 * k] == F[900, :2 * k]).all()) and bool((o[900, 2 * k:] == 0).all())
        c_ = bool((o[:300] == whole[:300]).all()) and outside(msg) == 0
        dis += (not a_) + (not b_) + (not c_)
    print('firme diverse fra i due pezzi (5 tagli): casi sbagliati %d' % dis)
    FAIL.append(dis)
    ok = ok and not any(FAIL)
    print('ESITO prova3:', 'PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
