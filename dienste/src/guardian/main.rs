//! Guardian – der Schutz-Dienst von Auriliux OS (läuft als root, gestartet von systemd).
//!   Status:    /run/auriliux/guardian/status.json   (lesbar für alle, wird bei jeder Änderung neu geschrieben)
//!   Steuerung: /run/auriliux/guardian/steuerung.sock (eine Zeile pro Befehl, Felder mit Tabulator getrennt)
//!   Daten:     /var/lib/auriliux/guardian           (nur root)
//! Probelauf ohne Dienst: auriliux-guardian --einmal [--beispiel] [--ausgabe datei.json]
mod autostart;
mod quarantaene;
mod scanner;
mod schilde;
mod usb;
mod wache;

use gemeinsam::datei;
use gemeinsam::json::{self, J};
use gemeinsam::sys;
use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::{FileExt, MetadataExt, PermissionsExt};
use std::os::unix::io::{AsRawFd, FromRawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::mpsc::{self, Receiver, Sender, SyncSender, TrySendError};
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};

pub const DATEN: &str = "/var/lib/auriliux/guardian";
pub const LAUFZEIT: &str = "/run/auriliux/guardian";
const SHELL: &str = "/usr/bin/auriliux-shell";
const PRUEF_TAKT: Duration = Duration::from_secs(15 * 60);

/// Erkennungsmerkmal einer freigegebenen Datei: Laufwerk, Inode, Änderungszeit (s, ns), Größe.
/// Jede Änderung an der Datei (auch chmod) ändert die Änderungszeit → Freigabe gilt dann nicht mehr.
pub type Schluessel = (u64, u64, i64, i64, u64);

#[derive(Clone)]
pub struct Ereignis {
    pub id: String,
    pub zeit: i64,
    pub art: String,
    pub stufe: String,
    pub titel: String,
    pub text: String,
    pub knoepfe: Vec<(String, String)>,
    pub daten: Vec<(String, String)>,
    pub uid: u32,
    pub erledigt: String,
    pub schluessel: String,
}

impl Ereignis {
    pub fn neu(art: &str, stufe: &str, titel: impl Into<String>, text: impl Into<String>) -> Ereignis {
        Ereignis {
            id: String::new(),
            zeit: datei::jetzt_ms(),
            art: art.into(),
            stufe: stufe.into(),
            titel: titel.into(),
            text: text.into(),
            knoepfe: vec![],
            daten: vec![],
            uid: 0,
            erledigt: String::new(),
            schluessel: String::new(),
        }
    }
    pub fn knopf(mut self, aktion: &str, text: &str) -> Ereignis {
        self.knoepfe.push((aktion.into(), text.into()));
        self
    }
    pub fn datum(mut self, k: &str, v: impl Into<String>) -> Ereignis {
        self.daten.push((k.into(), v.into()));
        self
    }
    pub fn fuer(mut self, uid: u32) -> Ereignis {
        self.uid = uid;
        self
    }
    pub fn schluessel(mut self, s: impl Into<String>) -> Ereignis {
        self.schluessel = s.into();
        self
    }
    pub fn wert(&self, k: &str) -> String {
        self.daten.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone()).unwrap_or_default()
    }
    fn json(&self) -> J {
        J::o(vec![
            ("id", J::t(&self.id)),
            ("zeit", J::I(self.zeit)),
            ("art", J::t(&self.art)),
            ("stufe", J::t(&self.stufe)),
            ("titel", J::t(&self.titel)),
            ("text", J::t(&self.text)),
            ("knoepfe", J::L(self.knoepfe.iter().map(|(a, t)| J::o(vec![("aktion", J::t(a)), ("text", J::t(t))])).collect())),
            ("daten", J::O(self.daten.iter().map(|(k, v)| (k.clone(), J::t(v))).collect())),
            ("uid", J::I(self.uid as i64)),
            ("erledigt", J::t(&self.erledigt)),
            ("schluessel", J::t(&self.schluessel)),
        ])
    }
    fn lesen(j: &J) -> Option<Ereignis> {
        let id = j.text_von("id");
        if id.is_empty() {
            return None;
        }
        Some(Ereignis {
            id,
            zeit: j.feld("zeit").and_then(|v| v.als_zahl()).unwrap_or(0),
            art: j.text_von("art"),
            stufe: j.text_von("stufe"),
            titel: j.text_von("titel"),
            text: j.text_von("text"),
            knoepfe: j.feld("knoepfe").map(|l| l.als_liste().iter().map(|k| (k.text_von("aktion"), k.text_von("text"))).collect()).unwrap_or_default(),
            daten: match j.feld("daten") {
                Some(J::O(o)) => o.iter().map(|(k, v)| (k.clone(), v.als_text().unwrap_or("").to_string())).collect(),
                _ => vec![],
            },
            uid: j.feld("uid").and_then(|v| v.als_zahl()).unwrap_or(0) as u32,
            erledigt: j.text_von("erledigt"),
            schluessel: j.text_von("schluessel"),
        })
    }
}

