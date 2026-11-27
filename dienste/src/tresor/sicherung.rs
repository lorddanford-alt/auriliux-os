//! Sicherung auf die externe Festplatte „AURILIUX“: verschlüsselt (AES-256) und ohne doppelte Daten mit restic –
//! einem bewährten Sicherungsprogramm (Verschlüsselung baut man nicht selbst). Der Schlüssel liegt nur für root
//! lesbar auf dem Mac; zusätzlich bekommst du ihn einmal als Notfall-Schlüssel zum Aufschreiben.
use crate::schloss;
use gemeinsam::datei;
use gemeinsam::json::{self, J};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

pub const ORDNER: &str = "Auriliux-Tresor";
const CACHE: &str = "/var/cache/auriliux-tresor";

#[derive(Clone, Default)]
pub struct Zustand {
    pub laeuft: bool,
    pub prozent: f64,
    pub letzte: i64,           // ms
    pub ergebnis: String,      // "ok" oder Fehlertext
    pub anzahl: i64,
}

/// Einhängepunkt der Festplatte „AURILIUX“ (USB, vom Benutzer eingehängt) oder leer
pub fn laufwerk() -> String {
    for z in datei::lies("/proc/self/mounts").lines() {
        let f: Vec<&str> = z.split_whitespace().collect();
        if f.len() < 2 {
            continue;
        }
        let mp = f[1].replace("\\040", " ");
        if mp.rsplit('/').next() == Some("AURILIUX") && (mp.starts_with("/run/media/") || mp.starts_with("/media/") || mp.starts_with("/mnt/")) {
            return mp;
        }
    }
    String::new()
}

pub fn ablage(laufwerk: &str) -> String {
    format!("{}/{}", laufwerk, ORDNER)
}

/// Schlüssel für die verschlüsselte Sicherung; beim ersten Mal erzeugt (Notfall-Schlüssel, 32 Zeichen)
pub fn schluessel(daten: &str) -> String {
    let p = format!("{}/schluessel", daten);
    let s = datei::lies(&p).trim().to_string();
    if s.len() >= 20 {
        return s;
    }
    const ZEICHEN: &[u8] = b"ABCDEFGHJKMNPQRSTVWXYZ0123456789";   // ohne I, L, O, U – nicht verwechselbar
    let z = schloss::zufall(32);
    let roh: String = z.iter().map(|b| ZEICHEN[(*b as usize) % 32] as char).collect();
    let neu = roh.as_bytes().chunks(4).map(|c| String::from_utf8_lossy(c).into_owned()).collect::<Vec<_>>().join("-");
    let _ = datei::schreiben(&p, format!("{}\n", neu).as_bytes(), 0o600);
    neu
}

fn restic(daten: &str, laufwerk: &str, args: &[&str]) -> Command {
    let mut c = Command::new("restic");
    c.arg("-r").arg(ablage(laufwerk))
        .arg("--password-file").arg(format!("{}/schluessel", daten))
        .arg("--cache-dir").arg(CACHE)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(Stdio::null());
    c
}

fn ausfuehren(daten: &str, laufwerk: &str, args: &[&str]) -> Result<String, String> {
    let aus = restic(daten, laufwerk, args).stdout(Stdio::piped()).stderr(Stdio::piped()).output().map_err(|e| format!("restic fehlt: {}", e))?;
    if aus.status.success() {
        Ok(String::from_utf8_lossy(&aus.stdout).into_owned())
    } else {
        let f = String::from_utf8_lossy(&aus.stderr);
        Err(f.lines().filter(|z| !z.trim().is_empty()).last().unwrap_or("restic-Fehler").to_string())
    }
}

