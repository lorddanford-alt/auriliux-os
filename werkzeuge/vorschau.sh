#!/bin/bash
# Läuft beim Cloud-Bau IM fertigen Systemabbild: startet einen unsichtbaren Bildschirm (2560×1600, wie der Mac),
# darauf die Auriliux-Oberfläche, und macht Bildschirmfotos nach /aus.
set -u
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1
export QT_QUICK_BACKEND=software LANG=de_DE.UTF-8 XDG_SESSION_TYPE=wayland
export QT_LOGGING_RULES="qt.qpa.wayland*=true" QT_FORCE_STDERR_LOGGING=1 AURILIUX_DIAGNOSE=1
mkdir -p /tmp/leer
cat > /tmp/innen.sh <<'INNEN'
#!/bin/bash
{
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
ls -la "$XDG_RUNTIME_DIR"
wlr-randr --output HEADLESS-1 --custom-mode 2560x1600 --scale 2 || wlr-randr
swaybg -c '#202020' & sleep 1
} > /aus/innen.log 2>&1
WAYLAND_DEBUG=client auriliux-shell goldleiste > /aus/goldleiste.log 2>&1 & P=$!
sleep 6
kill -0 $P 2>/dev/null && echo "goldleiste läuft" >> /aus/innen.log || echo "goldleiste beendet" >> /aus/innen.log
grim /aus/1-goldleiste.png
kill $P; sleep 1
AURILIUX_VORSCHAU=menue auriliux-shell goldleiste > /aus/menue.log 2>&1 & P=$!
sleep 6; grim /aus/2-menue.png
kill $P
labwc --exit
INNEN
chmod +x /tmp/innen.sh
timeout 90 labwc -C /tmp/leer -s /tmp/innen.sh > /aus/labwc.log 2>&1
ls -la /aus