pub enum Meldung {
    Neu(Ereignis),
    Scanner(scanner::Stand),
    StartVerhindert { pfad: String, uid: u32, programm: String, schluessel: Schluessel },
    Pruefung { schilde: Vec<schilde::Schild>, ereignisse: Vec<Ereignis>, usb: Vec<usb::Geraet>, usb_eingerichtet: Option<String> },
    Usb(Vec<usb::Geraet>),
}

struct Guardian {
    ereignisse: Vec<Ereignis>,
    nummer: u64,
    schilde: Vec<schilde::Schild>,
    scan: scanner::Stand,
    tx: Sender<Meldung>,
    rx: Receiver<Meldung>,
    freigaben: wache::Freigaben,
    freigabe_liste: Vec<(String, String, i64)>,
    q: Arc<quarantaene::Quarantaene>,
    auftraege: Option<SyncSender<scanner::Auftrag>>,
    erpresser: wache::Erpresser,
    autostart: autostart::Wache,
    markierer: wache::Markierer,
    gefrierfach: Option<wache::Gefrierfach>,
    exec_fd: i32,
    schreib_fd: i32,
    usb_fd: i32,
    lage: schilde::Lage,
    geaendert: bool,
    zuletzt_geschrieben: Instant,
    pruefung_laeuft: bool,
    naechste_pruefung: Instant,
    usb_faellig: Option<Instant>,
    eigene_pid: i32,
    status_pfad: String,
}

fn antwort_ok(t: &str) -> String {
    J::o(vec![("ok", J::B(true)), ("text", J::t(t))]).text()
}
fn antwort_fehler(t: &str) -> String {
    J::o(vec![("ok", J::B(false)), ("fehler", J::t(t))]).text()
}

impl Guardian {
    fn neu(tx: Sender<Meldung>, rx: Receiver<Meldung>, status_pfad: String) -> Guardian {
        let mut g = Guardian {
            ereignisse: vec![],
            nummer: 0,
            schilde: vec![],
            scan: scanner::Stand { clam: scanner::clam_grundstand(), signaturen: scanner::signaturen_alter(), ..Default::default() },
            tx,
            rx,
            freigaben: Arc::new(RwLock::new(HashSet::new())),
            freigabe_liste: vec![],
            q: Arc::new(quarantaene::Quarantaene::laden()),
            auftraege: None,
            erpresser: wache::Erpresser::neu(),
            autostart: autostart::Wache::neu(),
            markierer: wache::Markierer::neu(),
            gefrierfach: None,
            exec_fd: -1,
            schreib_fd: -1,
            usb_fd: -1,
            lage: schilde::Lage::default(),
            geaendert: true,
            zuletzt_geschrieben: Instant::now().checked_sub(Duration::from_secs(5)).unwrap_or_else(Instant::now),
            pruefung_laeuft: false,
            naechste_pruefung: Instant::now(),
            usb_faellig: None,
            eigene_pid: std::process::id() as i32,
            status_pfad,
        };
        g.laden();
        g
    }

    // ── Speichern / Laden ──
    fn laden(&mut self) {
        if let Some(j) = json::lesen(&datei::lies(format!("{}/ereignisse.json", DATEN))) {
            for e in j.als_liste() {
                if let Some(mut e) = Ereignis::lesen(e) {
                    // eingefrorene Prozesse überleben einen Neustart des Dienstes nicht (systemd beendet sie)
                    if e.art == "erpresser" && e.erledigt.is_empty() {
                        e.erledigt = "Beendet (Guardian wurde neu gestartet)".into();
                    }
                    self.ereignisse.push(e);
                }
            }
        }
        self.nummer = self.ereignisse.len() as u64;
        let mut f = self.freigaben.write().unwrap_or_else(|e| e.into_inner());
        for z in datei::lies(format!("{}/freigaben.tsv", DATEN)).lines() {
            let t: Vec<&str> = z.splitn(3, '\t').collect();
            if t.len() == 3 {
                if let Some(s) = wache::schluessel_lesen(t[0]) {
                    f.insert(s);
                    self.freigabe_liste.push((t[0].to_string(), t[2].to_string(), t[1].parse().unwrap_or(0)));
                }
            }
        }
    }

    fn speichern(&self) {
        let j = J::L(self.ereignisse.iter().map(|e| e.json()).collect());
        let _ = datei::schreiben(&format!("{}/ereignisse.json", DATEN), j.text().as_bytes(), 0o600);
    }

    fn freigaben_speichern(&self) {
        let mut t = String::new();
        for (s, p, z) in &self.freigabe_liste {
            t.push_str(&format!("{}\t{}\t{}\n", s, z, p.replace(['\t', '\n'], " ")));
        }
        let _ = datei::schreiben(&format!("{}/freigaben.tsv", DATEN), t.as_bytes(), 0o600);
    }

