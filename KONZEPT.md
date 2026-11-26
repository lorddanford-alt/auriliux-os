# Auriliux OS – Gesamtkonzept (Entwurf 2, 26.11.2026)

Ein eigenes, schlankes und sicheres Betriebssystem für das MacBook Pro 13" (2015, MacBookPro12,1),
im goldenen Auriliux-Stil. Grundlage ist Linux (Kern, Treiber, Grafik-Unterbau), **alles Sichtbare und
alle Schutz- und Leistungsdienste programmieren wir selbst**. Ausnahme: der Webbrowser (Google Chrome).

---

## 1. Ziele

| Ziel | Was das konkret heißt |
|---|---|
| **Leistung** | Im Leerlauf ≤ 800 MB RAM und ≈ 1 % CPU (macOS 15 heute: ~3–4 GB, WindowServer bis 25 %). Das Programm vorne bekommt immer Vorrang. |
| **Schonung** | Prozessor bleibt unter ~85 °C, Lüfter reagiert früh und sanft, nie Dauer-Überlast; Akku-Modus spart automatisch. |
| **Sicherheit** | Unveränderliches System, Ausführungsschutz, eigener Wächter „Guardian“, Firewall, Verschlüsselung, Schnappschüsse gegen Erpresser-Viren. |
| **Eigenes Aussehen** | Gold auf Schwarz wie das Auriliux-Logo, Laser-Intro schon beim Hochfahren, Goldleiste, Golddock, Wabenfinder. |
| **Rückweg** | macOS bleibt zunächst daneben erhalten; Systemfehler lassen sich mit einem Klick auf den letzten Stand zurücksetzen. |

---

## 2. Grundaufbau (Schichten)

```
┌──────────────────────────────────────────────────────────────┐
│  SELBST PROGRAMMIERT                                          │
│  Goldleiste · Golddock · Wabenfinder · App-Suche · Hintergrund │
│  Boot-Intro · Anmeldebildschirm · Sperrbildschirm · Zentrale  │
│  Guardian (Schutz) · Herzschlag (Leistung) · Tresor (Sicherung)│
│  James · Charakter · Aufgaben · Benachrichtigungen            │
├──────────────────────────────────────────────────────────────┤
│  BAUSTEINE (Open Source, nicht neu erfunden)                  │
│  Fenster-Manager labwc (Wayland) · Qt 6/QML · PipeWire (Ton)  │
│  NetworkManager · ClamAV/YARA-Signaturen · USBGuard · firewalld│
├──────────────────────────────────────────────────────────────┤
│  BASIS: Fedora Atomic (unveränderliches System, Linux-Kern,   │
│  Treiber für WLAN, Grafik, Trackpad, Ton) · SELinux · LUKS2   │
└──────────────────────────────────────────────────────────────┘
```

**Warum nicht wirklich alles von null?** Treiber, Grafik-Unterbau und Kern sind Jahrzehnte Arbeit von
Tausenden Entwicklern. Selbst gebaut wäre das langsamer und unsicherer. Alles, was du siehst und was
schützt oder steuert, ist dagegen von uns.

### Entscheidungen und Begründung
- **Fedora Atomic als Basis:** Die Systemdateien sind schreibgeschützt (Viren können sie nicht verändern).
  Updates kommen als ganzes geprüftes Abbild; geht etwas schief, startet man das vorherige Abbild.
  SELinux ist ab Werk aktiv. Neuer Kern = gute Treiber für das MacBook.
- **Eigenes Systemabbild („Auriliux-Abbild“):** Wir bauen das komplette System als ein Abbild in der
  Cloud (GitHub). Daraus entsteht ein USB-Installer, auf dem **alles schon fertig drin ist**: Design,
  Guardian, Herzschlag, Programme. Nach der Installation ist sofort das Endprodukt da. Spätere Verbesserungen
  kommen als neues Abbild (wie ein Update-ZIP, nur für das ganze System) – mit Rückweg.
- **labwc als Fenster-Manager:** sehr sparsam (≈ 10 MB), klassische schwebende Fenster wie am Mac,
  komplett in Gold umgestaltbar. Leiste, Dock und Hintergrund liegen als eigene Ebenen darauf.
- **Qt 6 / QML für alle Oberflächen:** Zeichnet über die Grafikkarte, braucht ein Bruchteil des Speichers
  der bisherigen Web-Ansichten (≈ 20–40 MB statt 150–200 MB) und erlaubt flüssige Animationen.
  Die bisherigen HTML-Entwürfe dienen als Vorlage für Aussehen und Verhalten.
- **Rust für Guardian und Herzschlag:** Dienste, die mit vollen Rechten laufen, müssen speichersicher sein.
  Rust verhindert ganze Fehlerklassen, über die Angreifer sonst einbrechen.

