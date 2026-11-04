import sys; sys.path.insert(0, '/root/fit'); import ds2, eval75, hyb, tab
for nm in sys.argv[1:]:
    if nm == 'v7.3': t = tab.build(None)
    else:
        p, _ = eval75.p_json({'v7.6': '/root/fit/fit_H8_pack.json', 'v7.5': '/root/fit/fit_H2_all.json'}[nm]); t = hyb.build(p)
    r = ds2.evaluate(t, weights=(1.0, 4.0, 1.0))
    print('%s  cell %.3f  cell40 %.3f  bright %.3f  acc %.3f  gain %.2f' % (nm, r['cell'], r['cell40'], r['bright'], r['acc_pk'], r['gain'])); sys.stdout.flush()