    // ── Ereignisse ──
    fn melden(&mut self, mut e: Ereignis) {
        if !e.schluessel.is_empty() {
            let nur_offene = e.art == "start" || e.art == "erpresser" || e.art == "verdacht";
            if let Some(alt) = self.ereignisse.iter_mut().find(|x| x.schluessel == e.schluessel && (x.erledigt.is_empty() || !nur_offene)) {
                if alt.erledigt.is_empty() {
                    alt.zeit = e.zeit;
                    alt.text = e.text;
                    self.geaendert = true;
                }
                return;
            }
        }
        self.nummer += 1;
        e.id = format!("e{}-{}", datei::jetzt_ms(), self.nummer);
        eprintln!("Guardian: {} – {}", e.titel, e.text);
        self.ereignisse.push(e);
        // alle offenen behalten, von den erledigten die neuesten 40
        let mut erledigt: Vec<i64> = self.ereignisse.iter().filter(|x| !x.erledigt.is_empty()).map(|x| x.zeit).collect();
        if erledigt.len() > 40 {
            erledigt.sort_unstable_by(|a, b| b.cmp(a));
            let grenze = erledigt[39];
            self.ereignisse.retain(|x| x.erledigt.is_empty() || x.zeit >= grenze);
        }
        self.speichern();
        self.geaendert = true;
    }

    fn offen(&self, art: &str) -> usize {
        self.ereignisse.iter().filter(|e| e.erledigt.is_empty() && e.art == art).count()
    }

    /// Bewertung wie beim Systemwächter: 100 minus 14 je wichtigem, 6 je empfohlenem, 1 je Hinweis
    fn bewertung(&self) -> (i64, &'static str, usize, usize) {
        let mut stufen: Vec<&str> = self.schilde.iter().filter(|s| s.zustand != "ok" && !s.stufe.is_empty()).map(|s| s.stufe).collect();
        for e in self.ereignisse.iter().filter(|e| e.erledigt.is_empty()) {
            stufen.push(match e.stufe.as_str() {
                "hoch" => "hoch",
                "mittel" => "mittel",
                _ => "info",
            });
        }
        let abzug: i64 = stufen.iter().map(|s| match *s { "hoch" => 14, "mittel" => 6, _ => 1 }).sum();
        let hoch = stufen.iter().filter(|s| **s == "hoch").count();
        let worst = if hoch > 0 { "hoch" } else if stufen.contains(&"mittel") { "mittel" } else { "ok" };
        ((100 - abzug).clamp(0, 100), worst, stufen.len(), hoch)
    }

    fn status_text(&self) -> String {
        let (score, worst, count, hoch) = self.bewertung();
        let mut liste: Vec<&Ereignis> = self.ereignisse.iter().collect();
        liste.sort_by(|a, b| (a.erledigt.is_empty(), a.zeit).cmp(&(b.erledigt.is_empty(), b.zeit)).reverse());
        J::o(vec![
            ("version", J::I(1)),
            ("laeuft", J::B(true)),
            ("zeit", J::I(datei::jetzt_ms())),
            ("score", J::I(score)),
            ("worst", J::t(worst)),
            ("count", J::I(count as i64)),
            ("hoch", J::I(hoch as i64)),
            ("schilde", J::L(self.schilde.iter().map(|s| s.json()).collect())),
            ("ereignisse", J::L(liste.iter().take(50).map(|e| e.json()).collect())),
            ("quarantaene", self.q.json()),
            ("scanner", self.scan.json()),
            (
                "freigaben",
                J::L(self.freigabe_liste.iter().map(|(s, p, z)| J::o(vec![("schluessel", J::t(s)), ("pfad", J::t(p)), ("zeit", J::I(*z))])).collect()),
            ),
        ])
        .text()
    }

    fn status_schreiben(&mut self, sofort: bool) {
        if !self.geaendert || (!sofort && self.zuletzt_geschrieben.elapsed() < Duration::from_millis(300)) {
            return;
        }
        if let Err(e) = datei::schreiben(&self.status_pfad, self.status_text().as_bytes(), 0o644) {
            eprintln!("Guardian: Status nicht geschrieben: {}", e);
        }
        self.geaendert = false;
        self.zuletzt_geschrieben = Instant::now();
    }

    // ── Prüfung (eigener Faden, dauert ein paar Sekunden) ──
    fn lage_aktualisieren(&mut self) {
        self.lage.freigaben = self.freigabe_liste.len();
        self.lage.scan = self.scan.clone();
        self.lage.autostart_eintraege = self.autostart.anzahl();
        self.lage.autostart_offen = self.offen("autostart");
        self.lage.quarantaene = self.q.anzahl();
        self.lage.gefrierfach = self.gefrierfach.is_some();
    }