---

## 3. Aussehen („Auriliux-Gold“)

- **Farben:** Gold #d4a640 · Hellgold #f6dc8c · Akzent #e6bd57 · Elfenbein-Text #eadfc6 · warmes Schwarz #070502.
  Signalfarben bleiben: Grün erledigt, Rot Warnung, Bernstein Hinweis.
- **Schrift:** Cinzel für Titel (wie die Webseite), Cormorant für Text, eine Mono-Schrift für Messwerte.
- **Fenster:** schwarze Titelleiste mit goldener Haarlinie; Schließen/Minimieren/Vergrößern als drei
  kleine Goldrauten; aktives Fenster leicht goldener Schein.
- **Ablauf beim Einschalten:**
  1. Startauswahl (OpenCore) → „Auriliux OS“
  2. **Boot-Intro:** das Laser-Intro der Webseite, Bild für Bild aus dem Original aufgenommen, läuft schon
     während das System lädt (unter macOS unmöglich, hier machbar).
  3. **Anmeldung:** fertiges Goldlogo, darunter Passwortfeld mit goldener Linie (Festplatte wird damit entschlüsselt).
  4. **Schreibtisch:** Logo als Hintergrund, Waben-Schreibtisch, Goldleiste oben, Golddock unten.

---

## 4. Die Programme (alle selbst geschrieben)

| Programm | Aufgabe | Vorbild |
|---|---|---|
| **Goldleiste** | oben: Auriliux-Menü (Aus/Neustart/Ruhe/Sperren), App-Menüs, CPU/RAM/Temperatur, WLAN, Akku, Uhr, KI-Schalter, Lupe, Fokus-/Guardian-Anzeige | Neonleiste |
| **Golddock** | unten: runde Goldkreise, Vergrößern, Fenster-Vorschau, Home-Knopf (alle Fenster weg – hier technisch sauber lösbar) | Neondock |
| **Wabenfinder** | Dateimanager in Waben, Laufwerke-Ring mit Auswerfen, Schnellvorschau, Suche | Wabenfinder |
| **App-Suche** | Lupe/Tastenkürzel, sucht Programme, Dateien, Einstellungen | Suche der Neonleiste |
| **Hintergrund** | Logo-Standbild nach dem Intro (kostet fast nichts) | AuriliuxHintergrund |
| **Zentrale** | Einstellungen: Bildschirm, Ton, WLAN, Bluetooth, Tastatur-Licht, Energie, Benutzer, Updates | – |
| **Guardian** | Schutz-Zentrale (Kapitel 5) | Systemwächter |
| **Herzschlag** | Leistungs-Wächter (Kapitel 6) | Fokus-Modus |
| **Tresor** | Schnappschüsse, Sicherung auf AURILIUX, Wiederherstellen einzelner Dateien oder ganzer Stände | – |
| **James** | Sprachassistent (Server bleibt gleich, neues Linux-Programm), Wake-Word „James“ | James |
| **Charakter & Aufgaben** | wie bisher, im Gold-Stil | Wabenfinder-Fenster |
| **Benachrichtigungen** | goldene Hinweis-Karten oben rechts | – |

**Fremdprogramme:** Google Chrome. WhatsApp als Web-App. Malstudio als Web-App im Browser.
Digsoin Office, Digsoin Creative Studio und PeopleChat sind Electron-Programme → gibt es davon Linux-Versionen? (offene Frage)

---

## 5. Guardian – Schutz vor Viren und Angriffen

Grundgedanke: **Viren gar nicht erst ausführen lassen** ist stärker als sie hinterher zu finden.
Guardian hat sieben Schilde:

1. **System-Schild:** Systemdateien sind schreibgeschützt und kryptografisch geprüft. Guardian prüft
   regelmäßig, dass nichts verändert wurde.
2. **Ausführungs-Schild:** In deinem Benutzerordner (Downloads usw.) darf nichts direkt starten. Neue
   Programme nur aus dem geprüften System oder über Guardian-Freigabe nach Prüfung.
3. **Echtzeit-Scanner:** jede neue Datei (Download, USB, Mail-Anhang) wird sofort geprüft:
   Virensignaturen (ClamAV-Datenbank, täglich aktualisiert) + YARA-Regeln + eigene Regeln
   (z. B. „Skript lädt aus dem Internet nach und führt aus“, Krypto-Miner, verschleierte Skripte).
   Funde kommen in die Quarantäne.
4. **Netz-Schild:** Firewall lässt von außen nichts herein (keine offenen Türen). Ein DNS-Filter
   blockiert bekannte Schadseiten und Phishing-Adressen für das ganze System.
   Optional: Nachfrage, wenn ein unbekanntes Programm ins Internet will.