/// Sicherung durchführen (läuft lange – im eigenen Faden aufrufen). Hält `frei` während der ganzen Zeit.
pub fn sichern(daten: &str, heim: &str, zustand: &Arc<Mutex<Zustand>>, frei: &Arc<Mutex<()>>) {
    let Ok(_belegt) = frei.try_lock() else { return };
    let lw = laufwerk();
    let ende = |ergebnis: String, anzahl: Option<i64>| {
        let mut z = zustand.lock().unwrap();
        z.laeuft = false;
        z.prozent = 0.0;
        z.ergebnis = ergebnis;
        if z.ergebnis == "ok" {
            z.letzte = datei::jetzt_ms();
        }
        if let Some(a) = anzahl {
            z.anzahl = a;
        }
        let _ = datei::schreiben(&format!("{}/sicherung.json", daten),
                                 J::o(vec![("letzte", J::I(z.letzte)), ("ergebnis", J::t(z.ergebnis.clone())), ("anzahl", J::I(z.anzahl))]).text().as_bytes(), 0o600);
    };
    if lw.is_empty() {
        ende("Festplatte AURILIUX nicht angeschlossen".into(), None);
        return;
    }
    {
        let mut z = zustand.lock().unwrap();
        z.laeuft = true;
        z.prozent = 0.0;
    }
    let _ = fs::create_dir_all(CACHE);
    schluessel(daten);
    if !Path::new(&format!("{}/config", ablage(&lw))).exists() {
        if let Err(e) = ausfuehren(daten, &lw, &["init"]) {
            ende(format!("Einrichten fehlgeschlagen: {}", e), None);
            return;
        }
    }
    let mut kind = match restic(daten, &lw, &[
        "backup", heim, "--json", "--host", "auriliux", "--tag", "auriliux",
        "--exclude-caches", "--exclude", &format!("{}/*/.cache", heim),
        "--exclude", &format!("{}/*/.local/share/Trash", heim),
    ]).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
        Ok(k) => k,
        Err(e) => {
            ende(format!("restic fehlt: {}", e), None);
            return;
        }
    };
    if let Some(aus) = kind.stdout.take() {
        for z in BufReader::new(aus).lines().map_while(Result::ok) {
            if let Some(j) = json::lesen(&z) {
                if j.text_von("message_type") == "status" {
                    let p = match j.feld("percent_done") { Some(J::Z(p)) => *p, Some(J::I(i)) => *i as f64, _ => -1.0 };
                    if p >= 0.0 {
                        zustand.lock().unwrap().prozent = p;
                    }
                }
            }
        }
    }
    let fehler = kind.stderr.take().map(|e| {
        let mut s = String::new();
        let _ = std::io::Read::read_to_string(&mut BufReader::new(e), &mut s);
        s
    }).unwrap_or_default();
    let ok = kind.wait().map(|s| s.success() || s.code() == Some(3)).unwrap_or(false);   // 3 = einzelne Dateien nicht lesbar
    if !ok {
        if fehler.contains("wrong password") || fehler.contains("no key found") {
            ende("schluessel-falsch".into(), None);
            return;
        }
        ende(fehler.lines().filter(|z| !z.trim().is_empty()).last().unwrap_or("Sicherung fehlgeschlagen").to_string(), None);
        return;
    }
    // ältere Stände ausdünnen: 14 Tage täglich, 8 Wochen wöchentlich, 2 Jahre monatlich
    let _ = ausfuehren(daten, &lw, &["forget", "--tag", "auriliux", "--keep-daily", "14", "--keep-weekly", "8", "--keep-monthly", "24", "--prune"]);
    let anzahl = liste(daten).map(|l| l.len() as i64).ok();
    ende("ok".into(), anzahl);
}

pub fn zustand_laden(daten: &str) -> Zustand {
    let j = json::lesen(&datei::lies(format!("{}/sicherung.json", daten))).unwrap_or(J::Null);
    Zustand {
        laeuft: false,
        prozent: 0.0,
        letzte: j.feld("letzte").and_then(|x| x.als_zahl()).unwrap_or(0),
        ergebnis: j.text_von("ergebnis"),
        anzahl: j.feld("anzahl").and_then(|x| x.als_zahl()).unwrap_or(0),
    }
}

/// Passt dieser Notfall-Schlüssel zur Sicherung auf der Festplatte?
pub fn schluessel_pruefen(daten: &str, laufwerk: &str, schluessel: &str) -> Result<(), String> {
    if !Path::new(&format!("{}/config", ablage(laufwerk))).exists() {
        return Err("Auf der Festplatte gibt es noch keine Tresor-Sicherung.".into());
    }
    let probe = format!("{}/schluessel.probe", daten);
    datei::schreiben(&probe, format!("{}\n", schluessel).as_bytes(), 0o600).map_err(|e| e.to_string())?;
    let r = Command::new("restic").arg("-r").arg(ablage(laufwerk)).arg("--password-file").arg(&probe)
        .arg("--cache-dir").arg(CACHE).args(["cat", "config"]).env("LC_ALL", "C")
        .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status();
    let _ = fs::remove_file(&probe);
    match r {
        Ok(s) if s.success() => Ok(()),
        Ok(_) => Err("Dieser Schlüssel passt nicht zur Sicherung auf der Festplatte.".into()),
        Err(e) => Err(format!("restic fehlt: {}", e)),
    }
}