    fn pruefung_starten(&mut self) {
        self.naechste_pruefung = Instant::now() + PRUEF_TAKT;
        if self.pruefung_laeuft {
            return;
        }
        self.pruefung_laeuft = true;
        self.lage_aktualisieren();
        let lage = self.lage.clone();
        let tx = self.tx.clone();
        let _ = std::thread::Builder::new().name("pruefung".into()).spawn(move || {
            let (schilde, ereignisse, usb, usb_eingerichtet) = schilde::pruefen(&lage);
            let _ = tx.send(Meldung::Pruefung { schilde, ereignisse, usb, usb_eingerichtet });
        });
    }

    fn verarbeiten(&mut self, m: Meldung) {
        match m {
            Meldung::Neu(e) => self.melden(e),
            Meldung::Scanner(s) => {
                self.scan = s;
                self.geaendert = true;
            }
            Meldung::StartVerhindert { pfad, uid, programm, schluessel } => {
                let name = pfad.rsplit('/').next().unwrap_or("").to_string();
                let ordner = pfad.rsplitn(2, '/').nth(1).unwrap_or("").to_string();
                let e = Ereignis::neu(
                    "start",
                    "mittel",
                    format!("Start verhindert: {}", name),
                    format!(
                        "„{}“ wollte ein Programm aus {} starten. Programme aus Benutzerordnern, Downloads und von USB-Sticks laufen nur mit deiner Freigabe. Nur freigeben, wenn du es kennst.",
                        if programm.is_empty() { "Ein Programm".to_string() } else { programm },
                        ordner
                    ),
                )
                .knopf("freigeben", "Freigeben")
                .knopf("ignorieren", "Gesperrt lassen")
                .datum("pfad", &pfad)
                .datum("schluessel", wache::schluessel_text(&schluessel))
                .fuer(uid)
                .schluessel(format!("start:{}", wache::schluessel_text(&schluessel)));
                self.melden(e);
            }
            Meldung::Pruefung { schilde, ereignisse, usb, usb_eingerichtet } => {
                self.pruefung_laeuft = false;
                self.schilde = schilde;
                self.geaendert = true;
                for e in ereignisse {
                    self.melden(e);
                }
                if let Some(t) = usb_eingerichtet {
                    eprintln!("Guardian: USB-Schild {}", t);
                    let _ = self.autostart.behalten("/etc/systemd/system/multi-user.target.wants/usbguard.service");
                }
                self.usb_geraete(usb);
            }
            Meldung::Usb(l) => self.usb_geraete(l),
        }
    }

    fn usb_geraete(&mut self, liste: Vec<usb::Geraet>) {
        for g in liste {
            if usb::eingebaut(&g) {
                let _ = usb::zulassen(&g.nr);
                continue;
            }
            let tastatur = g.arten.contains(&"Tastatur/Maus");
            let speicher = g.arten.contains(&"Speicher");
            let art = if g.arten.is_empty() { "USB-Gerät".to_string() } else { g.arten.join(" + ") };
            let name = if g.name.is_empty() { g.kennung.clone() } else { g.name.clone() };
            let (stufe, text) = if tastatur && speicher {
                ("hoch", format!("„{}“ ist ein Speicher, gibt sich aber zusätzlich als Tastatur aus – typisch für Angriffs-Sticks, die heimlich Befehle eintippen. Nur zulassen, wenn du ganz sicher bist.", name))
            } else if tastatur {
                ("mittel", format!("„{}“ meldet sich als {}. Nur zulassen, wenn du es gerade selbst angesteckt hast.", name, art))
            } else {
                ("mittel", format!("„{}“ ({}) ist gesperrt, bis du es zulässt.", name, art))
            };
            let e = Ereignis::neu("usb", stufe, format!("Neues USB-Gerät: {}", name), text)
                .knopf("zulassen", "Zulassen")
                .knopf("ignorieren", "Gesperrt lassen")
                .datum("nr", &g.nr)
                .datum("kennung", &g.kennung)
                .schluessel(format!("usb:{}:{}", g.nr, g.kennung));
            self.melden(e);
        }
    }

    // ── Schreib-Wache: Scanner + Erpresser-Schild ──
    fn schreib_ereignisse(&mut self) {
        let mut buf = vec![0u8; 16 * 1024];
        loop {
            let n = unsafe { sys::read(self.schreib_fd, buf.as_mut_ptr() as *mut std::ffi::c_void, buf.len()) };
            if n <= 0 {
                break;
            }
            let n = n as usize;
            let mut off = 0;
            while off + sys::FAN_META <= n {
                let m: sys::FanMeta = unsafe { std::ptr::read_unaligned(buf.as_ptr().add(off) as *const sys::FanMeta) };
                if (m.event_len as usize) < sys::FAN_META {
                    break;
                }
                off += m.event_len as usize;
                if m.fd < 0 {
                    continue;
                }
                let datei = unsafe { File::from_raw_fd(m.fd) };
                self.geschrieben(datei, m.pid);
            }
        }
    }