5. **USB-Schild:** neue USB-Geräte müssen bestätigt werden (schützt vor „Tastatur-Sticks“, die
   blitzschnell Befehle eintippen).
6. **Erpresser-Schild:** stündliche, unveränderliche Schnappschüsse deiner Dateien. Ändert ein Programm
   plötzlich massenhaft Dateien (typisch für Verschlüsselungs-Viren), friert Guardian es sofort ein und
   meldet sich. Dateien lassen sich aus dem Schnappschuss zurückholen.
7. **Autostart-Wächter:** meldet jeden neuen Eintrag, der sich beim Start mitladen will (so nisten sich
   Schädlinge ein).

Außerdem: **Festplatte verschlüsselt** (LUKS2, wie FileVault), **automatische Sicherheits-Updates**,
kein Fernzugang aktiv, Chrome mit Schutzfunktionen und Werbe-/Tracking-Blocker.

**Ehrlich gesagt:** Kein System ist zu 100 % virenfrei. Das größte Restrisiko bleibt Täuschung
(gefälschte Login-Seiten, „führ diesen Befehl aus“). Guardian warnt bei solchen Mustern, kann dir die
Entscheidung aber nicht ganz abnehmen.

---

## 6. Herzschlag – maximale Leistung, schonend

1. **Vorrang für das, was du benutzt:** das vordere Programm bekommt den größten Anteil an Prozessor
   und Festplatte, Hintergrundprogramme den kleinsten (Linux-„cgroups“ – viel wirksamer als unter macOS).
2. **Fokus-Modus 2.0:** im Vollbild werden Hintergrundprogramme **eingefroren** (verbrauchen dann
   nichts mehr) und beim Verlassen sofort aufgetaut. Ausnahmen: James, Musik, laufende Downloads.
3. **Wärme-Schutz:** eigene Lüfterkurve (früher, aber leiser anlaufen); bleibt der Prozessor zu lange
   heiß, wird der Turbo sanft gedeckelt statt hart gedrosselt. Ziel: nie über ~85 °C dauerhaft.
4. **Speicher:** komprimierter Arbeitsspeicher (zram) – aus 8 GB werden effektiv ~12 GB; bei Engpass wird
   zuerst Hintergrund, nie das vordere Programm geopfert.
5. **Energieprofile:** am Netz „Leistung“, im Akku „Ausgewogen“, unter 20 % „Sparen“ – automatisch.
6. **Anzeige in der Leiste:** Temperatur, Last und ein Herz-Symbol, das bei Überlast warnt und
   den Verursacher nennt.

---

## 7. Hardware-Check (MacBookPro12,1) und bekannte Stolpersteine

| Teil | Linux-Unterstützung | Plan |
|---|---|---|
| Grafik Intel Iris 6100 | sehr gut (Mesa, beschleunigt) | – |
| WLAN Broadcom BCM43602 | Treiber brcmfmac im Kern, gilt als gelegentlich wackelig | im Live-Test prüfen; Notfall: USB-WLAN-Stick (~15 €) |
| Trackpad (Force Touch) | funktioniert, ohne Kraftklick | Gesten selbst nachbauen (Wischen für Fokus/Home) |
| Tastatur + Licht | funktioniert | Tastatur-Licht-Regler in der Zentrale |
| Ton + Mikrofon | funktioniert | – |
| FaceTime-Kamera | **nur mit Zusatztreiber** (facetimehd) | ins Abbild einbauen, falls du die Kamera brauchst |
| Ruhezustand | funktioniert meist | im Live-Test prüfen |
| Lüfter/Temperatur | über applesmc | Herzschlag steuert |
| Start über OpenCore | Linux lässt sich dort auswählen | im Test prüfen; sonst Startauswahl mit ⌥-Taste |

---

## 8. Ablauf – so bleiben wir nicht mittendrin stecken

Jede Phase endet mit einem **funktionierenden** Zustand. macOS bleibt bis zum Schluss als Rückweg.

| Phase | Inhalt | Wo |
|---|---|---|
| **0 Freigabe** | Dieses Konzept und Entwürfe (Bilder aller Oberflächen) gemeinsam festlegen | jetzt, am Mac |
| **1 Sicherung + Test** | Daten-Sicherung auf AURILIUX; Live-USB mit normalem Fedora: WLAN, Ton, Trackpad, Ruhezustand, Start über OpenCore testen – **ohne** etwas zu installieren | Mac + USB-Stick |
| **2 Bau** | Ich programmiere alles vorab: Abbild-Rezept, Oberflächen, Guardian, Herzschlag, Tresor, James. Das Abbild wird in der Cloud gebaut und automatisch geprüft | am Mac / GitHub |
| **3 Installation** | macOS-Bereich um ~50 GB verkleinern, Auriliux OS daneben installieren (vom fertigen USB-Installer) | einmalig |
| **4 Feinschliff** | 1–2 Wochen nutzen, Fehler beheben, Wünsche einbauen (kommen als Abbild-Updates) | Auriliux OS |
| **5 Entscheidung** | macOS entfernen und den Platz übernehmen – oder beides behalten | gemeinsam |

