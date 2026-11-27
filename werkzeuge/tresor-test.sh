#!/bin/bash
# Prüft beim Cloud-Bau den heikelsten Teil des Tresors an einer echten (kleinen) btrfs-Platte:
# Benutzerordner in einen btrfs-Teilbereich umwandeln, Schnappschuss aufnehmen, nichts geht verloren.
set -eu
B="$1"                                   # Pfad zu auriliux-tresor
W=$(mktemp -d)
truncate -s 400M "$W.img"
mkfs.btrfs -q "$W.img"
mount -o loop "$W.img" "$W"
trap 'umount "$W" 2>/dev/null; rm -f "$W.img"' EXIT
mkdir -p "$W/var/home/nutzer/Dokumente/Briefe" "$W/var/home/nutzer/.config"
echo "Hallo Tresor" > "$W/var/home/nutzer/Dokumente/Briefe/brief.txt"
head -c 3000000 /dev/urandom > "$W/var/home/nutzer/Dokumente/gross.bin"
ln -s Dokumente/Briefe "$W/var/home/nutzer/verknuepfung"
chown -R 1000:1000 "$W/var/home/nutzer"; chmod 700 "$W/var/home/nutzer"
vorher=$(cd "$W/var/home" && find . | sort | md5sum)
export AURILIUX_TRESOR_WURZEL="$W"

echo "── Umwandeln"
"$B" --vorbereiten
test "$(stat -c %i "$W/var/home")" = 256 || { echo "FEHLER: /var/home ist kein Teilbereich"; exit 1; }
nachher=$(cd "$W/var/home" && find . | sort | md5sum)
test "$vorher" = "$nachher" || { echo "FEHLER: Dateien unterschiedlich"; exit 1; }
test "$(stat -c %u:%a "$W/var/home/nutzer")" = "1000:700" || { echo "FEHLER: Besitzer/Rechte"; exit 1; }
grep -q "Hallo Tresor" "$W/var/home/nutzer/Dokumente/Briefe/brief.txt"
test -L "$W/var/home/nutzer/verknuepfung"
test ! -e "$W/var/home.tresor-alt" && test ! -e "$W/var/home.tresor-neu"

echo "── Zweiter Lauf ändert nichts"
"$B" --vorbereiten | grep -q "schon bereit"

echo "── Schnappschuss"
s=$("$B" --schnappschuss)
echo "Neue Datei" > "$W/var/home/nutzer/neu.txt"
rm "$W/var/home/nutzer/Dokumente/Briefe/brief.txt"
grep -q "Hallo Tresor" "$W/var/lib/auriliux/schnappschuesse/$s/nutzer/Dokumente/Briefe/brief.txt"
test ! -e "$W/var/lib/auriliux/schnappschuesse/$s/nutzer/neu.txt"
test "$(stat -c %a "$W/var/lib/auriliux/schnappschuesse")" = 700
if touch "$W/var/lib/auriliux/schnappschuesse/$s/nutzer/x" 2>/dev/null; then echo "FEHLER: Schnappschuss beschreibbar"; exit 1; fi

echo "── Status"
"$B" --einmal
echo "Tresor-Test bestanden"