    fn geschrieben(&mut self, datei: File, pid: i32) {
        if pid == self.eigene_pid {
            return;
        }
        let Some(pfad) = sys::fd_pfad(datei.as_raw_fd()) else { return };
        if !wache::beobachteter_ort(&pfad) {
            return;
        }
        let Ok(meta) = datei.metadata() else { return };
        if !meta.is_file() || meta.len() == 0 {
            return;
        }
        let prozess_uid = sys::uid_von(pid);
        let uid = prozess_uid.unwrap_or(meta.uid());
        let mut kopf = vec![0u8; 4096];
        let n = datei.read_at(&mut kopf, 0).unwrap_or(0);
        kopf.truncate(n);
        // Erpresser-Schild: eine schon länger vorhandene Datei wurde mit Zufallsdaten überschrieben
        if uid >= 1000 && prozess_uid.is_some() && n >= 1024 {
            let alt = meta.created().ok().and_then(|t| t.elapsed().ok()).map(|d| d.as_secs() > 120).unwrap_or(false);
            if alt && wache::entropie(&kopf) > 7.5 {
                if let Some(anzahl) = self.erpresser.beobachten(pid, meta.ino()) {
                    self.vorfall(pid, uid, anzahl, &pfad);
                }
            }
        }
        // Echtzeit-Scanner
        let ausfuehrbar = meta.permissions().mode() & 0o111 != 0;
        if meta.len() <= 100 * 1024 * 1024 {
            if let Some(art) = scanner::art_von(&pfad, &kopf, ausfuehrbar) {
                if let Some(a) = &self.auftraege {
                    match a.try_send(scanner::Auftrag { datei, pfad, uid, art }) {
                        Ok(()) => {}
                        Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => {
                            self.scan.uebersprungen += 1;
                            self.geaendert = true;
                        }
                    }
                }
            }
        }
    }

    fn vorfall(&mut self, pid: i32, uid: u32, anzahl: usize, beispiel: &str) {
        let name = sys::name_von(pid);
        let programm = sys::programm_von(pid).unwrap_or_default();
        let datei_name = beispiel.rsplit('/').next().unwrap_or(beispiel);
        let mut e = Ereignis::neu(
            "erpresser",
            "hoch",
            format!("Verdächtiges Verschlüsseln gestoppt: „{}“", name),
            format!(
                "„{}“ hat in wenigen Sekunden {} deiner Dateien mit unlesbarem Inhalt überschrieben (zuletzt „{}“). So arbeiten Erpresser-Viren. Das Programm ist eingefroren und kann nichts mehr verändern.",
                name, anzahl, datei_name
            ),
        )
        .knopf("beenden", "Beenden")
        .knopf("fortsetzen", "War ich – fortsetzen")
        .knopf("tresor", "Im Tresor retten")
        .fuer(uid)
        .datum("programm", programm)
        .schluessel(format!("erpresser:{}", pid));
        match self.gefrierfach.as_mut().map(|g| g.einfrieren(pid)) {
            Some(Ok((fach, pids))) => {
                e = e.datum("fach", fach).datum("pids", pids.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(" "));
            }
            _ => {
                unsafe { sys::kill(pid, sys::SIGSTOP) };
                e = e.datum("pids", pid.to_string());
                e.text.push_str(" (Notlösung: angehalten)");
            }
        }
        self.melden(e);
        self.status_schreiben(true);
    }

    // ── Aktionen auf Knopfdruck ──
    fn aktion(&mut self, id: &str, aktion: &str, wer: u32) -> Result<String, String> {
        let Some(i) = self.ereignisse.iter().position(|e| e.id == id) else { return Err("Unbekanntes Ereignis".into()) };
        let e = self.ereignisse[i].clone();
        if !e.erledigt.is_empty() {
            return Err(format!("Schon erledigt: {}", e.erledigt));
        }
        if e.uid != 0 && wer != 0 && e.uid != wer {
            return Err("Das gehört einem anderen Benutzer.".into());
        }
        if !e.knoepfe.iter().any(|(a, _)| a == aktion) {
            return Err("Diese Aktion gibt es hier nicht.".into());
        }
        let ergebnis: Result<String, String> = match (e.art.as_str(), aktion) {
            ("usb", "zulassen") => usb::zulassen(&e.wert("nr")),
            ("start", "freigeben") => self.freigeben(&e),
            ("verdacht", "einsperren") => self.q.einsperren(&e.wert("pfad"), e.uid, &e.wert("grund")).map(|_| "In Quarantäne".to_string()),
            ("autostart", "behalten") => self.autostart.behalten(&e.wert("pfad")),
            ("autostart", "entfernen") => {
                let p = e.wert("pfad");
                let r = self.q.einsperren(&p, e.uid, "Autostart entfernt").map(|_| "Entfernt (liegt in der Quarantäne)".to_string());
                if r.is_ok() {
                    self.autostart.vergessen(&p);
                }
                r
            }
            ("autostart", "zurueck") => self.autostart.zuruecksetzen(&e.wert("pfad")),
            ("erpresser", "beenden") => self.erpresser_aktion(&e, true),
            ("erpresser", "fortsetzen") => self.erpresser_aktion(&e, false),
            (_, "ignorieren") => Ok("Bleibt gesperrt".into()),
            (_, "behalten") => Ok("Behalten".into()),
            (_, "ok") => Ok("Verstanden".into()),
            _ => Err("Unbekannte Aktion".into()),
        };
        if let Ok(t) = &ergebnis {
            self.ereignisse[i].erledigt = t.clone();
            self.speichern();
            self.geaendert = true;
        }
        ergebnis
    }