---

## 9. Weitere Ideen (Vorschläge)

- **Gesten:** Drei-Finger-Wischen nach unten = Home (alle Fenster weg), nach oben = Fenster-Übersicht in Waben.
- **Guardian-Bericht** einmal pro Woche: was geblockt, was aktualisiert, wie gesund der Mac ist.
- **Spiel-/Film-Modus:** Herzschlag friert alles andere ein, Benachrichtigungen aus.
- **Akku-Schonung:** Hinweis bei dauerhaft 100 % am Netz.
- **Sitzung merken:** nach Neustart öffnen sich deine Programme wieder wie vorher.
- **Notfall-Knopf:** im Auriliux-Menü „Sicheren Stand starten“ → letztes funktionierendes Abbild.

---

## 10. Festlegungen (26.11.2026)

- Name: **Auriliux OS**; Programmnamen bleiben (Goldleiste, Golddock, Wabenfinder, Guardian, Herzschlag, Tresor, Zentrale, James).
- **Guardian startet streng:** jedes neue Programm wird beim ersten Internetzugriff nachgefragt.
- **FaceTime-Kamera wird eingebaut** (Treiber facetimehd im Abbild; die Kamera-Firmware wird bei der
  Einrichtung aus dem macOS dieses Macs ausgelesen, nicht aus dem Internet).
- Digsoin Office, Digsoin Creative Studio, PeopleChat: vorerst nicht.
- Claude Code (Terminal-Version von Claude) wird mit eingebaut → Weiterarbeit direkt in Auriliux OS.

## 11. Diagnose vor dem Start (26.11.2026)

| Prüfung | Ergebnis | Folge |
|---|---|---|
| SSD (APPLE SM0128G, 121 GB) | S.M.A.R.T. „Verified“ – gesund | Linux-Bereich 45 GB, macOS behält ~76 GB (47 GB belegt) |
| APFS-Container | 47 GB belegt, 74 GB frei, FileVault an | Verkleinern im laufenden Betrieb möglich (diskutil apfs resizeContainer) |
| EFI-Partition | 210 MB, enthält OpenCore | Linux bekommt eigene /boot-Partition (1 GB); OpenCore-Dateien werden nicht angefasst |
| Start | OpenCore Legacy Patcher aktiv (SIP teilweise aus, macOS-Bootargumente) | Live-Test MUSS über die OpenCore-Startauswahl laufen; Notweg ⌥-Taste beim Start |
| Akku | 208 Ladezyklen, Zustand normal | – |
| WLAN BCM43602 | Linux-Treiber brcmfmac + Firmware im Standardpaket | im Live-Test prüfen |
| Kamera 0x1570 | braucht facetimehd | ins Abbild, Firmware lokal auslesen |
| Sicherung | AURILIUX: 1,8 TB frei, aber exFAT (Time Machine geht darauf nicht) | Sicherung als Ordner-Kopie + Liste aller Einstellungen; macOS bleibt ohnehin erhalten |
| GitHub | Weder GitHub-Programm (gh) noch Zugangsdaten auf diesem Mac | gh installieren, du meldest dich einmal im Browser an |
| USB-Stick | Steuerchip „FirstChip FC3281C“, Seriennummer 012345678901, **meldet 0 Byte Speicher** | defekt oder Fälschung → anderer Stick nötig (Markenstick 16–32 GB) |

### Gefundene Stolpersteine und Lösung
1. **Chrome auf unveränderlichem System:** Das Chrome-Paket installiert nach /opt, das ist dort gesperrt.
   Lösung: beim Bau des Abbilds nach /usr/lib verschieben und verlinken (bewährtes Verfahren).
2. **Strenge App-Firewall:** eigener Rust-Dienst mit nftables + Paket-Warteschlange; Programm wird über
   /proc ermittelt; Freigaben dauerhaft speicherbar. Systemdienste (Updates, Zeit, DNS) sind vorab erlaubt,
   sonst würde das System sich selbst aussperren.
3. **Kleine SSD (121 GB):** Abbild-Updates halten zwei Stände vor → Linux-Bereich nicht unter 40 GB.
4. **OpenCore-Patches** gelten für macOS; ob sie Linux stören, zeigt der Live-Test.
5. **Kamera-Firmware** darf nicht mit ins öffentliche Abbild → Repository privat halten und Firmware lokal auslesen.
