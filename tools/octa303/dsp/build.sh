#!/bin/bash
# OCTA303 vFable, the 303 voice on the DSP (code written by Claude): builds the reference kernel and the bench.
#   tools/octa303/dsp/build.sh            -> out/octa303/dsp/libo3k_dsp.so, out/octa303/dsp/o3host
# O3_DSP56300 = the built vendor/dsp56300 tree (default: this checkout's vendor/dsp56300; `make setup` builds it).
set -e
cd "$(dirname "$0")/../../.."
V="${O3_DSP56300:-$PWD/vendor/dsp56300}"
O=out/octa303/dsp; mkdir -p $O
gcc -O2 -ffp-contract=off -shared -fPIC -Itools/octa303/model_v7 -o $O/libo3k_dsp.so tools/octa303/dsp/ref/o3k.c -lm
LIBS=""
for l in dsp56kEmu/libdsp56kEmu.a dsp56kBase/libdsp56kBase.a asmjit/libasmjit.a vtuneSdk/libvtuneSdk.a; do   # as the vendored build made them
    [ -f "$V/build/source/$l" ] && LIBS="$LIBS $V/build/source/$l"
done
g++ -std=c++17 -O2 -I"$V/source" -I"$V/source/asmjit/src" tools/octa303/dsp/host/o3host.cpp -o $O/o3host $LIBS -lpthread -ldl
echo "built $O/libo3k_dsp.so and $O/o3host"