    fn freigeben(&mut self, e: &Ereignis) -> Result<String, String> {
        let st = e.wert("schluessel");
        let s = wache::schluessel_lesen(&st).ok_or("Ungültige Freigabe")?;
        self.freigaben.write().unwrap_or_else(|e| e.into_inner()).insert(s);
        self.freigabe_liste.retain(|(x, _, _)| *x != st);
        self.freigabe_liste.push((st, e.wert("pfad"), datei::jetzt_ms()));
        self.freigaben_speichern();
        Ok("Freigegeben – starte es jetzt noch einmal".into())
    }

    fn freigabe_entfernen(&mut self, st: &str) -> Result<String, String> {
        let s = wache::schluessel_lesen(st).ok_or("Ungültige Freigabe")?;
        self.freigaben.write().unwrap_or_else(|e| e.into_inner()).remove(&s);
        self.freigabe_liste.retain(|(x, _, _)| x != st);
        self.freigaben_speichern();
        self.geaendert = true;
        Ok("Freigabe entfernt".into())
    }

    fn erpresser_aktion(&mut self, e: &Ereignis, beenden: bool) -> Result<String, String> {
        let fach = e.wert("fach");
        if !fach.is_empty() {
            let g = self.gefrierfach.as_ref().ok_or("Gefrierfach fehlt")?;
            return if beenden { g.beenden(&fach) } else { g.fortsetzen(&fach) };
        }
        for p in e.wert("pids").split_whitespace().filter_map(|p| p.parse::<i32>().ok()) {
            unsafe { sys::kill(p, if beenden { sys::SIGKILL } else { sys::SIGCONT }) };
        }
        Ok(if beenden { "Beendet" } else { "Läuft weiter" }.into())
    }

    // ── Steuerung über den Socket ──
    fn kunde(&mut self, s: UnixStream) {
        let _ = s.set_nonblocking(false);
        let _ = s.set_read_timeout(Some(Duration::from_secs(2)));
        let _ = s.set_write_timeout(Some(Duration::from_secs(2)));
        let Some((pid, uid)) = sys::gegenueber(s.as_raw_fd()) else { return };
        if uid != 0 && !(1000..60000).contains(&uid) {
            return;
        }
        let mut zeile = String::new();
        if BufReader::new((&s).take(4096)).read_line(&mut zeile).is_err() {
            return;
        }
        let teile: Vec<&str> = zeile.trim_end_matches(['\n', '\r']).split('\t').collect();
        // Entscheidungen nur aus der Auriliux-Oberfläche (nicht von irgendeinem Programm des Benutzers)
        let vertraut = uid == 0 || sys::programm_von(pid).map(|p| p == SHELL).unwrap_or(false);
        let antwort = match teile.as_slice() {
            ["status"] => self.status_text(),
            ["pruefen"] => {
                self.pruefung_starten();
                antwort_ok("Prüfung läuft")
            }
            _ if !vertraut => antwort_fehler("Nur die Auriliux-Oberfläche darf das."),
            ["aktion", id, aktion] => match self.aktion(id, aktion, uid) {
                Ok(t) => antwort_ok(&t),
                Err(f) => antwort_fehler(&f),
            },
            ["quarantaene", id, was] => {
                let r = match *was {
                    "zurueckholen" => self.q.zurueckholen(id, uid),
                    "loeschen" => self.q.loeschen(id, uid),
                    _ => Err("Unbekannt".into()),
                };
                self.geaendert = true;
                match r {
                    Ok(t) => antwort_ok(&t),
                    Err(f) => antwort_fehler(&f),
                }
            }
            ["freigabe-weg", st] => match self.freigabe_entfernen(st) {
                Ok(t) => antwort_ok(&t),
                Err(f) => antwort_fehler(&f),
            },
            _ => antwort_fehler("Unbekannter Befehl"),
        };
        let _ = (&s).write_all(antwort.as_bytes());
        let _ = (&s).write_all(b"\n");
        self.status_schreiben(true);
    }

