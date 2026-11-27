#!/bin/bash
# Läuft beim Cloud-Bau IM fertigen Systemabbild: startet einen unsichtbaren Bildschirm (2560×1600, wie der Mac),
# darauf die Auriliux-Oberfläche, und macht Bildschirmfotos nach /aus.
set -u
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1
export QT_QUICK_BACKEND=software LANG=C.UTF-8 XDG_SESSION_TYPE=wayland
export QT_FORCE_STDERR_LOGGING=1 AURILIUX_DIAGNOSE=1
mkdir -p /tmp/leer && cp /etc/xdg/labwc/rc.xml /tmp/leer/
cat > /tmp/innen.sh <<'INNEN'
#!/bin/bash
{
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
ls -la "$XDG_RUNTIME_DIR"
wlr-randr --output HEADLESS-1 --custom-mode 2560x1600 --scale 2 || wlr-randr
swaybg -c '#202020' & sleep 1
} > /aus/innen.log 2>&1
auriliux-shell goldleiste > /aus/goldleiste.log 2>&1 & P=$!
sleep 6
kill -0 $P 2>/dev/null && echo "goldleiste läuft" >> /aus/innen.log || echo "goldleiste beendet" >> /aus/innen.log
grim /aus/1-goldleiste.png
kill $P; sleep 1
AURILIUX_VORSCHAU=menue auriliux-shell goldleiste > /aus/menue.log 2>&1 & P=$!
sleep 6; grim /aus/2-menue.png
kill $P; sleep 1
AURILIUX_VORSCHAU=suche auriliux-shell goldleiste > /aus/suche.log 2>&1 & P=$!
sleep 6; grim /aus/3-suche.png
kill $P; sleep 1
# Golddock: ein Programm (Terminal) läuft, damit Punkt/Balken sichtbar sind
foot >/dev/null 2>&1 & F=$!; sleep 2
AURILIUX_VORSCHAU=dock auriliux-shell golddock > /aus/dock.log 2>&1 & P=$!
sleep 6; grim /aus/4-dock.png
kill $P; sleep 1
AURILIUX_VORSCHAU=dockmenue auriliux-shell golddock > /aus/dockmenue.log 2>&1 & P=$!
sleep 6; grim /aus/5-dockmenue.png
kill $P $F; sleep 1
# Wabenfinder mit Beispielordnern (eigener Heimordner – /root ist im Abbild nur ein Verweis auf /var)
H=/tmp/heim; mkdir -p "$H/Dokumente/Rechnungen" "$H/Dokumente/Verträge" "$H/Bilder/Urlaub" "$H/Downloads" "$H/Projekte/System" "$H/Musik" "$H/Schreibtisch"
for i in 1 2 3 4 5 6 7 8; do echo test > "$H/Notiz $i.txt"; done
for i in $(seq 1 14); do echo x > "$H/Dokumente/Brief $i.txt"; done; echo x > "$H/Dokumente/Vertrag.pdf"
echo x > "$H/Bewerbung.pdf"; echo x > "$H/plan.md"
HOME=$H auriliux-shell wabenfinder "$H" > /aus/wabenfinder.log 2>&1 & P=$!
sleep 8; grim /aus/6-wabenfinder.png
kill $P; sleep 1
HOME=$H AURILIUX_VORSCHAU=ring auriliux-shell wabenfinder "$H" > /aus/ring.log 2>&1 & P=$!
sleep 9; grim /aus/7-ring.png
kill $P; sleep 1
# Schreibtisch mit Aufgaben-Leiste: Beispiel-Schreibtisch (deutscher Ordnername wie nach xdg-user-dirs-update)
mkdir -p "$H/.config" "$H/Schreibtisch/Projekte" "$H/Schreibtisch/Ideen"
printf 'XDG_DESKTOP_DIR="$HOME/Schreibtisch"\nXDG_DOCUMENTS_DIR="$HOME/Dokumente"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_PICTURES_DIR="$HOME/Bilder"\nXDG_MUSIC_DIR="$HOME/Musik"\n' > "$H/.config/user-dirs.dirs"
echo "Milch, Brot" > "$H/Schreibtisch/Einkaufsliste.txt"; echo x > "$H/Schreibtisch/Rechnung 2026-11.pdf"
cp /usr/share/icons/hicolor/256x256/apps/google-chrome.png "$H/Schreibtisch/Urlaub.png" 2>/dev/null || cp /aus/2-menue.png "$H/Schreibtisch/Urlaub.png"
cp /usr/share/applications/google-chrome.desktop "$H/Schreibtisch/Chrome.desktop" 2>/dev/null && chmod +x "$H/Schreibtisch/Chrome.desktop"
HOME=$H auriliux-shell goldleiste > /dev/null 2>&1 & L=$!
HOME=$H auriliux-shell schreibtisch > /aus/schreibtisch.log 2>&1 & P=$!
sleep 8; grim /aus/8-schreibtisch.png
kill $P; sleep 1
HOME=$H AURILIUX_VORSCHAU=aufgaben auriliux-shell schreibtisch > /aus/aufgaben.log 2>&1 & P=$!
sleep 8; grim /aus/9-aufgaben.png
kill $P; sleep 1
HOME=$H AURILIUX_VORSCHAU=geraete AURILIUX_GERAETE_DEMO=1 auriliux-shell schreibtisch > /aus/geraete.log 2>&1 & P=$!
sleep 8; grim /aus/10-geraete.png
kill $P $L; sleep 1
# Guardian + Herzschlag: beide Dienste einmal echt laufen lassen (Probelauf, mit harmlosen Beispiel-Meldungen)
/usr/libexec/auriliux/auriliux-guardian --einmal --beispiel > /aus/guardian-status.json 2> /aus/guardian.log
/usr/libexec/auriliux/auriliux-herzschlag --einmal > /aus/herzschlag-status.json 2> /aus/herzschlag.log
ls -la /run/auriliux/*/ >> /aus/guardian.log 2>&1
fallocate -l 140M "$H/Downloads/Film-Archiv.zip" 2>/dev/null || dd if=/dev/zero of="$H/Downloads/Film-Archiv.zip" bs=1M count=140 2>/dev/null
for t in uebersicht schutz ereignisse herzschlag; do
  HOME=$H AURILIUX_VORSCHAU=guardian auriliux-shell guardian $t > /aus/guardian-$t.log 2>&1 & P=$!
  sleep 9; grim /aus/guardian-$t.png
  kill $P; sleep 1
done
mv /aus/guardian-uebersicht.png /aus/11-guardian.png; mv /aus/guardian-schutz.png /aus/12-schutz.png
mv /aus/guardian-ereignisse.png /aus/13-ereignisse.png; mv /aus/guardian-herzschlag.png /aus/14-herzschlag.png
HOME=$H AURILIUX_VORSCHAU=karte auriliux-shell goldleiste > /aus/karte.log 2>&1 & P=$!
sleep 7; grim /aus/15-karte.png
kill $P; sleep 1
# Goldener Login (ohne greetd: Vorschau-Modus), einmal ruhig und einmal mit falschem Passwort
AURILIUX_VORSCHAU=anmeldung auriliux-shell anmeldung > /aus/anmeldung.log 2>&1 & P=$!
sleep 6; grim /aus/16-anmeldung.png
kill $P; sleep 1
AURILIUX_VORSCHAU=anmeldung-fehler auriliux-shell anmeldung > /aus/anmeldung-fehler.log 2>&1 & P=$!
sleep 3; grim /aus/17-anmeldung-fehler.png
kill $P
sh -n /usr/libexec/auriliux/anmeldung && sh -n /usr/libexec/auriliux/bildschirm-skalieren && sh -n /usr/libexec/auriliux/sperren && echo "Skripte ok" >> /aus/anmeldung.log
# Zentrale (Einstellungen): fünf Bereiche, ohne WLAN/Ton/Bluetooth-Dienste im Bau-Behälter → Beispielwerte
for t in bildschirm ton wlan energie updates ueber; do
  HOME=$H AURILIUX_VORSCHAU=zentrale auriliux-shell zentrale $t > /aus/zentrale-$t.log 2>&1 & P=$!
  sleep 6; grim /aus/zentrale-$t.png
  kill $P; sleep 1
done
n=21; for t in bildschirm ton wlan energie updates ueber; do mv /aus/zentrale-$t.png /aus/$n-zentrale-$t.png; n=$((n+1)); done
sh -n /usr/libexec/auriliux/update && echo "update-Skript ok" >> /aus/zentrale-ueber.log
# Charakter: Beispiel-Fähigkeiten (eine mit Bild = Auriliux-Logo), Übersicht, Baum, Baum mit Bearbeiten-Leiste
mkdir -p "$H/.local/share/auriliux"
B="data:image/png;base64,$(base64 -w0 /usr/share/auriliux/logo.png)"
k() { printf '{"id":"%s","name":"%s","symbol":"%s","bild":%s,"x":%s,"y":%s,"eltern":%s,"status":"%s","notiz":""}' "$@"; }
w() { k wurzel "$1" "$2" null 0 0 null gemeistert; }
{
printf '{"version":1,"werte":{"muskulatur":0,"bildung":0,"geld":0,"beziehung":0},"baeume":{'
printf '"muskulatur":{"knoten":[%s,%s,%s]},' "$(w Muskulatur 💪)" "$(k m1 Liegestütze 🏋️ null 0 -1 '"wurzel"' gemeistert)" "$(k m2 Laufen 🏃 null 1 0 '"wurzel"' arbeit)"
printf '"bildung":{"knoten":[%s,%s,%s,%s,%s,%s,%s,%s]},' "$(w Bildung 📚)" \
  "$(k b1 Programmieren 💻 null 0 -1 '"wurzel"' gemeistert)" "$(k b2 'Qt und QML' 🧩 null -1 -2 '"b1"' gemeistert)" \
  "$(k b3 Rust 🦀 null 1 -2 '"b1"' arbeit)" "$(k b4 Englisch 🗣️ null -1.5 0.5 '"wurzel"' arbeit)" \
  "$(k b5 'Auriliux OS' ⭐ "\"$B\"" 0 -3 '"b2"' gemeistert)" "$(k b6 Mathematik 🧠 null 1.5 0.5 '"wurzel"' offen)" \
  "$(k b7 Statistik 📈 null 2.5 1 '"b6"' offen)"
printf '"geld":{"knoten":[%s,%s]},' "$(w Geld 💰)" "$(k g1 Budget 🧾 null 0 -1 '"wurzel"' gemeistert)"
printf '"beziehung":{"knoten":[%s]}}}' "$(w Beziehung ❤️)"
} > "$H/.local/share/auriliux/charakter.json"
HOME=$H AURILIUX_VORSCHAU=charakter auriliux-shell charakter > /aus/charakter.log 2>&1 & P=$!
sleep 6; grim /aus/27-charakter.png; kill $P; sleep 1
HOME=$H AURILIUX_VORSCHAU=charakter auriliux-shell charakter bildung > /aus/charakter-baum.log 2>&1 & P=$!
sleep 6; grim /aus/28-charakter-baum.png; kill $P; sleep 1
HOME=$H AURILIUX_VORSCHAU=charakter-editor auriliux-shell charakter bildung > /aus/charakter-editor.log 2>&1 & P=$!
sleep 6; grim /aus/29-charakter-editor.png; kill $P; sleep 1
# Tresor (ohne Tresor-Dienst im Bau-Behälter → Beispielwerte; Vorschau-Code 12-34-56)
for t in tresor tresor-neu tresor-fehler tresor-offen tresor-versionen tresor-rettung; do
  HOME=$H AURILIUX_VORSCHAU=$t auriliux-shell tresor > /aus/$t.log 2>&1 & P=$!
  sleep 5; grim /aus/$t.png; kill $P; sleep 1
done
HOME=$H AURILIUX_VORSCHAU=tresor-oeffnet auriliux-shell tresor > /aus/tresor-oeffnet.log 2>&1 & P=$!
sleep 3; grim /aus/tresor-oeffnet-1.png; sleep 1.6; grim /aus/tresor-oeffnet-2.png; kill $P; sleep 1
n=30; for t in tresor tresor-neu tresor-fehler tresor-oeffnet-1 tresor-oeffnet-2 tresor-offen tresor-versionen tresor-rettung; do mv /aus/$t.png /aus/$n-$t.png; n=$((n+1)); done
/usr/libexec/auriliux/auriliux-tresor --einmal > /aus/tresor-status.json 2> /aus/tresor-dienst.log
# ── James: Fenster + Dienst gegen die Attrappe des Servers (läuft auf dem Bau-Rechner, 127.0.0.1:8766) ──
J=/tmp/jheim; mkdir -p "$J/.config/auriliux" "$J/.local/bin"
HOME=$J auriliux-shell james > /aus/james-einrichten.log 2>&1 & P=$!
sleep 6; grim /aus/40-james-einrichten.png; kill $P; sleep 1
printf '{"server":"http://127.0.0.1:8766/jamesgehirn/","token":"%s"}\n' "${JAMES_PROBE_TOKEN:-}" > "$J/.config/auriliux/james.json"
chmod 600 "$J/.config/auriliux/james.json"; echo an > "$J/.config/auriliux/ki-schalter"
# Probe-„Claude Code“: liest nur und meldet sich (das echte wird später einmalig installiert)
printf '#!/bin/sh\necho "Probe-Claude im Ordner $(pwd): Auftrag gelesen."\necho "Zusammenfassung: nichts verändert."\n' > "$J/.local/bin/claude"
chmod +x "$J/.local/bin/claude"
HOME=$J AURILIUX_VORSCHAU=james auriliux-shell james-dienst > /aus/james-dienst.log 2>&1 & D=$!
sleep 5; grim /aus/41-james-hinweis.png
HOME=$J AURILIUX_VORSCHAU=james-senden auriliux-shell james > /aus/james.log 2>&1 & P=$!
sleep 6; grim /aus/42-james-schreibt.png
sleep 14; grim /aus/43-james.png
HOME=$J auriliux-shell james >> /aus/james.log 2>&1; echo "zweiter Start: Code $?" >> /aus/james.log
kill $P; sleep 1
HOME=$J AURILIUX_VORSCHAU=james-auftraege auriliux-shell james > /aus/james-auftraege.log 2>&1 & P=$!
sleep 7; grim /aus/44-james-auftraege.png; kill $P; sleep 1
# Stimme ohne Mikrofon: Super+J (kein Mikrofon im Bau → Hinweis), dann eine Probe-Aufnahme direkt an den Dienst
HOME=$J auriliux-shell james-befehl hoeren > /aus/james-befehl.log 2>&1; echo "hoeren: Code $?" >> /aus/james-befehl.log
sleep 1.5; grim /aus/45-james-hoert.png
HOME=$J auriliux-shell james-befehl probe >> /aus/james-befehl.log 2>&1
sleep 1; grim /aus/46-james-denkt.png
sleep 6; grim /aus/47-james-spricht.png
sleep 24; grim /aus/48-james-danach.png
HOME=$J auriliux-shell james-befehl status >> /aus/james-befehl.log 2>&1
kill $D; sleep 1
{ cat "$J/.local/state/auriliux/james.log"; ls -la "$J/.config/auriliux/" "$J/Projekte/Probe" 2>&1; } > /aus/james-protokoll.log 2>&1
# Boot-Intro: Thema, Einstellungen, initramfs (Bilder zum Ansehen in /aus)
{
  T=/usr/share/plymouth/themes/auriliux
  ls $T | wc -l; cat $T/dauer; echo; cat /etc/plymouth/plymouthd.conf; cat /usr/lib/bootc/kargs.d/10-auriliux.toml
  grep -c "global.folge" $T/auriliux.script
  k=$(ls /usr/lib/modules | head -1); ls -la /usr/lib/modules/$k/initramfs.img
  lsinitrd /usr/lib/modules/$k/initramfs.img | grep -c "themes/auriliux"
  sh -n /usr/libexec/auriliux/intro-abwarten && echo "intro-abwarten ok"
} > /aus/boot-intro.log 2>&1
n=0; for f in $(grep -o "global.folge\[[0-9]*\] = [0-9]*" /usr/share/plymouth/themes/auriliux/auriliux.script | awk 'NR % 25 == 1 { print $3 }'); do
  cp /usr/share/plymouth/themes/auriliux/intro-$f.png /aus/boot-intro-$n.png 2>/dev/null; n=$((n+1)); done
# Sperrwache kurz laufen lassen (ohne logind im Bau-Behälter: darf nur melden, nicht abstürzen)
auriliux-shell sperrwache > /aus/sperrwache.log 2>&1 & P=$!
sleep 3; kill -0 $P 2>/dev/null && echo "sperrwache läuft" >> /aus/sperrwache.log || echo "sperrwache beendet" >> /aus/sperrwache.log
kill $P 2>/dev/null; sleep 1
# Echte Bildschirmsperre: Wegwerf-Passwort nur in diesem Bau-Behälter; die Sperre tippt erst ein falsches,
# dann dieses Passwort ein (geprüft über PAM) und muss sich danach selbst entsperren und beenden
echo 'root:probe-7Gq2x' | chpasswd >> /aus/sperre.log 2>&1
AURILIUX_VORSCHAU=sperre-probe AURILIUX_PROBE_PASSWORT='probe-7Gq2x' auriliux-shell sperre >> /aus/sperre.log 2>&1 & P=$!
sleep 2.5; grim /aus/18-sperre.png 2>> /aus/sperre.log
sleep 3.2; grim /aus/19-sperre-fehler.png 2>> /aus/sperre.log
for i in $(seq 1 16); do kill -0 $P 2>/dev/null || break; sleep 0.5; done
if kill -0 $P 2>/dev/null; then echo "FEHLER: Sperre läuft noch (nicht entsperrt)" >> /aus/sperre.log; kill $P
else wait $P; echo "Sperre beendet mit Code $?" >> /aus/sperre.log; fi
sleep 1; grim /aus/20-entsperrt.png 2>> /aus/sperre.log
labwc --exit
INNEN
chmod +x /tmp/innen.sh
timeout 660 labwc -C /tmp/leer -s /tmp/innen.sh > /aus/labwc.log 2>&1
ls -la /aus
