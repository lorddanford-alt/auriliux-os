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
cp /aus/1-goldleiste.png "$H/Schreibtisch/Bildschirmfoto.png"
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
kill $P $L
labwc --exit
INNEN
chmod +x /tmp/innen.sh
timeout 160 labwc -C /tmp/leer -s /tmp/innen.sh > /aus/labwc.log 2>&1
ls -la /aus