    fn usb_wache_setzen(&mut self) {
        if self.usb_fd < 0 {
            return;
        }
        let maske = sys::IN_CREATE | sys::IN_DELETE;
        sys::beobachten(self.usb_fd, "/dev/bus/usb", maske);
        if let Ok(d) = fs::read_dir("/dev/bus/usb") {
            for e in d.flatten() {
                sys::beobachten(self.usb_fd, &e.path().to_string_lossy(), maske);
            }
        }
    }

    fn beispiele(&mut self) {
        // für die Vorschau-Bilder: echte Abläufe mit harmlosen Testdaten
        let _ = fs::create_dir_all("/tmp/beispiel");
        let eicar = "/tmp/beispiel/rechnung-november.pdf.sh";
        let _ = fs::write(eicar, "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*\n");
        let grund = scanner::eigene_regeln("rechnung-november.pdf.sh", &datei::lies(eicar).to_lowercase()).map(|r| r.1).unwrap_or_default();
        match self.q.einsperren(eicar, 1000, &grund) {
            Ok(q) => {
                let e = Ereignis::neu("fund", "hoch", "Schädling in Quarantäne: rechnung-november.pdf.sh", format!("{}. Gefunden in Downloads. Die Datei ist weggesperrt und kann nichts mehr anrichten.", grund))
                    .knopf("ok", "Verstanden").datum("q", q.id).fuer(1000);
                self.melden(e);
            }
            Err(f) => eprintln!("Beispiel-Quarantäne: {}", f),
        }
        if let Some(g) = usb::zeile_lesen(r#"7: block id 0781:5583 serial "4C53" name "SanDisk Ultra Fit" with-interface { 08:06:50 03:01:01 } with-connect-type "hotplug""#) {
            self.usb_geraete(vec![g]);
        }
        let e = Ereignis::neu("start", "mittel", "Start verhindert: Digsoin-Office.AppImage",
            "„bash“ wollte ein Programm aus /var/home/nutzer/Downloads starten. Programme aus Benutzerordnern, Downloads und von USB-Sticks laufen nur mit deiner Freigabe. Nur freigeben, wenn du es kennst.")
            .knopf("freigeben", "Freigeben").knopf("ignorieren", "Gesperrt lassen").fuer(1000).datum("schluessel", "1:2:3:4:5");
        self.melden(e);
        let v = scanner::eigene_regeln("install.sh", "curl -fssl https://example.org/install | sh").map(|r| r.1).unwrap_or_default();
        let e = Ereignis::neu("verdacht", "mittel", "Verdächtige Datei: install.sh", format!("{}. Liegt in Downloads. Wenn du sie nicht selbst geladen hast: in Quarantäne.", v))
            .knopf("einsperren", "In Quarantäne").knopf("behalten", "Behalten").fuer(1000);
        self.melden(e);
    }
}

