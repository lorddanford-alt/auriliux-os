//! Tresor – Sicherung deiner Dateien.
//!   · stündliche Schnappschüsse von /var/home (btrfs, schreibgeschützt, nur für root lesbar)
//!   · verschlüsselte Sicherung auf die Festplatte „AURILIUX“, sobald sie angeschlossen ist (restic)
//!   · Zurückholen einzelner Dateien und Ordner – nur nach dem Drehcode (Zahlenschloss)
//! Steuerung: /run/auriliux/tresor/steuerung.sock (eine Zeile, Teile mit Tab getrennt, Antwort JSON)
//! Sonderaufrufe: --vorbereiten (beim Hochfahren), --schnappschuss, --einmal (Status ausgeben)
mod schloss;
mod schnappschuss;
mod sicherung;

use gemeinsam::datei;
use gemeinsam::json::J;
use gemeinsam::sys;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const SHELL: &str = "/usr/bin/auriliux-shell";

struct Gemeinsam {
    daten: String,
    ablage: String,
    orte: schnappschuss::Orte,
    schloss: schloss::Schloss,
    letzter: i64,
    fehler: String,
}

#[derive(Clone)]
struct Dienst {
    g: Arc<Mutex<Gemeinsam>>,
    sz: Arc<Mutex<sicherung::Zustand>>,
    frei: Arc<Mutex<()>>,
}

fn ok(felder: Vec<(&str, J)>) -> String {
    let mut f = vec![("ok", J::B(true))];
    f.extend(felder);
    J::o(f).text()
}
fn fehler(t: &str) -> String {
    J::o(vec![("ok", J::B(false)), ("fehler", J::t(t))]).text()
}

/// relativer Pfad im Benutzerordner, ohne „..“ und Ähnliches
fn sauber(p: &str) -> Option<String> {
    if p.contains('\0') || p.starts_with('/') {
        return None;
    }
    let teile: Vec<&str> = p.split('/').filter(|t| !t.is_empty()).collect();
    if teile.iter().any(|t| *t == "." || *t == "..") {
        return None;
    }
    Some(teile.join("/"))
}

/// Name eines neuen Ordners im Benutzerordner (z. B. „Gerettet 27.11.2026 14-00“)
fn ordnername_ok(n: &str) -> bool {
    !n.is_empty() && n.chars().count() <= 120 && !n.contains('/') && !n.contains('\0') && !n.starts_with('.')
}

fn ist_id(t: &str) -> bool {
    !t.is_empty() && t.len() <= 64 && t.chars().all(|c| c.is_ascii_hexdigit())
}

impl Dienst {
    /// Name des Benutzerordners (z. B. „danny“ für /var/home/danny), nur wenn er wirklich unter /var/home liegt
    fn heim_name(&self, uid: u32) -> Option<(String, u32)> {
        let b = sys::benutzer().into_iter().find(|b| b.uid == uid)?;
        let echt = fs::canonicalize(&b.heim).ok()?;
        let heim = fs::canonicalize(&self.g.lock().unwrap().orte.heim).ok()?;
        if echt.parent()? != heim {
            return None;
        }
        Some((echt.file_name()?.to_string_lossy().into_owned(), b.gid))
    }

    fn status(&self) -> J {
        let g = self.g.lock().unwrap();
        let sz = self.sz.lock().unwrap().clone();
        let hindernis = schnappschuss::hindernis(&g.orte);
        let lw = sicherung::laufwerk();
        let liste = schnappschuss::liste(&g.orte);
        J::o(vec![
            ("schnappschuesse", J::o(vec![
                ("moeglich", J::B(hindernis.is_empty())),
                ("grund", J::t(hindernis)),
                ("anzahl", J::I(liste.len() as i64)),
                ("letzter", J::I(liste.last().copied().unwrap_or(0) * 1000)),
                ("fehler", J::t(g.fehler.clone())),
            ])),
            ("sicherung", J::o(vec![
                ("laufwerk", J::B(!lw.is_empty())),
                ("eingerichtet", J::B(!lw.is_empty() && Path::new(&format!("{}/config", sicherung::ablage(&lw))).exists())),
                ("laeuft", J::B(sz.laeuft)),
                ("prozent", J::Z(sz.prozent)),
                ("letzte", J::I(sz.letzte)),
                ("ergebnis", J::t(sz.ergebnis)),
                ("anzahl", J::I(sz.anzahl)),
            ])),
            ("code", J::o(vec![("gesetzt", J::B(g.schloss.gesetzt())), ("gesperrtBis", J::I(g.schloss.gesperrt_bis()))])),
        ])
    }