/// Stände in der Sicherung: (kurze ID, Zeit in Sekunden), älteste zuerst
pub fn liste(daten: &str) -> Result<Vec<(String, i64)>, String> {
    let lw = laufwerk();
    if lw.is_empty() || !Path::new(&format!("{}/config", ablage(&lw))).exists() {
        return Ok(Vec::new());
    }
    let aus = ausfuehren(daten, &lw, &["snapshots", "--json", "--tag", "auriliux"])?;
    let j = json::lesen(&aus).ok_or("Antwort von restic unlesbar")?;
    let mut l: Vec<(String, i64)> = j.als_liste().iter()
        .filter_map(|s| Some((s.text_von("short_id"), zeit_lesen(&s.text_von("time"))?)))
        .collect();
    l.sort_by_key(|x| x.1);
    Ok(l)
}

/// Inhalt eines Ordners in einem gesicherten Stand: (Name, ist Ordner, Größe, Zeit ms)
pub fn ordner(daten: &str, id: &str, pfad: &str) -> Result<Vec<(String, bool, u64, i64)>, String> {
    let lw = laufwerk();
    if lw.is_empty() {
        return Err("Festplatte AURILIUX nicht angeschlossen".into());
    }
    let aus = ausfuehren(daten, &lw, &["ls", "--json", id, pfad])?;
    let mut l = Vec::new();
    for z in aus.lines() {
        let Some(j) = json::lesen(z) else { continue };
        if j.text_von("struct_type") != "node" && j.feld("type").is_none() {
            continue;
        }
        let p = j.text_von("path");
        let eltern = p.rsplit_once('/').map(|x| x.0).unwrap_or("");
        if eltern != pfad.trim_end_matches('/') {
            continue;
        }
        let typ = j.text_von("type");
        let groesse = j.feld("size").and_then(|x| x.als_zahl()).unwrap_or(0) as u64;
        let zeit = zeit_lesen(&j.text_von("mtime")).unwrap_or(0) * 1000;
        l.push((j.text_von("name"), typ == "dir", groesse, zeit));
    }
    Ok(l)
}

/// gesicherten Pfad nach `ziel` auspacken (Ergebnis liegt dann unter ziel/<pfad>)
pub fn auspacken(daten: &str, id: &str, pfad: &str, ziel: &str) -> Result<(), String> {
    let lw = laufwerk();
    if lw.is_empty() {
        return Err("Festplatte AURILIUX nicht angeschlossen".into());
    }
    ausfuehren(daten, &lw, &["restore", id, "--target", ziel, "--include", pfad]).map(|_| ())
}

/// „2026-11-27T14:05:33.123456+01:00“ → Sekunden seit 1970 (UTC)
pub fn zeit_lesen(t: &str) -> Option<i64> {
    let b = t.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let n = |a: usize, l: usize| t.get(a..a + l)?.parse::<i64>().ok();
    let (j, mo, ta, h, mi, s) = (n(0, 4)?, n(5, 2)?, n(8, 2)?, n(11, 2)?, n(14, 2)?, n(17, 2)?);
    // Tage seit 1970 (Algorithmus nach Howard Hinnant)
    let y = if mo <= 2 { j - 1 } else { j };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if mo > 2 { mo - 3 } else { mo + 9 }) + 2) / 5 + ta - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let tage = era * 146_097 + doe - 719_468;
    let mut sek = tage * 86_400 + h * 3600 + mi * 60 + s;
    // Zeitzone am Ende: Z oder ±hh:mm
    let rest = t.get(19..)?;
    let rest = rest.trim_start_matches(|c: char| c == '.' || c.is_ascii_digit());
    if let Some(v) = rest.chars().next() {
        if v == '+' || v == '-' {
            let zh = rest.get(1..3)?.parse::<i64>().ok()?;
            let zm = rest.get(4..6).and_then(|x| x.parse::<i64>().ok()).unwrap_or(0);
            let versatz = zh * 3600 + zm * 60;
            sek -= if v == '+' { versatz } else { -versatz };
        }
    }
    Some(sek)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zeiten() {
        assert_eq!(zeit_lesen("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(zeit_lesen("2026-11-27T14:05:33.123456789+01:00"), Some(1_795_784_733));
        assert_eq!(zeit_lesen("2000-02-29T12:00:00-02:00"), Some(951_832_800));
    }
}
