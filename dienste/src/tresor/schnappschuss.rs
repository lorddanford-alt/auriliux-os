//! Schnappschüsse der Benutzerordner (/var/home) mit btrfs: schreibgeschützt, kosten fast keinen Platz
//! (nur Änderungen), entstehen in einem Augenblick. Abgelegt unter /var/lib/auriliux/schnappschuesse/<Sekunden>,
//! nur für root lesbar – an alte Stände kommt man nur über den Tresor (mit Code).
use gemeinsam::datei;
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;

pub struct Orte {
    pub heim: String,
    pub lager: String,
}

impl Orte {
    pub fn neu(wurzel: &str) -> Orte {
        Orte { heim: format!("{}/var/home", wurzel), lager: format!("{}/var/lib/auriliux/schnappschuesse", wurzel) }
    }
}

/// Dateisystem, auf dem ein Pfad liegt (längster passender Einhängepunkt)
pub fn dateisystem(pfad: &str) -> String {
    let echt = fs::canonicalize(pfad).map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| pfad.to_string());
    let mut best = (0usize, String::new());
    for z in datei::lies("/proc/self/mounts").lines() {
        let f: Vec<&str> = z.split_whitespace().collect();
        if f.len() < 3 {
            continue;
        }
        let mp = f[1].replace("\\040", " ");
        let passt = echt == mp || mp == "/" || echt.starts_with(&format!("{}/", mp));
        if passt && mp.len() >= best.0 {
            best = (mp.len(), f[2].to_string());
        }
    }
    best.1
}

/// Ist der Ordner die Wurzel eines btrfs-Teilbereichs (Subvolume)? Die haben immer die Inode-Nummer 256.
pub fn ist_teilbereich(pfad: &str) -> bool {
    dateisystem(pfad) == "btrfs" && fs::metadata(pfad).map(|m| m.ino() == 256).unwrap_or(false)
}

/// Grund, warum keine Schnappschüsse möglich sind (leer = alles bereit)
pub fn hindernis(o: &Orte) -> String {
    if !Path::new(&o.heim).is_dir() {
        return "Kein Benutzerordner gefunden".into();
    }
    if dateisystem(&o.heim) != "btrfs" {
        return "Die Festplatte nutzt kein btrfs – Schnappschüsse sind so nicht möglich".into();
    }
    if !ist_teilbereich(&o.heim) {
        return "Wird beim nächsten Neustart eingerichtet".into();
    }
    String::new()
}

fn btrfs(args: &[&str], sek: u64) -> Result<String, String> {
    match datei::befehl("btrfs", args, sek) {
        Some((0, aus)) => Ok(aus),
        Some((c, aus)) => Err(format!("btrfs {} fehlgeschlagen ({}): {}", args.join(" "), c, aus.trim())),
        None => Err("btrfs antwortet nicht".into()),
    }
}

/// alle Schnappschüsse (Sekunden seit 1970), älteste zuerst
pub fn liste(o: &Orte) -> Vec<i64> {
    let mut l: Vec<i64> = fs::read_dir(&o.lager)
        .map(|d| d.flatten().filter_map(|e| e.file_name().to_string_lossy().parse::<i64>().ok()).collect())
        .unwrap_or_default();
    l.sort();
    l
}

pub fn aufnehmen(o: &Orte) -> Result<i64, String> {
    let h = hindernis(o);
    if !h.is_empty() {
        return Err(h);
    }
    fs::create_dir_all(&o.lager).map_err(|e| e.to_string())?;
    let _ = fs::set_permissions(&o.lager, fs::Permissions::from_mode(0o700));
    let mut sek = datei::jetzt_ms() / 1000;
    while Path::new(&format!("{}/{}", o.lager, sek)).exists() {
        sek += 1;
    }
    btrfs(&["subvolume", "snapshot", "-r", &o.heim, &format!("{}/{}", o.lager, sek)], 60)?;
    Ok(sek)
}

pub fn entfernen(o: &Orte, sek: i64) -> Result<(), String> {
    btrfs(&["subvolume", "delete", &format!("{}/{}", o.lager, sek)], 120).map(|_| ())
}

/// Welche Schnappschüsse bleiben? Letzte 24 Stunden alle, dann je Tag der neueste (7 Tage),
/// dann je Woche der neueste (5 Wochen). Gibt die zu löschenden zurück.
pub fn ausduennen(alle: &[i64], jetzt: i64) -> Vec<i64> {
    let mut weg = Vec::new();
    let mut gesehen_tag = std::collections::HashSet::new();
    let mut gesehen_woche = std::collections::HashSet::new();
    let mut l = alle.to_vec();
    l.sort_by(|a, b| b.cmp(a)); // neueste zuerst
    for s in l {
        let alter = jetzt - s;
        if alter < 86_400 {
            continue;
        }
        if alter < 7 * 86_400 {
            if !gesehen_tag.insert(s / 86_400) {
                weg.push(s);
            }
            continue;
        }
        if alter < 35 * 86_400 {
            if !gesehen_woche.insert(s / (7 * 86_400)) {
                weg.push(s);
            }
            continue;
        }
        weg.push(s);
    }
    weg
}