    fn sichern_starten(&self) -> bool {
        if self.sz.lock().unwrap().laeuft || self.frei.try_lock().is_err() {
            return false;
        }
        let (daten, heim) = {
            let g = self.g.lock().unwrap();
            (g.daten.clone(), g.orte.heim.clone())
        };
        let (sz, frei) = (self.sz.clone(), self.frei.clone());
        std::thread::spawn(move || sicherung::sichern(&daten, &heim, &sz, &frei));
        true
    }

    fn karte(&self, karte: &str, uid: u32) -> bool {
        self.g.lock().unwrap().schloss.karte_gilt(karte, uid)
    }

    fn liste(&self) -> String {
        let (orte_liste, daten) = {
            let g = self.g.lock().unwrap();
            (schnappschuss::liste(&g.orte), g.daten.clone())
        };
        let mut l: Vec<J> = orte_liste.iter().rev()
            .map(|s| J::o(vec![("quelle", J::t("s")), ("id", J::t(s.to_string())), ("zeit", J::I(s * 1000))]))
            .collect();
        let mut hinweis = String::new();
        if !sicherung::laufwerk().is_empty() {
            match self.frei.try_lock() {
                Ok(_f) => match sicherung::liste(&daten) {
                    Ok(a) => l.extend(a.iter().rev().map(|(id, s)| J::o(vec![("quelle", J::t("a")), ("id", J::t(id.clone())), ("zeit", J::I(s * 1000))]))),
                    Err(e) => hinweis = format!("Festplatte: {}", e),
                },
                Err(_) => hinweis = "Die Sicherung läuft gerade – die Stände auf der Festplatte erscheinen danach.".into(),
            }
        }
        ok(vec![("eintraege", J::L(l)), ("hinweis", J::t(hinweis))])
    }

    fn ordner(&self, uid: u32, quelle: &str, id: &str, pfad: &str) -> String {
        let (Some((name, _)), Some(rel)) = (self.heim_name(uid), sauber(pfad)) else { return fehler("Ungültiger Ordner") };
        if !ist_id(id) {
            return fehler("Ungültiger Stand");
        }
        let (lager, heim, daten) = {
            let g = self.g.lock().unwrap();
            (g.orte.lager.clone(), g.orte.heim.clone(), g.daten.clone())
        };
        let eintraege: Vec<(String, bool, u64, i64)> = if quelle == "s" {
            let basis = format!("{}/{}/{}", lager, id, name);
            let dir = if rel.is_empty() { basis.clone() } else { format!("{}/{}", basis, rel) };
            // nicht über Verknüpfungen aus dem Stand hinaus
            match (fs::canonicalize(&dir), fs::canonicalize(&basis)) {
                (Ok(d), Ok(b)) if d.starts_with(&b) => {}
                _ => return fehler("Ordner gibt es in diesem Stand nicht"),
            }
            let Ok(it) = fs::read_dir(&dir) else { return fehler("Ordner gibt es in diesem Stand nicht") };
            it.flatten().filter_map(|e| {
                let m = e.path().symlink_metadata().ok()?;
                Some((e.file_name().to_string_lossy().into_owned(), m.is_dir(), m.len(), m.mtime() * 1000))
            }).collect()
        } else {
            let Ok(_f) = self.frei.try_lock() else { return fehler("Die Sicherung läuft gerade – bitte kurz warten.") };
            let abs = format!("{}/{}{}", heim, name, if rel.is_empty() { String::new() } else { format!("/{}", rel) });
            match sicherung::ordner(&daten, id, &abs) {
                Ok(l) => l,
                Err(e) => return fehler(&e),
            }
        };
        let l: Vec<J> = eintraege.into_iter().map(|(n, o, g, z)| J::o(vec![("name", J::t(n)), ("ordner", J::B(o)), ("groesse", J::I(g as i64)), ("zeit", J::I(z))])).collect();
        ok(vec![("eintraege", J::L(l))])
    }