fn arg_nach(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1).cloned())
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let einmal = args.iter().any(|a| a == "--einmal");
    if unsafe { sys::geteuid() } != 0 {
        eprintln!("Guardian muss als root laufen.");
        std::process::exit(1);
    }
    let _ = fs::create_dir_all(DATEN);
    let _ = fs::set_permissions(DATEN, fs::Permissions::from_mode(0o700));
    let status_pfad = arg_nach(&args, "--ausgabe").unwrap_or_else(|| format!("{}/status.json", LAUFZEIT));
    if let Some(o) = std::path::Path::new(&status_pfad).parent() {
        let _ = fs::create_dir_all(o);
    }
    let (tx, rx) = mpsc::channel();
    let mut g = Guardian::neu(tx.clone(), rx, status_pfad);

    if einmal {
        g.lage_aktualisieren();
        g.lage.ausfuehrung = Some("nur Probelauf".into());
        g.lage.schreibwache = Some("nur Probelauf".into());
        let (schilde, ereignisse, usb, _) = schilde::pruefen(&g.lage);
        g.schilde = schilde;
        for e in ereignisse {
            g.melden(e);
        }
        g.usb_geraete(usb);
        if args.iter().any(|a| a == "--beispiel") {
            g.beispiele();
        }
        g.geaendert = true;
        g.status_schreiben(true);
        println!("{}", g.status_text());
        return;
    }

    sys::signale_abfangen();
    g.gefrierfach = wache::Gefrierfach::einrichten();
    if g.gefrierfach.is_none() {
        eprintln!("Guardian: kein eigenes Gefrierfach (läuft nicht unter systemd mit Delegate=yes) – Notlösung SIGSTOP");
    }

    // Ausführungs-Schild
    match wache::ausfuehrung_starten(g.freigaben.clone(), tx.clone()) {
        Ok(fd) => g.exec_fd = fd,
        Err(f) => g.lage.ausfuehrung = Some(f),
    }
    // Schreib-Wache
    let fd = unsafe { sys::fanotify_init(sys::FAN_CLASS_NOTIF | sys::FAN_CLOEXEC | sys::FAN_NONBLOCK, sys::O_LARGEFILE | sys::O_CLOEXEC) };
    if fd >= 0 {
        g.schreib_fd = fd;
    } else {
        g.lage.schreibwache = Some(format!("fanotify nicht verfügbar (Fehler {})", sys::fehlernummer()));
    }
    let (atx, arx) = mpsc::sync_channel::<scanner::Auftrag>(200);
    g.auftraege = Some(atx);
    scanner::starten(arx, tx.clone(), g.q.clone());
    g.markierer.aktualisieren(g.exec_fd, g.schreib_fd);
    g.autostart.beobachten();
    g.usb_fd = unsafe { sys::inotify_init1(sys::IN_NONBLOCK | sys::IN_CLOEXEC) };
    g.usb_wache_setzen();
    g.lage.einrichten = true;

    // Steuerung
    let sock = format!("{}/steuerung.sock", LAUFZEIT);
    let _ = fs::remove_file(&sock);
    let hoerer = match UnixListener::bind(&sock) {
        Ok(h) => {
            let _ = fs::set_permissions(&sock, fs::Permissions::from_mode(0o666));
            let _ = h.set_nonblocking(true);
            Some(h)
        }
        Err(e) => {
            eprintln!("Guardian: Steuerung nicht verfügbar: {}", e);
            None
        }
    };
    let mut einhaengungen = File::open("/proc/self/mounts").ok();
    let mut aufraeumen = Instant::now();
    eprintln!("Guardian läuft (Ausführungs-Schild: {}, Schreib-Wache: {})", g.exec_fd >= 0, g.schreib_fd >= 0);

    while !sys::ende() {
        let mut fds: Vec<sys::PollFd> = Vec::new();
        let mut rollen: Vec<u8> = Vec::new();
        if let Some(h) = &hoerer {
            fds.push(sys::PollFd { fd: h.as_raw_fd(), events: sys::POLLIN, revents: 0 });
            rollen.push(1);
        }
        if g.schreib_fd >= 0 {
            fds.push(sys::PollFd { fd: g.schreib_fd, events: sys::POLLIN, revents: 0 });
            rollen.push(2);
        }
        if g.autostart.fd >= 0 {
            fds.push(sys::PollFd { fd: g.autostart.fd, events: sys::POLLIN, revents: 0 });
            rollen.push(3);
        }
        if g.usb_fd >= 0 {
            fds.push(sys::PollFd { fd: g.usb_fd, events: sys::POLLIN, revents: 0 });
            rollen.push(4);
        }
        if let Some(f) = &einhaengungen {
            fds.push(sys::PollFd { fd: f.as_raw_fd(), events: sys::POLLPRI, revents: 0 });
            rollen.push(5);
        }
        sys::warte(&mut fds, 250);
        for (i, p) in fds.iter().enumerate() {
            if p.revents == 0 {
                continue;
            }
            match rollen[i] {
                1 => {
                    if let Some(h) = &hoerer {
                        while let Ok((s, _)) = h.accept() {
                            g.kunde(s);
                        }
                    }
                }
                2 => g.schreib_ereignisse(),
                3 => g.autostart.lesen(),
                4 => {
                    let neu = sys::inotify_lesen(g.usb_fd);
                    if neu.iter().any(|(_, m, _)| m & sys::IN_ISDIR != 0) {
                        g.usb_wache_setzen();
                    }
                    if neu.iter().any(|(_, m, _)| m & sys::IN_CREATE != 0) {
                        g.usb_faellig = Some(Instant::now() + Duration::from_millis(800));
                    }
                }
                5 => {
                    if let Some(f) = einhaengungen.as_mut() {
                        let mut t = String::new();
                        let _ = f.seek(SeekFrom::Start(0));
                        let _ = f.read_to_string(&mut t);
                    }
                    g.markierer.aktualisieren(g.exec_fd, g.schreib_fd);
                }
                _ => {}
            }
        }
        while let Ok(m) = g.rx.try_recv() {
            g.verarbeiten(m);
        }
        let jetzt = Instant::now();
        if jetzt >= g.naechste_pruefung {
            g.pruefung_starten();
        }
        if g.autostart.faellig.map(|t| jetzt >= t).unwrap_or(false) {
            for e in g.autostart.vergleichen() {
                g.melden(e);
            }
        }
        if g.usb_faellig.map(|t| jetzt >= t).unwrap_or(false) {
            g.usb_faellig = None;
            let tx = g.tx.clone();
            let _ = std::thread::Builder::new().name("usb".into()).spawn(move || {
                let _ = tx.send(Meldung::Usb(usb::gesperrte()));
            });
        }
        if aufraeumen.elapsed() > Duration::from_secs(60) {
            aufraeumen = jetzt;
            g.erpresser.aufraeumen();
            if let Some(f) = &g.gefrierfach {
                f.aufraeumen();
            }
            g.markierer.aktualisieren(g.exec_fd, g.schreib_fd);
        }
        g.status_schreiben(false);
    }
    let _ = fs::remove_file(&sock);
    eprintln!("Guardian beendet");
}
