//! Autostart-Wächter: merkt sich alle Stellen, über die sich Programme beim Start mitladen
//! (Autostart-Ordner, systemd-Dienste, Startdateien wie .bashrc, cron …) und meldet jede Änderung.
use crate::{Ereignis, DATEN};
use gemeinsam::datei;
use gemeinsam::sys;
use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::{Duration, Instant};

const SYSTEM_ORDNER: [&str; 9] = [
    "/etc/xdg/autostart", "/etc/systemd/system", "/etc/systemd/user", "/etc/xdg/labwc", "/etc/cron.d",
    "/etc/profile.d", "/etc/udev/rules.d", "/etc/modules-load.d", "/etc/environment.d",
];
const SYSTEM_DATEIEN: [&str; 4] = ["ld.so.preload", "crontab", "rc.local", "environment"];
const BENUTZER_ORDNER: [&str; 4] = [".config/autostart", ".config/systemd/user", ".config/labwc", ".config/environment.d"];
const BENUTZER_DATEIEN: [&str; 7] = [".bashrc", ".bash_profile", ".bash_login", ".profile", ".zshrc", ".xprofile", ".pam_environment"];

#[derive(Clone, PartialEq)]
struct Stand {
    wert: String,
    uid: u32,
}

pub struct Wache {
    pub fd: i32,
    ordner: HashMap<i32, (String, bool)>, // wd → (Ort, nur bestimmte Dateien?)
    basis: HashMap<String, Stand>,
    pub faellig: Option<Instant>,
}

fn basis_datei() -> String {
    format!("{}/autostart-basis.tsv", DATEN)
}
fn kopie_von(pfad: &str) -> String {
    format!("{}/kopien/{:016x}", DATEN, datei::fingerabdruck(pfad.as_bytes()))
}

/// Inhalt-Fingerabdruck (Verweise: Ziel)
fn wert_von(pfad: &str) -> Option<(String, u32)> {
    let m = fs::symlink_metadata(pfad).ok()?;
    if m.file_type().is_symlink() {
        let ziel = fs::read_link(pfad).ok()?;
        return Some((format!("->{}", ziel.to_string_lossy()), m.uid()));
    }
    if !m.is_file() {
        return None;
    }
    if m.len() <= 512 * 1024 {
        let d = fs::read(pfad).ok()?;
        return Some((format!("#{:016x}", datei::fingerabdruck(&d)), m.uid()));
    }
    Some((format!("{}:{}", m.len(), m.mtime()), m.uid()))
}

fn ist_systemd(ort: &str) -> bool {
    ort.contains("/systemd/")
}

impl Wache {
    pub fn neu() -> Wache {
        let fd = unsafe { sys::inotify_init1(sys::IN_NONBLOCK | sys::IN_CLOEXEC) };
        let mut basis = HashMap::new();
        for z in datei::lies(basis_datei()).lines() {
            let f: Vec<&str> = z.splitn(3, '\t').collect();
            if f.len() == 3 {
                basis.insert(f[2].to_string(), Stand { wert: f[0].to_string(), uid: f[1].parse().unwrap_or(0) });
            }
        }
        let _ = fs::create_dir_all(format!("{}/kopien", DATEN));
        Wache { fd, ordner: HashMap::new(), basis, faellig: Some(Instant::now()) }
    }

    pub fn anzahl(&self) -> usize {
        self.basis.len()
    }

    fn speichern(&self) {
        let mut t = String::new();
        for (p, s) in &self.basis {
            t.push_str(&format!("{}\t{}\t{}\n", s.wert, s.uid, p));
        }
        let _ = datei::schreiben(&basis_datei(), t.as_bytes(), 0o600);
    }

