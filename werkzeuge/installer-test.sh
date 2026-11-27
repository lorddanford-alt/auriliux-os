#!/bin/bash
# Prüft die Installer-Anweisungen (image/installer/auriliux.ks) an einer NACHGEBAUTEN Mac-Platte (Datei, keine echte Platte):
#   1. Syntax (ksvalidator aus Fedoras pykickstart)
#   2. %pre findet die „interne Platte“ mit macOS, sichert OpenCore und teilt NUR den freien Platz auf
#   3. bei zu wenig Platz bricht %pre ab und ändert nichts
#   4. die erzeugte Aufteilung legt sich auf die richtige Platte und rührt bestehende Partitionen nicht an
# Läuft im Fedora-Behälter mit --privileged (für Schleifen-Geräte). Aufruf: bash installer-test.sh /pfad/zu/auriliux.ks
set -euo pipefail
KS="$1"
dnf -y -q install --setopt=install_weak_deps=False pykickstart parted dosfstools util-linux python3 >/dev/null
fehler=0
pruefe() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fehler=$((fehler + 1)); fi; }

pre_skript() { awk '/^%pre /{f=1; next} /^%end/{if(f){exit}} f' "$KS"; }
post_skript() { awk '/^%post /{f=1; next} /^%end/{if(f){exit}} f' "$KS"; }

mac_platte() {   # $1 = GB, die macOS belegt (Rest bleibt frei)
    rm -f /tmp/mac.img; truncate -s 121G /tmp/mac.img
    parted -s /tmp/mac.img mklabel gpt mkpart EFI fat32 1MiB 211MiB set 1 esp on mkpart macOS 211MiB "$(( $1 * 1024 + 211 ))MiB"
    sgdisk_typ=7c3457ef-0000-11aa-aa11-00306543ecac
    parted -s /tmp/mac.img type 2 "$sgdisk_typ"
    dev=$(losetup -fP --show /tmp/mac.img)
    udevadm settle 2>/dev/null || sleep 1
    mkfs.vfat -n EFI "${dev}p1" >/dev/null
    mkdir -p /tmp/m && mount "${dev}p1" /tmp/m
    mkdir -p /tmp/m/EFI/BOOT /tmp/m/EFI/OC
    echo "OpenCore-Start" > /tmp/m/EFI/BOOT/BOOTx64.efi; echo "OpenCore" > /tmp/m/EFI/OC/OpenCore.efi
    umount /tmp/m
    echo "$dev"
}

echo "1. Syntax"
sed 's#^%include /tmp/auriliux-teile.ks#%include /tmp/teile-probe.ks#' "$KS" > /tmp/ks-probe.ks
printf 'ignoredisk --only-use=sda\npart /boot/efi --fstype=efi --size=600 --ondisk=sda\npart /boot --fstype=ext4 --size=1024 --ondisk=sda\npart btrfs.01 --encrypted --luks-version=luks2 --grow --ondisk=sda\nbtrfs none --label=auriliux btrfs.01\nbtrfs / --subvol --name=root auriliux\n' > /tmp/teile-probe.ks
pruefe "ksvalidator ohne Fehler" "ksvalidator -v F45 /tmp/ks-probe.ks || ksvalidator /tmp/ks-probe.ks"
pruefe "kein clearpart/zerombr/autopart (nichts wird gelöscht)" "! grep -Eq '^(clearpart|zerombr|autopart)' '$KS'"
pruefe "Startreihenfolge bleibt (--leavebootorder)" "grep -q -- '--leavebootorder' '$KS'"

echo "2. Mac-Platte mit 74 GB macOS → ~46 GB frei"
dev=$(mac_platte 74)
vorher=$(sfdisk -d "$dev" | grep "^$dev")
rm -f /tmp/auriliux-teile.ks /tmp/oc-pruefsummen; rm -rf /tmp/oc-sicherung
pruefe "%pre läuft durch" "pre_skript | AURILIUX_PLATTENTYP=loop bash > /tmp/pre.out 2>&1"
cat /tmp/pre.out | sed 's/^/      /'
pruefe "richtige Platte gewählt ($(basename "$dev"))" "grep -q 'ignoredisk --only-use=$(basename "$dev")$' /tmp/auriliux-teile.ks"
pruefe "alle Teile auf dieser Platte" "! grep 'ondisk=' /tmp/auriliux-teile.ks | grep -vq 'ondisk=$(basename "$dev")'"
pruefe "eigene EFI-Partition (nicht die von OpenCore)" "grep -q '^part /boot/efi --fstype=efi --size=600' /tmp/auriliux-teile.ks"
pruefe "Rest verschlüsselt (LUKS2)" "grep -q 'btrfs.01 --encrypted --luks-version=luks2 --grow' /tmp/auriliux-teile.ks"
pruefe "OpenCore gesichert" "tar -tf /tmp/oc-sicherung/$(basename "$dev")p1.tar | grep -q 'EFI/OC/OpenCore.efi'"
pruefe "Prüfsumme von BOOTx64.efi gemerkt" "grep -q 'EFI/BOOT/BOOTx64.efi' /tmp/oc-pruefsummen"
pruefe "Partitionen unverändert" "[ \"\$(sfdisk -d $dev | grep '^$dev')\" = \"\$vorher\" ]"
echo "   Aufteilung:"; sed 's/^/      /' /tmp/auriliux-teile.ks

echo "3. Nacharbeit: OpenCore-Startdatei „überschrieben“ → wird wiederhergestellt"
mount "${dev}p1" /tmp/m && echo "shim von Fedora" > /tmp/m/EFI/BOOT/BOOTX64.EFI && umount /tmp/m
mkdir -p /mnt/sysroot/boot/efi/EFI
post_skript | bash > /tmp/post.out 2>&1 || true
sed 's/^/      /' /tmp/post.out
mount "${dev}p1" /tmp/m
pruefe "OpenCore-Startdatei wieder da" "grep -q 'OpenCore-Start' /tmp/m/EFI/BOOT/BOOTx64.efi"
umount /tmp/m
pruefe "Name für die Startauswahl gesetzt" "grep -q 'Auriliux OS' /mnt/sysroot/boot/efi/.contentDetails"
losetup -d "$dev"

echo "4. Zu wenig Platz (macOS belegt 100 GB → ~20 GB frei)"
dev=$(mac_platte 100)
rm -f /tmp/auriliux-teile.ks
pruefe "%pre bricht ab" "! (pre_skript | sed 's/sleep 20/true/' | AURILIUX_PLATTENTYP=loop bash > /tmp/pre2.out 2>&1)"
sed 's/^/      /' /tmp/pre2.out
pruefe "keine Aufteilung erzeugt" "[ ! -e /tmp/auriliux-teile.ks ]"
losetup -d "$dev"

echo
if [ "$fehler" -eq 0 ]; then echo "Installer-Prüfung: alles in Ordnung"; else echo "Installer-Prüfung: $fehler Fehler"; exit 1; fi