    /// privates Fach in der Ablage (nur root, bis es dem Benutzer übergeben wird)
    fn fach_neu(&self) -> Result<String, String> {
        let ablage = self.g.lock().unwrap().ablage.clone();
        let _ = fs::create_dir_all(&ablage);
        let _ = fs::set_permissions(&ablage, fs::Permissions::from_mode(0o711));
        let fach = format!("{}/{}", ablage, schloss::hex(&schloss::zufall(12)));
        fs::create_dir(&fach).map_err(|_| "Ablage ließ sich nicht anlegen".to_string())?;
        let _ = fs::set_permissions(&fach, fs::Permissions::from_mode(0o700));
        Ok(fach)
    }

    /// Inhalt des Fachs dem Benutzer übergeben und MIT DEN RECHTEN DES BENUTZERS nach `ziel` kopieren
    /// (so kann eine Verknüpfung im Benutzerordner nie dazu führen, dass root woanders hinschreibt).
    /// Das Fach wird danach immer entfernt.
    fn einsortieren(uid: u32, gid: u32, fach: &str, oberstes: &str, inhalt: &str, ziel: &str) -> Result<(), String> {
        let besitzer = format!("{}:{}", uid, gid);
        let _ = datei::befehl("chown", &["-R", "-h", &besitzer, oberstes], 3600);
        let _ = datei::befehl("chown", &[&besitzer, fach], 10);
        let als = |args: &[&str]| -> bool {
            let mut a = vec![format!("--reuid={}", uid), format!("--regid={}", gid), "--clear-groups".to_string(), "--".to_string()];
            a.extend(args.iter().map(|s| s.to_string()));
            let r: Vec<&str> = a.iter().map(|s| s.as_str()).collect();
            matches!(datei::befehl("setpriv", &r, 7200), Some((0, _)))
        };
        let eltern = Path::new(ziel).parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
        let gut = als(&["mkdir", "-p", &eltern]) && als(&["cp", "-a", "--reflink=auto", "--no-target-directory", inhalt, ziel]);
        let _ = datei::befehl("rm", &["-rf", "--one-file-system", fach], 3600);
        if gut { Ok(()) } else { Err("Einsortieren in deinen Ordner fehlgeschlagen".into()) }
    }

    /// freier Name: „Brief.txt“ → „Brief (zurückgeholt).txt“ → „Brief (zurückgeholt 2).txt“ …
    fn freier_name(ziel: &str, zusatz: &str, endung_trennen: bool) -> String {
        if Path::new(ziel).symlink_metadata().is_err() {
            return ziel.to_string();
        }
        let (eltern, name) = ziel.rsplit_once('/').unwrap_or(("", ziel));
        let (stamm, endung) = match name.rsplit_once('.') {
            Some((s, e)) if endung_trennen && !s.is_empty() && e.len() <= 8 => (s.to_string(), format!(".{}", e)),
            _ => (name.to_string(), String::new()),
        };
        for n in 1..1000 {
            let z = if zusatz.is_empty() {
                format!("{}/{} {}{}", eltern, stamm, n + 1, endung)
            } else {
                format!("{}/{} ({}{}){}", eltern, stamm, zusatz, if n == 1 { String::new() } else { format!(" {}", n) }, endung)
            };
            if Path::new(&z).symlink_metadata().is_err() {
                return z;
            }
        }
        format!("{}/{} ({})", eltern, stamm, schloss::hex(&schloss::zufall(3)))
    }

