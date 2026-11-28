//! Bestätigen mit dem Anmelde-Passwort (für riskante Schritte: Guardian-Freigaben, Tresor-Code vergessen).
//! Geprüft wird über PAM wie bei Anmeldung und Bildschirmsperre – durch das kleine Hilfsprogramm
//! /usr/libexec/auriliux/passwort-pruefen (nur root darf es starten). Das Passwort geht über die
//! Standardeingabe, nie über die Befehlszeile. Nur Administratoren (Gruppe wheel) dürfen bestätigen.
//! Nach 3 Fehlversuchen in Folge: 60 s Pause (zusätzlich zur Wartezeit, die PAM selbst einlegt).
use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const HELFER: &str = "/usr/libexec/auriliux/passwort-pruefen";
static FEHLER: Mutex<(u32, Option<Instant>)> = Mutex::new((0, None));

/// Benutzername zu einer uid (über getent, damit auch spätere Benutzerquellen funktionieren)
pub fn name_von(uid: u32) -> Option<String> {
    let (code, aus) = crate::datei::befehl("getent", &["passwd", &uid.to_string()], 5)?;
    if code != 0 {
        return None;
    }
    let name = aus.split(':').next()?.trim().to_string();
    if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || "._-".contains(c)) {
        return None;
    }
    Some(name)
}

pub fn ist_admin(name: &str) -> bool {
    crate::datei::befehl("id", &["-nG", name], 5)
        .map(|(c, aus)| c == 0 && aus.split_whitespace().any(|g| g == "wheel"))
        .unwrap_or(false)
}

/// Ok(()) wenn das Passwort des Benutzers mit dieser uid stimmt und er Administrator ist.
pub fn pruefen(uid: u32, passwort: &str) -> Result<(), String> {
    if uid == 0 {
        return Ok(());
    }
    {
        let f = FEHLER.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(bis) = f.1 {
            if Instant::now() < bis {
                return Err(format!("Zu viele Fehlversuche – bitte {} Sekunden warten.", (bis - Instant::now()).as_secs() + 1));
            }
        }
    }
    if passwort.is_empty() || passwort.len() > 512 || passwort.contains('\n') {
        return Err("Bitte dein Passwort eingeben.".into());
    }
    let name = name_von(uid).ok_or("Benutzer unbekannt")?;
    if !ist_admin(&name) {
        return Err("Nur ein Administrator darf das bestätigen.".into());
    }
    let mut kind = Command::new(HELFER)
        .arg(&name)
        .env_clear()
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| "Passwortprüfung nicht verfügbar".to_string())?;
    if let Some(mut ein) = kind.stdin.take() {
        let _ = ein.write_all(passwort.as_bytes());
        let _ = ein.write_all(b"\n");
    }
    let ende = Instant::now() + Duration::from_secs(15);
    let code = loop {
        match kind.try_wait() {
            Ok(Some(st)) => break st.code().unwrap_or(2),
            Ok(None) if Instant::now() < ende => std::thread::sleep(Duration::from_millis(20)),
            _ => {
                let _ = kind.kill();
                let _ = kind.wait();
                break 2;
            }
        }
    };
    let mut f = FEHLER.lock().unwrap_or_else(|e| e.into_inner());
    match code {
        0 => {
            *f = (0, None);
            Ok(())
        }
        1 => {
            f.0 += 1;
            if f.0 >= 3 {
                f.1 = Some(Instant::now() + Duration::from_secs(60));
                f.0 = 0;
                Err("Falsches Passwort – jetzt 60 Sekunden Pause.".into())
            } else {
                Err("Falsches Passwort.".into())
            }
        }
        _ => Err("Passwortprüfung fehlgeschlagen".into()),
    }
}
