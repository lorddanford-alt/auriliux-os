//! Dateien sicher schreiben, kleine Dateien lesen, Hilfsprogramme mit Zeitgrenze ausführen.
use std::fs::{self, OpenOptions, Permissions};
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// erst in eine Nebendatei schreiben, dann umbenennen – Leser sehen nie eine halbe Datei
pub fn schreiben(pfad: &str, inhalt: &[u8], modus: u32) -> std::io::Result<()> {
    let neu = format!("{}.neu", pfad);
    {
        let mut f = OpenOptions::new().write(true).create(true).truncate(true).mode(modus).open(&neu)?;
        f.write_all(inhalt)?;
    }
    fs::set_permissions(&neu, Permissions::from_mode(modus))?;
    fs::rename(&neu, pfad)
}

pub fn lies(pfad: impl AsRef<Path>) -> String {
    fs::read_to_string(pfad).unwrap_or_default()
}

pub fn lies_zahl(pfad: impl AsRef<Path>) -> Option<f64> {
    lies(pfad).trim().parse().ok()
}

pub fn jetzt_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// Hilfsprogramm ohne Shell starten, höchstens `sek` Sekunden warten. (Rückgabecode, Ausgabe)
pub fn befehl(prog: &str, args: &[&str], sek: u64) -> Option<(i32, String)> {
    let mut kind = Command::new(prog)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut aus = kind.stdout.take()?;
    let leser = std::thread::spawn(move || {
        let mut s = Vec::new();
        let _ = aus.read_to_end(&mut s);
        s
    });
    let ende = Instant::now() + Duration::from_secs(sek);
    let code = loop {
        match kind.try_wait() {
            Ok(Some(st)) => break st.code().unwrap_or(-1),
            Ok(None) => {
                if Instant::now() > ende {
                    let _ = kind.kill();
                    let _ = kind.wait();
                    return None;
                }
                std::thread::sleep(Duration::from_millis(25));
            }
            Err(_) => return None,
        }
    };
    let s = leser.join().ok()?;
    Some((code, String::from_utf8_lossy(&s).into_owned()))
}

/// schneller, nicht-kryptografischer Fingerabdruck (FNV-1a) für „hat sich der Inhalt geändert?“
pub fn fingerabdruck(daten: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in daten {
        h ^= b as u64;
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    h
}

/// Zahl mit Komma (deutsch)
pub fn komma(x: f64, stellen: usize) -> String {
    format!("{:.*}", stellen, x).replace('.', ",")
}

/// Bytes lesbar (MB/GB)
pub fn groesse(b: u64) -> String {
    if b >= 1_000_000_000 {
        format!("{} GB", komma(b as f64 / 1e9, 1))
    } else {
        format!("{} MB", (b as f64 / 1e6).round().max(1.0) as u64)
    }
}

/// Feld aus einem Ein-Zeilen-Format „schluessel=wert“ (z. B. /proc/pressure)
pub fn feld_nach<'a>(text: &'a str, schluessel: &str) -> Option<&'a str> {
    let i = text.find(schluessel)? + schluessel.len();
    text[i..].split_whitespace().next()
}