    /// Datei/Ordner zurückholen – Vorhandenes wird nie überschrieben („… (zurückgeholt)“).
    /// Leerer Pfad + Ordnername = den ganzen Stand in einen eigenen Ordner zurückholen.
    fn zurueckholen(&self, uid: u32, quelle: &str, id: &str, pfad: &str, ordnername: &str) -> String {
        let (Some((name, gid)), Some(rel)) = (self.heim_name(uid), sauber(pfad)) else { return fehler("Ungültiger Pfad") };
        let ganz = rel.is_empty();
        if !ist_id(id) || (ganz && !ordnername_ok(ordnername)) {
            return fehler("Ungültige Auswahl");
        }
        let (lager, heim, daten) = {
            let g = self.g.lock().unwrap();
            (g.orte.lager.clone(), g.orte.heim.clone(), g.daten.clone())
        };
        let fach = match self.fach_neu() {
            Ok(f) => f,
            Err(e) => return fehler(&e),
        };
        let weg = || {
            let _ = datei::befehl("rm", &["-rf", "--one-file-system", &fach], 3600);
        };
        let basisname = if ganz { name.clone() } else { rel.rsplit('/').next().unwrap_or(&rel).to_string() };
        // 1) als root aus dem Stand in die Ablage
        let (inhalt, oberstes) = if quelle == "s" {
            let basis = format!("{}/{}/{}", lager, id, name);
            let q = if ganz { basis.clone() } else { format!("{}/{}", basis, rel) };
            match fs::canonicalize(Path::new(&q).parent().unwrap_or(Path::new("/"))) {
                Ok(p) if (ganz || p.starts_with(&basis)) && Path::new(&q).symlink_metadata().is_ok() => {}
                _ => {
                    weg();
                    return fehler("Das gibt es in diesem Stand nicht");
                }
            }
            if !matches!(datei::befehl("cp", &["-a", "--reflink=auto", &q, &format!("{}/", fach)], 7200), Some((0, _))) {
                weg();
                return fehler("Kopieren aus dem Schnappschuss fehlgeschlagen");
            }
            (format!("{}/{}", fach, basisname), format!("{}/{}", fach, basisname))
        } else {
            let Ok(_f) = self.frei.try_lock() else {
                weg();
                return fehler("Die Sicherung läuft gerade – bitte kurz warten.");
            };
            let abs = if ganz { format!("{}/{}", heim, name) } else { format!("{}/{}/{}", heim, name, rel) };
            if let Err(e) = sicherung::auspacken(&daten, id, &abs, &fach) {
                weg();
                return fehler(&e);
            }
            let erstes = abs.trim_start_matches('/').split('/').next().unwrap_or("").to_string();
            (format!("{}{}", fach, abs), format!("{}/{}", fach, erstes))
        };
        if Path::new(&inhalt).symlink_metadata().is_err() {
            weg();
            return fehler("Nichts zum Zurückholen gefunden");
        }
        // 2) freien Namen suchen, 3) als Benutzer einsortieren
        let ziel = if ganz {
            Dienst::freier_name(&format!("{}/{}/{}", heim, name, ordnername), "", false)
        } else {
            Dienst::freier_name(&format!("{}/{}/{}", heim, name, rel), "zurückgeholt", true)
        };
        if let Err(e) = Dienst::einsortieren(uid, gid, &fach, &oberstes, &inhalt, &ziel) {
            return fehler(&e);
        }
        let anzeigen = ziel.trim_start_matches(&format!("{}/{}/", heim, name)).to_string();
        ok(vec![("text", J::t(format!("Zurückgeholt: {}", anzeigen))), ("pfad", J::t(ziel))])
    }

    /// Alle Stände, in denen es diese Datei gibt – gleiche Fassungen nur einmal (neueste zuerst)
    fn versionen(&self, uid: u32, pfad: &str) -> String {
        let (Some((name, _)), Some(rel)) = (self.heim_name(uid), sauber(pfad)) else { return fehler("Ungültiger Pfad") };
        if rel.is_empty() {
            return fehler("Ungültiger Pfad");
        }
        let (orte_liste, lager) = {
            let g = self.g.lock().unwrap();
            (schnappschuss::liste(&g.orte), g.orte.lager.clone())
        };
        let mut l = Vec::new();
        let mut zuletzt: Option<(u64, i64)> = None;
        for s in orte_liste.iter().rev() {
            let basis = format!("{}/{}/{}", lager, s, name);
            let q = format!("{}/{}", basis, rel);
            let Ok(m) = Path::new(&q).symlink_metadata() else { continue };
            match fs::canonicalize(Path::new(&q).parent().unwrap_or(Path::new("/"))) {
                Ok(p) if p.starts_with(&basis) => {}
                _ => continue,
            }
            let fassung = (m.len(), m.mtime());
            if zuletzt == Some(fassung) {
                continue;
            }
            zuletzt = Some(fassung);
            l.push(J::o(vec![("quelle", J::t("s")), ("id", J::t(s.to_string())), ("zeit", J::I(s * 1000)),
                             ("groesse", J::I(m.len() as i64)), ("geaendert", J::I(m.mtime() * 1000)), ("ordner", J::B(m.is_dir()))]));
        }
        ok(vec![("versionen", J::L(l))])
    }

