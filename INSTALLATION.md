# Auriliux OS installieren – neben macOS

Auriliux kommt **neben** macOS auf die interne SSD. macOS, deine Daten und die OpenCore-Startauswahl bleiben,
wie sie sind. Beim Einschalten wählst du in der OpenCore-Startauswahl „macOS“ oder „Auriliux OS“.

**Was der Installer garantiert** (wird bei jedem Cloud-Bau an einer nachgebauten Mac-Platte geprüft):
- Er löscht nichts und benutzt **nur freien, unbelegten Platz**.
- Auriliux bekommt eine **eigene EFI-Partition**. Die vorhandene mit OpenCore wird nicht beschrieben. Zur Sicherheit wird OpenCores Startdatei vorher gesichert und nach der Installation verglichen. Bei einer Abweichung wird sie wiederhergestellt.
- Die Startreihenfolge des Macs wird **nicht** verändert. OpenCore startet weiter zuerst.
- Findet er keine interne Platte mit macOS oder ist zu wenig Platz frei, **bricht er ab, bevor er etwas ändert**.
- Auriliux wird **verschlüsselt** (LUKS2). Ohne dein Festplatten-Passwort kommt niemand an die Daten.

Vorher prüfen, ob alles bereit ist. Das Skript ändert nichts, es liest nur:

```bash
bash ~/System_2.0/AuriliuxOS/werkzeuge/mac-pruefen.sh
```

---

## 1. Sicherung

macOS bleibt zwar erhalten, aber du arbeitest an der Aufteilung der Platte. Kopiere deshalb vorher
deine wichtigen Ordner auf **AURILIUX**: Dokumente, Bilder, Schreibtisch und `System_2.0`.

## 2. USB-Stick besorgen

Du brauchst einen **Markenstick mit 16–32 GB**. Der alte Stick meldet 0 Byte und ist defekt oder gefälscht.
Alles auf dem Stick wird beim Beschreiben gelöscht.

## 3. Platz für Auriliux schaffen (macOS verkleinern)

Auriliux braucht **mindestens 30 GB**, gut sind 35–45 GB. Updates halten immer zwei Systemstände bereit.

Stand 27.11.2026:
- **SSD:** 121 GB.
- **macOS belegt:** 74 GB.
- **Davon allein die Claude-App:** etwa 12 GB (`~/Library/Application Support/Claude/vm_bundles`).
- **Vorbereitetes macOS-Update:** wartet und belegt zusätzlich Platz.

| Auriliux | macOS-Bereich danach | frei für macOS |
|---|---|---|
| 45 GB | 76 GB | **≈ 2 GB – zu wenig** |
| 35 GB | 86 GB | ≈ 12 GB |
| 30 GB | 91 GB | ≈ 17 GB |

Willst du Auriliux mehr Platz geben, schaffe zuerst in macOS Platz und miss dann neu mit `mac-pruefen.sh`.

Verkleinert wird im Terminal von macOS, im laufenden Betrieb. FileVault darf an bleiben. Beispiel für
**35 GB** für Auriliux: Der macOS-Bereich wird auf 86 GB gesetzt, der Rest wird frei.

```bash
diskutil apfs resizeContainer disk0s2 86g
```

Danach zeigt `mac-pruefen.sh` „Freier, unbelegter Bereich vorhanden“. Bitte **nichts formatieren**.
Der freie Bereich bleibt leer, der Installer nimmt ihn sich.

## 4. Installer herunterladen

Der Installer (ISO) wird in der Cloud gebaut:
- Auf GitHub unter **Actions → „Auriliux OS bauen“ → Run workflow** den Haken „Installer (ISO) erzeugen“ setzen.
- Danach liegt er unter **Releases** in Teilen zu 1,9 GB.

Alle Teile und `pruefsummen.txt` in einen Ordner laden. Im Terminal in diesen Ordner wechseln und die Teile prüfen.
Jede Zeile muss „OK“ melden:

```bash
grep teil pruefsummen.txt | shasum -a 256 -c
```

Dann zusammensetzen:

```bash
cat auriliux-os.iso.teil* > auriliux-os.iso
```

## 5. Stick beschreiben

Stick einstecken und mit `mac-pruefen.sh` die Nummer des Sticks ablesen, zum Beispiel `/dev/disk4`.
**Genau hinsehen:** Die AURILIUX-Festplatte und die interne SSD (`disk0`) sind es **nicht**.

```bash
diskutil unmountDisk /dev/disk4
```

```bash
sudo dd if=auriliux-os.iso of=/dev/rdisk4 bs=4m status=progress
```

Danach meldet macOS, dass der Stick nicht lesbar ist. Das ist richtig, also „Auswerfen“ wählen.

## 6. Vom Stick starten

Netzteil anschließen und den Stick einstecken. Neu starten und dabei **⌥ (Alt) gedrückt halten**, dann
**„EFI Boot“** (den Stick) wählen. Steht der Stick schon in der OpenCore-Auswahl, geht es auch dort.
Im Menü „Install Auriliux OS“ wählen.

Der Installer ist auf Deutsch eingestellt, mit Mac-Tastatur und Zeitzone Berlin. Du machst nur zwei Dinge:
1. **Benutzer anlegen:** Name, Passwort und den Haken **„Diesen Benutzer zum Administrator machen“**.
2. **Festplatten-Passwort:** Wenn der Installer fragt, ein gutes Passwort wählen und **aufschreiben**.
   Ohne dieses Passwort sind die Auriliux-Daten verloren. Niemand kann es zurücksetzen.

„Installation beginnen“ klicken. Das dauert etwa 10–20 Minuten. Danach „Neustart“ und den Stick abziehen.

## 7. Erster Start

Die OpenCore-Startauswahl zeigt jetzt **„Auriliux OS“** mit dem Gold-Logo:
- Auswählen → Boot-Intro → goldene Abfrage des Festplatten-Passworts → goldener Login.
- macOS startest du wie bisher über denselben Bildschirm.

Erste Schritte in Auriliux:
- **WLAN:** Zentrale → WLAN.
- **James:** James-Fenster öffnen, Server-Adresse und App-Schlüssel eingeben.
- **Claude Code:** Programm „Claude Code“ öffnen und `/login` eingeben.
- **Tresor:** Tresor öffnen und einen Code festlegen. AURILIUX anstecken, damit der Tresor sichern kann.
- **Kamera:** Die Firmware liest Auriliux beim ersten Start selbst aus macOS aus.

## Wenn etwas nicht klappt

- **„Auriliux OS“ fehlt in der OpenCore-Auswahl:** Beim Start ⌥ halten und den Eintrag „EFI Boot“ der
  internen Platte wählen, der nicht OpenCore ist.
- **Der Mac startet ohne OpenCore** (sollte nicht passieren, die Startreihenfolge bleibt unverändert):
  Beim Start ⌥ halten → „EFI Boot“ (OpenCore) wählen. In macOS mit OpenCore Legacy Patcher
  „Build and Install OpenCore“ erneut ausführen.
- **Installer bricht ab mit „AURILIUX: …“:** Die Meldung nennt den Grund, zum Beispiel zu wenig Platz.
  Es wurde nichts verändert.
- **Protokolle der Installation:** In Auriliux unter `/var/log/auriliux-installation/`.

## Auriliux wieder entfernen

In macOS das Festplattendienstprogramm öffnen und unter „Partitionieren“ die drei Auriliux-Partitionen löschen:
- **AURILIUXEFI** (600 MB)
- **auriliux-boot** (1 GB)
- **den verschlüsselten Bereich**

Danach den macOS-Bereich wieder auf die ganze Platte vergrößern:

```bash
diskutil apfs resizeContainer disk0s2 0
```

OpenCore und macOS bleiben dabei unberührt.
