# Auriliux OS – Installer-Anweisungen (Kickstart) für das MacBook Pro 12,1 NEBEN macOS.
#
# Sicherheitsregeln (werden im Cloud-Bau an einer nachgebauten Mac-Platte geprüft):
#  • Es wird NICHTS gelöscht: kein clearpart, keine bestehende Partition wird angefasst – nur freier Platz.
#  • Auriliux bekommt eine EIGENE EFI-Partition. Die vorhandene (mit OpenCore) bleibt unverändert;
#    zur Sicherheit wird OpenCores Startdatei vorher gesichert und hinterher verglichen/wiederhergestellt.
#  • Die Startreihenfolge im Mac bleibt, wie sie ist (OpenCore startet zuerst, Auriliux wählst du dort aus).
#  • Fehlt die interne Platte mit macOS oder ist zu wenig frei, bricht der Installer ab, bevor er etwas ändert.
# Sprache, Tastatur (deutsch, Mac) und Zeitzone sind vorgegeben. Benutzername, Passwort und das
# Festplatten-Passwort gibst du im Installer selbst ein.
# (Die Zeile „ostreecontainer“ fügt der Bau selbst hinzu.)

graphical
lang de_DE.UTF-8
keyboard --vckeymap=de-mac --xlayouts='de (mac)'
timezone Europe/Berlin --utc
rootpw --lock
network --hostname=auriliux
# Startdateien nur auf die eigene EFI-Partition, NVRAM/Startreihenfolge des Macs nicht verändern
bootloader --leavebootorder --append="firmware_class.path=/var/lib/firmware rhgb quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"

%pre --interpreter=/bin/bash --erroronfail --log=/tmp/auriliux-pre.log
# ── Vorbereitung: interne Platte finden, Platz prüfen, OpenCore sichern, Aufteilung festlegen ──
set -u
APFS=7c3457ef-0000-11aa-aa11-00306543ecac
ESP=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
MINDEST_GB=${AURILIUX_MINDEST_GB:-30}
melde() { echo "AURILIUX: $*"; for t in /dev/tty1 /dev/console; do echo "AURILIUX: $*" > "$t" 2>/dev/null && break; done; }
abbruch() { melde "$*"; melde "Es wurde nichts verändert. Bitte die Anleitung (Schritt 3) ansehen."; sleep 20; exit 1; }

# 1. interne Platte: kein USB-Gerät und mit einer macOS-Partition (APFS)
ziel=""
typ=${AURILIUX_PLATTENTYP:-disk}          # (nur die Prüfung im Bau nutzt nachgebaute Platten vom Typ „loop“)
for d in $(lsblk -dnpo NAME,TYPE | awk -v t="$typ" '$2==t {print $1}'); do
    [ "$(lsblk -dno TRAN "$d" 2>/dev/null | tr -d ' ')" = "usb" ] && continue
    if lsblk -nro PARTTYPE "$d" 2>/dev/null | grep -qi "$APFS"; then ziel="$d"; break; fi
done
[ -n "$ziel" ] || abbruch "Keine interne Platte mit macOS gefunden."
melde "Interne Platte: $ziel ($(lsblk -dno SIZE "$ziel" | tr -d ' '))"

# 2. freier, unbelegter Platz (größtes freies Stück)
frei=$(parted -m -s "$ziel" unit B print free 2>/dev/null | grep 'free;$' | awk -F: '{gsub("B","",$4); if ($4+0 > m) m = $4+0} END {printf "%d", m}')
frei_gb=$(( ${frei:-0} / 1073741824 ))
[ "$frei_gb" -ge "$MINDEST_GB" ] || abbruch "Nur ${frei_gb} GB frei – Auriliux braucht mindestens ${MINDEST_GB} GB. macOS zuerst verkleinern."
melde "Freier Platz für Auriliux: ${frei_gb} GB"

# 3. vorhandene EFI-Partition (OpenCore): Startdateien sichern und Prüfsummen merken
mkdir -p /tmp/oc-esp /tmp/oc-sicherung
: > /tmp/oc-pruefsummen
for p in $(lsblk -nrpo NAME,PARTTYPE "$ziel" | awk -v e="$ESP" 'tolower($2)==e {print $1}'); do
    if mount -o ro "$p" /tmp/oc-esp 2>/dev/null; then
        if [ -d /tmp/oc-esp/EFI/BOOT ] || [ -d /tmp/oc-esp/EFI/OC ]; then
            ( cd /tmp/oc-esp && tar -cf "/tmp/oc-sicherung/$(basename "$p").tar" EFI )
            ( cd /tmp/oc-esp && find EFI/BOOT -type f -exec sha256sum {} + 2>/dev/null ) | sed "s#^#$(basename "$p") #" >> /tmp/oc-pruefsummen
            [ -d /tmp/oc-esp/EFI/OC ] && melde "OpenCore gefunden auf $p – wird nicht verändert"
        fi
        umount /tmp/oc-esp
    fi
done

# 4. Aufteilung NUR im freien Bereich: eigene EFI (600 MB), /boot (1 GB), Rest verschlüsselt (btrfs)
name=$(basename "$ziel")
cat > /tmp/auriliux-teile.ks <<TEILE
ignoredisk --only-use=$name
part /boot/efi --fstype=efi --size=600 --ondisk=$name --label=AURILIUXEFI
part /boot --fstype=ext4 --size=1024 --ondisk=$name --label=auriliux-boot
part btrfs.01 --encrypted --luks-version=luks2 --grow --ondisk=$name
btrfs none --label=auriliux btrfs.01
btrfs / --subvol --name=root auriliux
TEILE
melde "Aufteilung vorbereitet – bestehende Partitionen bleiben unberührt"
%end

%include /tmp/auriliux-teile.ks

%post --nochroot --interpreter=/bin/bash --log=/tmp/auriliux-post.log
# ── Nacharbeit: OpenCore unverändert? Auriliux-Eintrag in der OpenCore-Startauswahl benennen ──
set -u
shopt -s nullglob
mkdir -p /tmp/oc-pruef
while read -r teil summe datei; do
    p="/dev/$teil"
    mount "$p" /tmp/oc-pruef 2>/dev/null || continue
    if ! echo "$summe  /tmp/oc-pruef/$datei" | sha256sum -c --status - 2>/dev/null; then
        echo "OpenCore-Datei $datei auf $p wurde verändert – stelle die Sicherung wieder her"
        ( cd /tmp/oc-pruef && tar -xf "/tmp/oc-sicherung/$teil.tar" )
    else
        echo "OpenCore-Datei $datei auf $p unverändert"
    fi
    umount /tmp/oc-pruef
done < /tmp/oc-pruefsummen
# eigene EFI-Partition: Name und Gold-Symbol für die OpenCore-Startauswahl
for m in /mnt/sysroot/boot/efi /mnt/sysimage/boot/efi; do
    [ -d "$m/EFI" ] || continue
    printf 'Auriliux OS' > "$m/.contentDetails"
    icns=$(ls /mnt/sysroot/ostree/deploy/*/deploy/*/usr/share/auriliux/auriliux.icns 2>/dev/null | head -1)
    [ -n "$icns" ] && cp "$icns" "$m/.VolumeIcon.icns"
    echo "Startauswahl-Name gesetzt in $m"
done
# Protokolle ins installierte System (/var/log/auriliux-installation)
for v in /mnt/sysroot/ostree/deploy/*/var; do
    mkdir -p "$v/log/auriliux-installation" && cp /tmp/auriliux-pre.log /tmp/auriliux-post.log /tmp/oc-pruefsummen "$v/log/auriliux-installation/" 2>/dev/null
done
true
%end