    /// Nach einem Erpresser-Angriff: was hat sich seit `seit` gegenüber dem letzten sauberen Schnappschuss
    /// verändert oder ist verschwunden?
    fn rettung_suchen(&self, uid: u32, seit_ms: i64) -> Result<(i64, String, Vec<String>), String> {
        let (name, _) = self.heim_name(uid).ok_or("Benutzerordner unbekannt")?;
        let (liste, lager, heim) = {
            let g = self.g.lock().unwrap();
            (schnappschuss::liste(&g.orte), g.orte.lager.clone(), g.orte.heim.clone())
        };
        let stand = *liste.iter().filter(|s| **s * 1000 < seit_ms).last().ok_or("Es gibt keinen Schnappschuss von vor dem Angriff.")?;
        let basis = format!("{}/{}/{}", lager, stand, name);
        let jetzt = format!("{}/{}", heim, name);
        let seit = seit_ms / 1000;
        let mut l = Vec::new();
        let mut stapel = vec![String::new()];
        let mut gesehen = 0usize;
        while let Some(rel) = stapel.pop() {
            let Ok(it) = fs::read_dir(if rel.is_empty() { basis.clone() } else { format!("{}/{}", basis, rel) }) else { continue };
            for e in it.flatten() {
                gesehen += 1;
                if gesehen > 300_000 {
                    break;
                }
                let n = e.file_name().to_string_lossy().into_owned();
                let r = if rel.is_empty() { n.clone() } else { format!("{}/{}", rel, n) };
                if r == ".cache" || r == ".local/share/Trash" {
                    continue;
                }
                let Ok(m) = e.path().symlink_metadata() else { continue };
                if m.is_dir() {
                    stapel.push(r);
                } else if m.is_file() {
                    let geaendert = match Path::new(&format!("{}/{}", jetzt, r)).symlink_metadata() {
                        Err(_) => true,
                        Ok(h) => h.mtime() >= seit && (h.len() != m.len() || h.mtime() != m.mtime()),
                    };
                    if geaendert {
                        l.push(r);
                    }
                }
            }
        }
        l.sort();
        Ok((stand, name, l))
    }

    fn rettung(&self, uid: u32, seit_ms: i64) -> String {
        match self.rettung_suchen(uid, seit_ms) {
            Ok((stand, _, l)) => ok(vec![("stand", J::t(stand.to_string())), ("zeit", J::I(stand * 1000)), ("anzahl", J::I(l.len() as i64)),
                                         ("beispiele", J::texte(&l.iter().take(14).cloned().collect::<Vec<_>>()))]),
            Err(e) => fehler(&e),
        }
    }

    /// betroffene Dateien aus dem sauberen Stand in einen eigenen Ordner „Gerettet …“ zurückholen
    fn rettung_los(&self, uid: u32, seit_ms: i64, ordnername: &str) -> String {
        if !ordnername_ok(ordnername) {
            return fehler("Ungültiger Ordnername");
        }
        let (stand, name, l) = match self.rettung_suchen(uid, seit_ms) {
            Ok(x) => x,
            Err(e) => return fehler(&e),
        };
        if l.is_empty() {
            return fehler("Keine betroffenen Dateien gefunden.");
        }
        let Some((_, gid)) = self.heim_name(uid) else { return fehler("Benutzerordner unbekannt") };
        let (lager, heim) = {
            let g = self.g.lock().unwrap();
            (g.orte.lager.clone(), g.orte.heim.clone())
        };
        let fach = match self.fach_neu() {
            Ok(f) => f,
            Err(e) => return fehler(&e),
        };
        let inhalt = format!("{}/gerettet", fach);
        let mut kopiert = 0;
        for r in &l {
            let von = format!("{}/{}/{}/{}", lager, stand, name, r);
            let nach = format!("{}/{}", inhalt, r);
            if let Some(p) = Path::new(&nach).parent() {
                let _ = fs::create_dir_all(p);
            }
            // std::fs::copy nutzt auf btrfs „reflink“ – kostet keinen Platz
            if fs::copy(&von, &nach).is_ok() {
                if let Ok(m) = Path::new(&von).symlink_metadata() {
                    if let (Ok(f), Ok(t)) = (fs::File::options().write(true).open(&nach), m.modified()) {
                        let _ = f.set_modified(t);
                    }
                }
                kopiert += 1;
            }
        }
        if kopiert == 0 {
            let _ = datei::befehl("rm", &["-rf", "--one-file-system", &fach], 600);
            return fehler("Nichts ließ sich kopieren");
        }
        let ziel = Dienst::freier_name(&format!("{}/{}/{}", heim, name, ordnername), "", false);
        if let Err(e) = Dienst::einsortieren(uid, gid, &fach, &inhalt, &inhalt, &ziel) {
            return fehler(&e);
        }
        ok(vec![("text", J::t(format!("{} Dateien gerettet nach „{}“", kopiert, ziel.rsplit('/').next().unwrap_or("")))), ("pfad", J::t(ziel))])
    }