/// freier Platz in Prozent (über df)
pub fn frei_prozent(pfad: &str) -> Option<f64> {
    let (_, aus) = datei::befehl("df", &["-P", pfad], 10)?;
    let z = aus.lines().nth(1)?;
    let p = z.split_whitespace().nth(4)?.trim_end_matches('%').parse::<f64>().ok()?;
    Some(100.0 - p)
}

/// Einmalig (beim Hochfahren, bevor sich jemand anmeldet): /var/home zu einem eigenen btrfs-Teilbereich machen.
/// Kopie mit „reflink“ – kostet weder Zeit noch Platz, die Dateien teilen sich dieselben Blöcke.
/// Bei jedem Fehler wird der alte Zustand wiederhergestellt.
pub fn vorbereiten(o: &Orte) -> Result<String, String> {
    let heim = o.heim.as_str();
    let neu = format!("{}.tresor-neu", heim);
    let alt = format!("{}.tresor-alt", heim);
    // abgebrochener früherer Versuch?
    if !Path::new(heim).exists() && Path::new(&alt).exists() {
        fs::rename(&alt, heim).map_err(|e| format!("Rückweg fehlgeschlagen: {}", e))?;
    }
    if Path::new(&neu).exists() {
        let _ = btrfs(&["subvolume", "delete", &neu], 120);
        let _ = fs::remove_dir_all(&neu);
    }
    if dateisystem(heim) != "btrfs" {
        return Ok("kein btrfs – nichts zu tun".into());
    }
    if ist_teilbereich(heim) {
        if Path::new(&alt).exists() {
            let _ = fs::remove_dir_all(&alt);
        }
        return Ok("schon bereit".into());
    }
    // niemand darf gerade angemeldet sein
    for e in fs::read_dir("/proc").into_iter().flatten().flatten() {
        if let Ok(pid) = e.file_name().to_string_lossy().parse::<i32>() {
            if gemeinsam::sys::uid_von(pid).map(|u| (1000..60000).contains(&u)).unwrap_or(false) && o.heim == "/var/home" {
                return Err("Ein Benutzer ist angemeldet – Einrichtung beim nächsten Start".into());
            }
        }
    }
    btrfs(&["subvolume", "create", &neu], 60)?;
    let rueckgaengig = |grund: String| -> String {
        let _ = btrfs(&["subvolume", "delete", &neu], 120);
        grund
    };
    let quelle = format!("{}/.", heim);
    match datei::befehl("cp", &["-a", "--reflink=always", &quelle, &format!("{}/", neu)], 3600) {
        Some((0, _)) => {}
        other => return Err(rueckgaengig(format!("Kopieren fehlgeschlagen: {:?}", other))),
    }
    for (prog, a) in [("chown", "--reference"), ("chmod", "--reference")] {
        let _ = datei::befehl(prog, &[&format!("{}={}", a, heim), &neu], 30);
    }
    let _ = datei::befehl("chcon", &[&format!("--reference={}", heim), &neu], 30);
    // Gegenprobe: gleich viele Einträge?
    let (a, b) = (zaehlen(Path::new(heim)), zaehlen(Path::new(&neu)));
    if a != b {
        return Err(rueckgaengig(format!("Gegenprobe fehlgeschlagen ({} statt {} Einträge)", b, a)));
    }
    fs::rename(heim, &alt).map_err(|e| rueckgaengig(format!("Umbenennen fehlgeschlagen: {}", e)))?;
    if let Err(e) = fs::rename(&neu, heim) {
        let _ = fs::rename(&alt, heim);
        return Err(rueckgaengig(format!("Umbenennen fehlgeschlagen: {}", e)));
    }
    let _ = fs::remove_dir_all(&alt);
    Ok(format!("eingerichtet ({} Einträge)", a))
}

fn zaehlen(p: &Path) -> u64 {
    let mut n = 0;
    let mut stapel = vec![p.to_path_buf()];
    while let Some(d) = stapel.pop() {
        if let Ok(it) = fs::read_dir(&d) {
            for e in it.flatten() {
                n += 1;
                if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    stapel.push(e.path());
                }
            }
        }
    }
    n
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ausduennen_behaelt_das_richtige() {
        let jetzt = 100 * 86_400;
        let mut alle = Vec::new();
        for h in 0..24 * 50 {
            alle.push(jetzt - h * 3600); // 50 Tage lang stündlich
        }
        let weg = ausduennen(&alle, jetzt);
        let bleiben: Vec<i64> = alle.iter().filter(|s| !weg.contains(s)).cloned().collect();
        assert_eq!(bleiben.iter().filter(|s| jetzt - **s < 86_400).count(), 24);
        assert!(bleiben.iter().filter(|s| (86_400..7 * 86_400).contains(&(jetzt - **s))).count() <= 7);
        assert!(bleiben.iter().all(|s| jetzt - s < 35 * 86_400));
        assert!(bleiben.len() < 24 + 7 + 6);
    }
}
