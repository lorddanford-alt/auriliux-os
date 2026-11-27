#!/bin/bash
# Prüft auf dem Mac (macOS), ob alles für die Installation von Auriliux OS bereit ist.
# Ändert NICHTS – liest nur. Aufruf im Terminal:  bash mac-pruefen.sh
set -u
gruen=$'\033[32m'; rot=$'\033[31m'; gelb=$'\033[33m'; aus=$'\033[0m'
ok()   { echo "  ${gruen}✓${aus} $*"; }
warn() { echo "  ${gelb}!${aus} $*"; }
nein() { echo "  ${rot}✗${aus} $*"; }

echo "Auriliux OS – Prüfung vor der Installation (nur lesen)"
echo

echo "Rechner"
modell=$(sysctl -n hw.model 2>/dev/null)
[ "$modell" = "MacBookPro12,1" ] && ok "Modell $modell" || warn "Modell $modell (Auriliux ist für MacBookPro12,1 gebaut)"
ok "macOS $(sw_vers -productVersion 2>/dev/null)"

echo
echo "OpenCore (Startauswahl)"
oc=$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | awk '{print $2}')
if [ -n "$oc" ]; then ok "OpenCore aktiv ($oc)"; else warn "keine OpenCore-Version im NVRAM gefunden – Start nur über ⌥-Taste prüfen"; fi

echo
echo "Interne SSD"
intern=$(diskutil list internal physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1; exit}')
if [ -z "$intern" ]; then nein "keine interne Platte gefunden"; else
    groesse=$(diskutil info "$intern" | awk -F': *' '/Disk Size/ {print $2; exit}')
    ok "$intern – ${groesse%%(*}"
    diskutil list "$intern" | sed -n '3,20p' | sed 's/^/      /'
    frei_unpartitioniert=$(diskutil list "$intern" | awk '/\(free space\)/ {print $0}')
    [ -n "$frei_unpartitioniert" ] && ok "Freier, unbelegter Bereich vorhanden: $(echo "$frei_unpartitioniert" | sed 's/  */ /g')" \
        || warn "Noch kein freier Bereich für Auriliux – macOS muss erst verkleinert werden (Anleitung Schritt 3)"
fi
container=$(diskutil apfs list 2>/dev/null | awk '/Container Reference:/ {print $NF; exit}')
if [ -n "$container" ]; then
    diskutil apfs list "$container" | awk -F': *' '/Size \(Capacity Ceiling\)|Capacity In Use By Volumes|Capacity Not Allocated/ {gsub(/^ *\+?-* */,"",$1); print "      " $1 ": " $2}'
fi
fv=$(fdesetup status 2>/dev/null)
case "$fv" in *On*) ok "FileVault an (bleibt an – macOS ist weiter verschlüsselt)";; *) warn "FileVault: $fv";; esac

echo
echo "USB-Sticks"
usb=$(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1}')
if [ -z "$usb" ]; then warn "kein USB-Stick eingesteckt (für den Installer: mindestens 16 GB, Markenstick)"; else
    for d in $usb; do
        name=$(diskutil info "$d" | awk -F': *' '/Media Name/ {print $2; exit}')
        bytes=$(diskutil info "$d" | awk -F'[(]' '/Disk Size/ {print $2; exit}' | awk '{print $1}')
        if [ "${bytes:-0}" -gt 300000000000 ] 2>/dev/null; then echo "      $d – $name ($(( bytes / 1000000000 )) GB): Festplatte, kein Stick – wird nicht angefasst"
        elif [ "${bytes:-0}" -ge 15000000000 ] 2>/dev/null; then ok "$d – $name ($(( bytes / 1000000000 )) GB) – passt für den Installer"
        elif [ "${bytes:-0}" -eq 0 ] 2>/dev/null; then nein "$d – $name meldet 0 Byte (defekt oder Fälschung)"
        else warn "$d – $name ($(( ${bytes:-0} / 1000000000 )) GB) – zu klein, mindestens 16 GB"; fi
    done
fi

echo
echo "Sicherung"
if [ -d /Volumes/AURILIUX ]; then
    frei=$(df -g /Volumes/AURILIUX | awk 'NR==2 {print $4}')
    ok "AURILIUX angeschlossen (${frei} GB frei)"
else warn "AURILIUX nicht angeschlossen – vor der Installation eine Sicherung machen"; fi

echo
echo "Akku"
pmset -g batt | sed -n '2p' | sed 's/^/      /'
echo
echo "Fertig. Es wurde nichts verändert."