    /// Neuer Rechner / neu eingerichtet: Notfall-Schlüssel der Festplatte übernehmen
    fn notfall_eingeben(&self, schluessel: &str) -> String {
        let s: String = schluessel.trim().to_uppercase().chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').collect();
        if s.replace('-', "").len() < 20 {
            return fehler("Der Notfall-Schlüssel ist zu kurz.");
        }
        let lw = sicherung::laufwerk();
        if lw.is_empty() {
            return fehler("Bitte die Festplatte AURILIUX anschließen.");
        }
        let Ok(_f) = self.frei.try_lock() else { return fehler("Die Sicherung läuft gerade – bitte kurz warten.") };
        let daten = self.g.lock().unwrap().daten.clone();
        match sicherung::schluessel_pruefen(&daten, &lw, &s) {
            Ok(()) => {
                let _ = datei::schreiben(&format!("{}/schluessel", daten), format!("{}\n", s).as_bytes(), 0o600);
                let mut z = self.sz.lock().unwrap();
                z.ergebnis.clear();
                ok(vec![("text", J::t("Schlüssel passt – die Sicherungen auf der Festplatte sind jetzt erreichbar."))])
            }
            Err(e) => fehler(&e),
        }
    }

    fn kunde(&self, s: UnixStream) {
        let _ = s.set_nonblocking(false);
        let _ = s.set_read_timeout(Some(Duration::from_secs(3)));
        let _ = s.set_write_timeout(Some(Duration::from_secs(10)));
        let Some((pid, uid)) = sys::gegenueber(s.as_raw_fd()) else { return };
        if uid != 0 && !(1000..60000).contains(&uid) {
            return;
        }
        let mut zeile = String::new();
        if BufReader::new((&s).take(4096)).read_line(&mut zeile).is_err() {
            return;
        }
        let teile: Vec<&str> = zeile.trim_end_matches(['\n', '\r']).split('\t').collect();
        let vertraut = uid == 0 || sys::programm_von(pid).map(|p| p == SHELL).unwrap_or(false);
        let antwort = match teile.as_slice() {
            ["status"] => self.status().text(),
            _ if !vertraut => fehler("Nur die Auriliux-Oberfläche darf den Tresor bedienen."),
            ["schnappschuss-jetzt"] => {
                let r = { let g = self.g.lock().unwrap(); schnappschuss::aufnehmen(&g.orte) };
                match r {
                    Ok(_) => ok(vec![("text", J::t("Schnappschuss aufgenommen"))]),
                    Err(e) => fehler(&e),
                }
            }
            ["sichern-jetzt"] => {
                if sicherung::laufwerk().is_empty() {
                    fehler("Bitte die Festplatte AURILIUX anschließen.")
                } else if self.sichern_starten() {
                    ok(vec![("text", J::t("Sicherung läuft"))])
                } else {
                    fehler("Die Sicherung läuft bereits.")
                }
            }
            ["code-neu", code] => {
                let mut g = self.g.lock().unwrap();
                if g.schloss.gesetzt() {
                    fehler("Es gibt schon einen Code.")
                } else {
                    match g.schloss.setzen(code) {
                        Ok(()) => {
                            let karte = g.schloss.karte_ausgeben(uid);
                            let notfall = sicherung::schluessel(&g.daten);
                            ok(vec![("karte", J::t(karte)), ("notfall", J::t(notfall))])
                        }
                        Err(e) => fehler(&e),
                    }
                }
            }
            ["oeffnen", code] => {
                let mut g = self.g.lock().unwrap();
                match g.schloss.pruefen(code) {
                    Ok(()) => {
                        let karte = g.schloss.karte_ausgeben(uid);
                        ok(vec![("karte", J::t(karte))])
                    }
                    Err((t, bis)) => J::o(vec![("ok", J::B(false)), ("fehler", J::t(t)), ("gesperrtBis", J::I(bis))]).text(),
                }
            }
            ["schliessen", karte] => {
                self.g.lock().unwrap().schloss.karte_weg(karte);
                ok(vec![])
            }
            [befehl, karte, rest @ ..] if !self.karte(karte, uid) => {
                let _ = (befehl, rest);
                fehler("Der Tresor ist verschlossen – bitte den Code eingeben.")
            }
            ["code-aendern", _, neu] => {
                let mut g = self.g.lock().unwrap();
                match g.schloss.setzen(neu) {
                    Ok(()) => {
                        let karte = g.schloss.karte_ausgeben(uid);
                        ok(vec![("karte", J::t(karte)), ("text", J::t("Neuer Code gespeichert"))])
                    }
                    Err(e) => fehler(&e),
                }
            }
            ["notfall", _] => {
                let d = self.g.lock().unwrap().daten.clone();
                ok(vec![("notfall", J::t(sicherung::schluessel(&d)))])
            }
            ["liste", _] => self.liste(),
            ["ordner", _, quelle, id, pfad] => self.ordner(uid, quelle, id, pfad),
            ["zurueckholen", _, quelle, id, pfad] => self.zurueckholen(uid, quelle, id, pfad, ""),
            ["alles", _, quelle, id, ordnername] => self.zurueckholen(uid, quelle, id, "", ordnername),
            ["versionen", _, pfad] => self.versionen(uid, pfad),
            ["rettung", _, seit] => self.rettung(uid, seit.parse().unwrap_or(0)),
            ["rettung-los", _, seit, ordnername] => self.rettung_los(uid, seit.parse().unwrap_or(0), ordnername),
            ["notfall-eingeben", _, schluessel] => self.notfall_eingeben(schluessel),
            _ => fehler("Unbekannter Befehl"),
        };
        let _ = (&s).write_all(antwort.as_bytes());
        let _ = (&s).write_all(b"\n");
    }