    /// alle Orte: (Ordner, nur diese Namen)
    fn orte() -> Vec<(String, Option<Vec<&'static str>>)> {
        let mut o: Vec<(String, Option<Vec<&'static str>>)> = SYSTEM_ORDNER.iter().map(|s| (s.to_string(), None)).collect();
        o.push(("/etc".into(), Some(SYSTEM_DATEIEN.to_vec())));
        for b in sys::benutzer() {
            for d in BENUTZER_ORDNER {
                o.push((format!("{}/{}", b.heim, d), None));
            }
            o.push((b.heim.clone(), Some(BENUTZER_DATEIEN.to_vec())));
        }
        o
    }

    /// Wachen setzen (auch für Ordner, die es inzwischen erst gibt)
    pub fn beobachten(&mut self) {
        if self.fd < 0 {
            return;
        }
        let maske = sys::IN_CLOSE_WRITE | sys::IN_MOVED_TO | sys::IN_MOVED_FROM | sys::IN_CREATE | sys::IN_DELETE | sys::IN_ATTRIB | sys::IN_ONLYDIR;
        let mut neu: Vec<(String, bool)> = Vec::new();
        for (ort, nur) in Wache::orte() {
            if !Path::new(&ort).is_dir() {
                continue;
            }
            neu.push((ort.clone(), nur.is_some()));
            if ist_systemd(&ort) {
                if let Ok(d) = fs::read_dir(&ort) {
                    for e in d.flatten() {
                        if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                            neu.push((e.path().to_string_lossy().into_owned(), false));
                        }
                    }
                }
            }
        }
        for (ort, nur) in neu {
            let wd = sys::beobachten(self.fd, &ort, maske);
            if wd >= 0 {
                self.ordner.insert(wd, (ort, nur));
            }
        }
    }

    /// inotify-Meldungen lesen → in 1,5 s neu vergleichen
    pub fn lesen(&mut self) {
        for (wd, maske, name) in sys::inotify_lesen(self.fd) {
            let Some((ort, nur)) = self.ordner.get(&wd) else { continue };
            if *nur {
                let erlaubt: &[&str] = if ort == "/etc" { &SYSTEM_DATEIEN } else { &BENUTZER_DATEIEN };
                if !erlaubt.contains(&name.as_str()) {
                    continue;
                }
            }
            if maske & sys::IN_ISDIR != 0 && maske & sys::IN_CREATE != 0 {
                self.faellig = Some(Instant::now() + Duration::from_millis(300));
            }
            self.faellig = Some(Instant::now() + Duration::from_millis(1500));
        }
    }

    fn aufnehmen() -> HashMap<String, Stand> {
        let mut aus = HashMap::new();
        for (ort, nur) in Wache::orte() {
            if let Some(namen) = nur {
                for n in namen {
                    let p = format!("{}/{}", ort, n);
                    if let Some((w, uid)) = wert_von(&p) {
                        aus.insert(p, Stand { wert: w, uid });
                    }
                }
                continue;
            }
            let Ok(d) = fs::read_dir(&ort) else { continue };
            for e in d.flatten() {
                let p = e.path().to_string_lossy().into_owned();
                let ist_ordner = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                if ist_ordner && ist_systemd(&ort) {
                    if let Ok(u) = fs::read_dir(&p) {
                        for f in u.flatten() {
                            let q = f.path().to_string_lossy().into_owned();
                            if let Some((w, uid)) = wert_von(&q) {
                                aus.insert(q, Stand { wert: w, uid });
                            }
                        }
                    }
                } else if let Some((w, uid)) = wert_von(&p) {
                    aus.insert(p, Stand { wert: w, uid });
                }
            }
        }
        aus
    }

    /// stammt die Datei unverändert aus dem Systemabbild? (/usr/etc enthält die Auslieferungs-Fassung von /etc)
    fn aus_dem_abbild(pfad: &str, s: &Stand) -> bool {
        if !pfad.starts_with("/etc/") {
            return false;
        }
        match wert_von(&format!("/usr{}", pfad)) {
            Some((w, _)) => w == s.wert,
            None => false,
        }
    }

    fn kopie_anlegen(pfad: &str) {
        if let Ok(m) = fs::symlink_metadata(pfad) {
            if m.is_file() && m.len() <= 512 * 1024 {
                let _ = fs::copy(pfad, kopie_von(pfad));
            }
        }
    }

