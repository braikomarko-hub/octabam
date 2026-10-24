#!/bin/bash
# menu_v0.sh -- il MENU DELLA TRACCIA v0 (solo navigazione) nell'emulatore.
# Lavora in ~/octabam_menu (cartella nuova). ~/octabam, ~/octabam_new e ~/octabam_morph NON vengono toccati,
# e l'immagine ACIDV77 in ~/Desktop/acidtrack resta dov'e'.
#   1) prende il ramo `trackmenu` dal tuo GitHub
#   2) il test del menu nel simulatore (52 controlli)
#   3) make check REMIX=trackmenu (il remix di prova: menu + MORPH + STORE + effetti stock)
#   4) le FOTO dello schermo dall'emulatore: tieni premuto T5, pagine, manopole, chiusura
#   5) l'immagine di prova TMENU1 (BUILD 99) -- da NON flashare prima che Claude abbia letto i log
# Risultati in ~/Desktop/menu/   Stato: ~/Desktop/new_0_stato.txt   (~30-60 minuti)
set -u
D="$HOME/Desktop/menu"; STATUS="$HOME/Desktop/new_0_stato.txt"
NEW="$HOME/octabam_new"; M="$HOME/octabam_menu"
mkdir -p "$D"; rm -f "$D"/OCTATRACK_*.bin
st() { echo "$(date +%H:%M) $1" >> "$STATUS"; echo "== $1"; }
fail() { echo "!! $1"; echo "$(date +%H:%M) MENU v0 FERMO: $1" >> "$STATUS"; exit 1; }

st "MENU v0 1) prendo il ramo trackmenu in ~/octabam_menu"
if [ ! -d "$M/.git" ]; then
  git clone -q --reference "$NEW" https://github.com/braikomarko-hub/octabam "$M" > "$D/1_clone.log" 2>&1 \
    || fail "il download non e' riuscito (1_clone.log)"
fi
cd "$M" || exit 1
git checkout -q -- . 2>/dev/null
git fetch -q origin "+refs/heads/trackmenu:refs/remotes/origin/trackmenu" \
  && git checkout -q -B trackmenu origin/trackmenu && git reset -q --hard origin/trackmenu || fail "git"
git submodule update --init -q >> "$D/1_clone.log" 2>&1
mkdir -p downloads/extracted out/raw
cp "$NEW/downloads/extracted/OCTATRACK_OS1.40C.syx" downloads/extracted/ || fail "manca il file dell'OS in ~/octabam_new"
cp "$NEW"/out/raw/* out/raw/
[ -e .venv ] || ln -s "$HOME/octabam/.venv" .venv
[ -e vendor ] || ln -s "$NEW/vendor" vendor
echo "   versione: $(git log -1 --format='%h %s')" | tee "$D/versione.txt"
make emu-cf > "$D/1_emu.log" 2>&1 || fail "l'emulatore non si costruisce (1_emu.log)"

st "MENU v0 2) il test del menu nel simulatore"
python3 tools/trackmenu/test_trackmenu.py > "$D/2_test.log" 2>&1; echo "   uscita $?  $(tail -1 "$D/2_test.log")"

st "MENU v0 3) make check REMIX=trackmenu"
PROJ="${OT_PROJECT:-$(cat "$HOME/.octabam_project" 2>/dev/null)}"
make docs > /dev/null 2>&1
OT_PROJECT="$PROJ" make check REMIX=trackmenu > "$D/3_check.log" 2>&1; echo "   uscita $?"; tail -2 "$D/3_check.log"

st "MENU v0 4) le foto dello schermo nell'emulatore"
rm -rf "$D/foto"; mkdir -p "$D/foto"
OT_PROJECT="$PROJ" .venv/bin/python3 tools/emu/live_shots.py trackmenu --script tools/trackmenu/menu.script \
  --output-dir "$D/foto" > "$D/4_foto.log" 2>&1; echo "   uscita $?"
cp out/live/port.txt "$D/4_port.txt" 2>/dev/null
ls "$D/foto/trackmenu" 2>/dev/null | head -20

st "MENU v0 5) immagine di prova TMENU1 (BUILD 99)"
make image REMIX=trackmenu BUILD=99 VERSION=TMENU1 > "$D/5_image.log" 2>&1; echo "   uscita $?"
cp out/OCTATRACK_TMENU1.bin "$D/" 2>/dev/null || echo "!! immagine non fatta (5_image.log)"
ls -la "$D"/*.bin 2>/dev/null
st "MENU v0 FINITO: Claude legge ~/Desktop/menu (NON flashare prima che Claude abbia letto i log)"