    /// stündlich Schnappschuss, ausdünnen, bei wenig Platz alte löschen
    fn pflege(&self) {
        let mut g = self.g.lock().unwrap();
        if !schnappschuss::hindernis(&g.orte).is_empty() {
            return;
        }
        let jetzt = datei::jetzt_ms() / 1000;
        let alle = schnappschuss::liste(&g.orte);
        let letzter = alle.last().copied().unwrap_or(0);
        if jetzt - letzter >= 3600 {
            match schnappschuss::aufnehmen(&g.orte) {
                Ok(s) => {
                    g.letzter = s;
                    g.fehler.clear();
                }
                Err(e) => g.fehler = e,
            }
        }
        for s in schnappschuss::ausduennen(&schnappschuss::liste(&g.orte), jetzt) {
            let _ = schnappschuss::entfernen(&g.orte, s);
        }
        // weniger als 8 % frei → älteste weg (mindestens 3 bleiben)
        let mut l = schnappschuss::liste(&g.orte);
        while l.len() > 3 && schnappschuss::frei_prozent(&g.orte.heim).map(|f| f < 8.0).unwrap_or(false) {
            let _ = schnappschuss::entfernen(&g.orte, l.remove(0));
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let hat = |a: &str| args.iter().any(|x| x == a);
    if unsafe { sys::geteuid() } != 0 {
        eprintln!("Tresor: braucht root-Rechte");
        std::process::exit(1);
    }
    // für Tests: alles unter einem anderen Wurzelordner
    let wurzel = std::env::var("AURILIUX_TRESOR_WURZEL").unwrap_or_default();
    let orte = schnappschuss::Orte::neu(&wurzel);
    if hat("--vorbereiten") {
        match schnappschuss::vorbereiten(&orte) {
            Ok(t) => println!("Tresor: Benutzerordner {}", t),
            Err(e) => {
                eprintln!("Tresor: Vorbereiten nicht möglich: {}", e);
                std::process::exit(2);
            }
        }
        return;
    }
    let daten = format!("{}/var/lib/auriliux/tresor", wurzel);
    let laufzeit = format!("{}/run/auriliux/tresor", wurzel);
    for (o, m) in [(&daten, 0o700), (&laufzeit, 0o755)] {
        let _ = fs::create_dir_all(o);
        let _ = fs::set_permissions(o, fs::Permissions::from_mode(m));
    }
    if hat("--schnappschuss") {
        match schnappschuss::aufnehmen(&orte) {
            Ok(s) => println!("{}", s),
            Err(e) => {
                eprintln!("Tresor: {}", e);
                std::process::exit(2);
            }
        }
        return;
    }
    let d = Dienst {
        g: Arc::new(Mutex::new(Gemeinsam {
            schloss: schloss::Schloss::laden(&daten),
            ablage: format!("{}/var/lib/auriliux/tresor-ablage", wurzel),
            daten: daten.clone(),
            orte,
            letzter: 0,
            fehler: String::new(),
        })),
        sz: Arc::new(Mutex::new(sicherung::zustand_laden(&daten))),
        frei: Arc::new(Mutex::new(())),
    };
    if hat("--einmal") {
        println!("{}", d.status().text());
        return;
    }

    sys::signale_abfangen();
    let sock = format!("{}/steuerung.sock", laufzeit);
    let _ = fs::remove_file(&sock);
    let hoerer = match UnixListener::bind(&sock) {
        Ok(h) => {
            let _ = fs::set_permissions(&sock, fs::Permissions::from_mode(0o666));
            let _ = h.set_nonblocking(true);
            h
        }
        Err(e) => {
            eprintln!("Tresor: Steuerung nicht verfügbar: {}", e);
            std::process::exit(1);
        }
    };
    eprintln!("Tresor läuft (Schnappschüsse: {})", {
        let h = schnappschuss::hindernis(&d.g.lock().unwrap().orte);
        if h.is_empty() { "bereit".to_string() } else { h }
    });
    // (kein Instant::now() - x: kurz nach dem Hochfahren wäre das kleiner als null → Absturz)
    let mut pflege: Option<Instant> = None;
    let mut laufwerk_vorher = false;
    let mut status_vorher = String::new();
    let mut status_zeit: Option<Instant> = None;
    while !sys::ende() {
        let mut fds = [sys::PollFd { fd: hoerer.as_raw_fd(), events: sys::POLLIN, revents: 0 }];
        sys::warte(&mut fds, 1000);
        while let Ok((s, _)) = hoerer.accept() {
            let d2 = d.clone();
            std::thread::spawn(move || d2.kunde(s));
        }
        if pflege.map(|p| p.elapsed() >= Duration::from_secs(60)).unwrap_or(true) {
            pflege = Some(Instant::now());
            let d2 = d.clone();
            std::thread::spawn(move || d2.pflege());
            // Festplatte angeschlossen → sichern, wenn die letzte Sicherung älter als 6 Stunden ist
            // (nach einem Fehler frühestens eine Stunde später erneut)
            let lw = !sicherung::laufwerk().is_empty();
            let z = d.sz.lock().unwrap().clone();
            let alt = datei::jetzt_ms() - z.letzte > 6 * 3_600_000;
            if lw && alt && !z.laeuft && (z.ergebnis == "ok" || z.ergebnis.is_empty() || !laufwerk_vorher || pflege_stunde()) {
                d.sichern_starten();
            }
            laufwerk_vorher = lw;
        }
        // Status für die Oberfläche (ohne Geheimnisse)
        if status_zeit.map(|p| p.elapsed() >= Duration::from_secs(2)).unwrap_or(true) {
            status_zeit = Some(Instant::now());
            let mut j = d.status().text();
            if j != status_vorher {
                let _ = datei::schreiben(&format!("{}/status.json", laufzeit), j.as_bytes(), 0o644);
                status_vorher = std::mem::take(&mut j);
            }
        }
    }
    let _ = fs::remove_file(&sock);
}

/// einmal pro Stunde (Minute 0) – für den erneuten Versuch nach einem Fehler
fn pflege_stunde() -> bool {
    (datei::jetzt_ms() / 60_000) % 60 == 0
}