    /// vergleichen: neue/geänderte Einträge werden gemeldet (bis du entscheidest), entfernte vergessen
    pub fn vergleichen(&mut self) -> Vec<Ereignis> {
        self.faellig = None;
        self.beobachten();
        let jetzt = Wache::aufnehmen();
        let mut aus = Vec::new();
        if self.basis.is_empty() {
            // allererster Start: alles, was es jetzt gibt, gilt als bekannt
            for p in jetzt.keys() {
                Wache::kopie_anlegen(p);
            }
            self.basis = jetzt;
            self.speichern();
            return aus;
        }
        let mut geaendert = false;
        for (p, s) in &jetzt {
            let alt = self.basis.get(p).cloned();
            if alt.as_ref() == Some(s) {
                continue;
            }
            if Wache::aus_dem_abbild(p, s) {
                self.basis.insert(p.clone(), s.clone());
                geaendert = true;
                continue;
            }
            aus.push(Wache::ereignis(p, s, alt.is_some()));
        }
        let weg: Vec<String> = self.basis.keys().filter(|p| !jetzt.contains_key(*p)).cloned().collect();
        for p in weg {
            self.basis.remove(&p);
            geaendert = true;
        }
        if geaendert {
            self.speichern();
        }
        aus
    }

    fn anzeigename(pfad: &str) -> String {
        let datei = pfad.rsplit('/').next().unwrap_or(pfad).to_string();
        if pfad.ends_with(".desktop") {
            for z in datei::lies(pfad).lines() {
                if let Some(n) = z.strip_prefix("Name=") {
                    return n.trim().to_string();
                }
            }
        }
        datei
    }

    fn ereignis(pfad: &str, s: &Stand, geaendert: bool) -> Ereignis {
        let name = Wache::anzeigename(pfad);
        let system = pfad.starts_with("/etc/");
        let startdatei = BENUTZER_DATEIEN.iter().any(|d| pfad.ends_with(&format!("/{}", d))) || (system && SYSTEM_DATEIEN.iter().any(|d| pfad == format!("/etc/{}", d)));
        let wo = if system { "für alle Benutzer" } else { "nur für dich" };
        let stufe = if system { "hoch" } else { "mittel" };
        let mut e = if startdatei && geaendert {
            Ereignis::neu("autostart", stufe, format!("Startdatei verändert: {}", name),
                format!("{} wird bei jedem Start gelesen ({}). Wenn du sie nicht selbst geändert hast, mach es rückgängig.", pfad, wo))
        } else if geaendert {
            Ereignis::neu("autostart", stufe, format!("Autostart verändert: „{}“", name),
                format!("{} startet automatisch ({}) und wurde verändert.", pfad, wo))
        } else {
            Ereignis::neu("autostart", stufe, format!("Neuer Autostart: „{}“", name),
                format!("{} will bei jedem Start mitladen ({}). So nisten sich Schädlinge ein – wenn du das nicht selbst eingerichtet hast: entfernen.", pfad, wo))
        };
        e = e.knopf("behalten", "Behalten");
        if geaendert && Path::new(&kopie_von(pfad)).exists() {
            e = e.knopf("zurueck", "Rückgängig machen");
        } else {
            e = e.knopf("entfernen", "Entfernen");
        }
        e.datum("pfad", pfad).fuer(if system { 0 } else { s.uid }).schluessel(format!("autostart:{}:{}", pfad, s.wert))
    }

    pub fn behalten(&mut self, pfad: &str) -> Result<String, String> {
        match wert_von(pfad) {
            Some((w, uid)) => {
                self.basis.insert(pfad.to_string(), Stand { wert: w, uid });
                Wache::kopie_anlegen(pfad);
            }
            None => {
                self.basis.remove(pfad);
            }
        }
        self.speichern();
        Ok("Behalten".into())
    }

    pub fn vergessen(&mut self, pfad: &str) {
        self.basis.remove(pfad);
        self.speichern();
    }

    pub fn zuruecksetzen(&mut self, pfad: &str) -> Result<String, String> {
        let k = kopie_von(pfad);
        let inhalt = fs::read(&k).map_err(|_| "Keine frühere Fassung gespeichert".to_string())?;
        fs::write(pfad, inhalt).map_err(|e| format!("Zurücksetzen fehlgeschlagen: {}", e))?;
        self.behalten(pfad)?;
        Ok("Frühere Fassung wiederhergestellt".into())
    }
}
